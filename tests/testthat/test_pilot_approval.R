pilot_bottom_units <- function() {
  tibble::tibble(
    region_code = c("NE", "NE", "N"),
    state_code = c("27", "27", "14"),
    stable_municipality_id = c("2700102", "2700201", "1400050"),
    base_level = c(100, 50, 30)
  )
}

synthetic_pilot_error_rows <- function(
    factors = c(
      seasonal_naive = 0.80,
      ets = 0.90,
      ets_wls = 0.91,
      ets_bottom_up = 0.92,
      ridge_global_bottom_up = 0.90,
      xgboost_global_bottom_up = 0.95
    ),
    origins = 1:4,
    horizons = c(1L, 3L, 6L)) {
  bottom <- tidyr::expand_grid(
    pilot_bottom_units(),
    origin = origins,
    horizon = horizons,
    .model = names(factors)
  ) |>
    dplyr::mutate(
      hierarchy_level = "municipality",
      actual = .data$base_level + .data$origin + .data$horizon,
      prediction = .data$actual * unname(factors[.data$.model])
    ) |>
    dplyr::select(-"base_level")
  sum_up <- function(data, groups, level, aggregated) {
    data |>
      dplyr::group_by(dplyr::across(dplyr::all_of(c(groups, "origin", "horizon", ".model")))) |>
      dplyr::summarise(
        actual = sum(.data$actual),
        prediction = sum(.data$prediction),
        .groups = "drop"
      ) |>
      dplyr::mutate(hierarchy_level = level, !!!stats::setNames(
        as.list(rep("__AGGREGATED__", length(aggregated))),
        aggregated
      ))
  }
  dplyr::bind_rows(
    bottom,
    sum_up(bottom, c("region_code", "state_code"), "state", "stable_municipality_id"),
    sum_up(bottom, "region_code", "region", c("state_code", "stable_municipality_id")),
    sum_up(bottom, character(), "national", c("region_code", "state_code", "stable_municipality_id"))
  ) |>
    dplyr::mutate(
      error = .data$actual - .data$prediction,
      absolute_error = abs(.data$error),
      squared_error = .data$error^2,
      mae_scale = 10,
      rmsse_scale = 12
    )
}

synthetic_pilot_panel <- function() {
  tidyr::expand_grid(
    pilot_bottom_units(),
    month = seq(as.Date("2021-01-01"), by = "month", length.out = 6L)
  ) |>
    dplyr::mutate(payer_count = .data$base_level)
}

all_pass <- function(checks) {
  nrow(checks) > 0L && all(checks$status == "PASS")
}

test_that("a coherent synthetic pilot passes C2, C3 and C4", {
  rows <- synthetic_pilot_error_rows()
  map_file <- file.path(tempdir(), "figure_forecast_gain_map_pilot_h1.png")
  writeLines("png", map_file)

  geography <- check_pilot_geography(
    calendar_gaps = tibble::tibble(stable_municipality_id = character()),
    panel = synthetic_pilot_panel(),
    expected_states = c(27, 14),
    error_rows = rows,
    map_files = map_file
  )
  predictive <- check_pilot_predictive(rows, c(27, 14), c(1L, 3L, 6L))
  reconciliation <- check_pilot_reconciliation(rows, c(1L, 3L, 6L))

  expect_true(all_pass(geography))
  expect_true(all_pass(predictive))
  expect_equal(nrow(predictive), 4L)
  expect_true(all_pass(reconciliation))
})

test_that("missing inputs are never treated as PASS", {
  expect_equal(check_pilot_predictive(NULL, c(27, 14), 1L)$status, "FAIL")
  expect_equal(check_pilot_reconciliation(NULL, 1L)$status, "FAIL")
  expect_equal(
    check_pilot_execution(NULL, character(), scope_label = NULL)$status,
    "FAIL"
  )
  geography <- check_pilot_geography(
    calendar_gaps = NULL,
    panel = NULL,
    expected_states = c(27, 14),
    error_rows = NULL,
    map_files = NULL
  )
  expect_true(all(geography$status == "FAIL"))

  summary <- summarise_pilot_approval(tibble::tibble())
  expect_equal(summary$criterion, c("C1", "C2", "C3", "C4"))
  expect_true(all(summary$status == "FAIL"))
})

test_that("C3 fails when global models do not beat the seasonal naive benchmark", {
  rows <- synthetic_pilot_error_rows(c(
    seasonal_naive = 0.95,
    ets = 0.90,
    ets_wls = 0.90,
    ets_bottom_up = 0.90,
    ridge_global_bottom_up = 0.97,
    xgboost_global_bottom_up = 0.80
  ))
  predictive <- check_pilot_predictive(rows, c(27, 14), c(1L, 3L, 6L))
  failed <- predictive |>
    dplyr::filter(.data$status == "FAIL")
  expect_equal(nrow(failed), 2L)
  expect_true(all(grepl("xgboost_global_bottom_up", failed$check)))
})

test_that("C3 does not count horizons without valid seasonal scales", {
  rows <- synthetic_pilot_error_rows() |>
    dplyr::mutate(mae_scale = 0, rmsse_scale = NA_real_)
  predictive <- check_pilot_predictive(rows, c(27, 14), c(1L, 3L, 6L))
  expect_true(all(predictive$status == "FAIL"))
})

test_that("C3 fails when a pilot state is absent", {
  rows <- synthetic_pilot_error_rows() |>
    dplyr::filter(.data$state_code != "14")
  predictive <- check_pilot_predictive(rows, c(27, 14), c(1L, 3L, 6L))
  expect_true(any(predictive$status == "FAIL"))
})

test_that("C4 fails when reconciliation worsens aggregates beyond the margin", {
  rows <- synthetic_pilot_error_rows(c(
    seasonal_naive = 0.80,
    ets = 0.95,
    ets_wls = 0.90,
    ets_bottom_up = 0.90,
    ridge_global_bottom_up = 0.90,
    xgboost_global_bottom_up = 0.95
  ))
  reconciliation <- check_pilot_reconciliation(rows, c(1L, 3L, 6L))
  expect_equal(
    reconciliation$status[grepl("does not worsen", reconciliation$check)],
    c("FAIL", "FAIL")
  )
})

test_that("C4 detects incoherent reconciled forecasts", {
  rows <- synthetic_pilot_error_rows()
  target <- rows$.model == "ets_wls" & rows$hierarchy_level == "state" &
    rows$state_code == "27" & rows$origin == 2L & rows$horizon == 3L
  rows$prediction[target] <- rows$prediction[target] + 1
  reconciliation <- check_pilot_reconciliation(rows, c(1L, 3L, 6L))
  coherence <- reconciliation[grepl("coherent", reconciliation$check), ]
  expect_equal(coherence$status, "FAIL")
  expect_match(coherence$value, "^2 incoherent")
})

test_that("C2 detects incoherent observed aggregates and map failures", {
  rows <- synthetic_pilot_error_rows()
  rows$actual[rows$hierarchy_level == "national"] <-
    rows$actual[rows$hierarchy_level == "national"] + 5
  marker <- file.path(tempdir(), "forecast_gain_map_unavailable_pilot.txt")
  writeLines("unavailable", marker)
  geography <- check_pilot_geography(
    calendar_gaps = tibble::tibble(stable_municipality_id = "2700102"),
    panel = synthetic_pilot_panel() |>
      dplyr::filter(!(.data$stable_municipality_id == "1400050" &
        .data$month == as.Date("2021-03-01"))),
    expected_states = c(27, 14),
    error_rows = rows,
    map_files = marker
  )
  expect_true(all(geography$status == "FAIL"))
})

test_that("C2 rejects a panel outside the pilot states", {
  geography <- check_pilot_geography(
    calendar_gaps = tibble::tibble(stable_municipality_id = character()),
    panel = synthetic_pilot_panel() |>
      dplyr::filter(.data$state_code == "27"),
    expected_states = c(27, 14),
    error_rows = synthetic_pilot_error_rows(),
    map_files = character()
  )
  panel_check <- geography[geography$check == "stable and balanced pilot geography", ]
  expect_equal(panel_check$status, "FAIL")
})

test_that("C1 requires error-free targets and explained warnings", {
  targets <- c("config", "all_errors", "forecast_map_files")
  meta <- tibble::tibble(
    name = targets,
    error = NA_character_,
    warnings = c(NA, NA, "The forecast-gain map was not generated")
  )
  unexplained <- check_pilot_execution(
    meta, targets, "pilot_alagoas_roraima"
  )
  expect_equal(
    unexplained$status[unexplained$check == "every warning is registered and explained"],
    "FAIL"
  )

  explained <- check_pilot_execution(
    meta, targets, "pilot_alagoas_roraima",
    warning_explanations = tibble::tibble(
      target = "forecast_map_files",
      explanation = "geobr unavailable"
    )
  )
  expect_true(all_pass(explained))

  errored <- meta
  errored$error[2] <- "boom"
  expect_true(any(check_pilot_execution(
    errored, targets, "pilot_alagoas_roraima"
  )$status == "FAIL"))
  expect_true(any(check_pilot_execution(
    meta[-1, ], targets, "pilot_alagoas_roraima",
    warning_explanations = tibble::tibble(target = "forecast_map_files", explanation = "x")
  )$status == "FAIL"))
  expect_true(any(check_pilot_execution(
    meta, targets, "national",
    warning_explanations = tibble::tibble(target = "forecast_map_files", explanation = "x")
  )$status == "FAIL"))
})

test_that("aggregated fable keys are converted to the canonical marker", {
  keys <- vctrs::new_rcrd(
    list(x = c("27", NA), agg = c(FALSE, TRUE)),
    class = "agg_vec"
  )
  expect_equal(pilot_key_character(keys), c("27", "__AGGREGATED__"))
  expect_equal(pilot_key_character(c("27", "14")), c("27", "14"))
})

test_that("the approval report is written as CSV and Markdown", {
  directory <- file.path(tempdir(), "pilot_approval_report")
  checks <- dplyr::bind_rows(
    pilot_check_row("C1", "a", TRUE),
    pilot_check_row("C2", "b", TRUE),
    pilot_check_row("C3", "c", NA, detail = "pipe | inside"),
    pilot_check_row("C4", "d", TRUE)
  )
  report <- write_pilot_approval_report(checks, directory)
  expect_true(file.exists(report$csv))
  expect_true(file.exists(report$markdown))
  expect_equal(report$summary$status, c("PASS", "PASS", "FAIL", "PASS"))
  markdown <- readLines(report$markdown, encoding = "UTF-8")
  expect_true(any(grepl("Resultado geral: FAIL", markdown, fixed = TRUE)))
  expect_true(any(grepl("pipe \\| inside", markdown, fixed = TRUE)))
})

test_that("ridge losing to the benchmark is reported but does not gate C3", {
  rows <- synthetic_pilot_error_rows()
  ridge <- rows$.model == "ridge_global_bottom_up"
  rows$absolute_error[ridge] <- rows$absolute_error[ridge] * 10
  rows$squared_error[ridge] <- rows$squared_error[ridge] * 100
  predictive <- check_pilot_predictive(rows, c(27, 14), c(1L, 3L, 6L))
  gate <- predictive |> dplyr::filter(.data$criterion == "C3")
  info <- predictive |> dplyr::filter(.data$criterion == "C3-info")
  expect_true(all(grepl("xgboost", gate$check)))
  expect_true(all(gate$status == "PASS"))
  expect_true(all(grepl("ridge", info$check)))
  expect_true(any(info$status == "FAIL"))
  expect_equal(summarise_pilot_approval(predictive)$status[3], "PASS")
})
