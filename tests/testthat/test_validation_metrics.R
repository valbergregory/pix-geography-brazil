test_that("panel gaps are detected and never silently converted to zero", {
  complete <- tidyr::expand_grid(
    stable_municipality_id = c("A", "B"),
    month = seq(as.Date("2024-01-01"), by = "month", length.out = 3L)
  ) |>
    dplyr::mutate(
      payer_count = 1,
      payer_value_nominal = 1,
      active_payers = 1
    )
  incomplete <- complete |>
    dplyr::filter(!(
      .data$stable_municipality_id == "B" &
        .data$month == as.Date("2024-02-01")
    ))

  gaps <- analysis_panel_calendar_gaps(incomplete)
  expect_equal(nrow(gaps), 1L)
  expect_equal(gaps$stable_municipality_id, "B")
})

test_that("zero seasonal scales are excluded from MASE and reported", {
  rows <- tibble::tibble(
    .model = "test",
    horizon = 1L,
    hierarchy_level = "municipality",
    absolute_error = c(2, 4),
    squared_error = c(4, 16),
    actual = c(10, 10),
    mae_scale = c(0, 2),
    rmsse_scale = c(0, 4)
  )
  accuracy <- summarise_forecast_accuracy(rows)

  expect_equal(accuracy$series_origins, 2L)
  expect_equal(accuracy$scaled_origins, 1L)
  expect_equal(accuracy$MASE, 2)
  expect_equal(accuracy$RMSSE, 1)
  expect_true(is.finite(accuracy$WAPE))
})

test_that("missing calendar months produce an explicit diagnostic", {
  raw <- synthetic_pix_raw() |>
    dplyr::filter(.data$AnoMes == 202301L) |>
    dplyr::bind_rows(
      synthetic_pix_raw() |>
        dplyr::filter(.data$AnoMes == 202302L) |>
        dplyr::mutate(AnoMes = 202303L)
    )

  expect_error(
    validate_pix_months(raw, minimum_months = 2L),
    "Missing reference months: 2023-02"
  )
})

test_that("reliability covariates use history available at each origin", {
  panel <- tidyr::expand_grid(
    stable_municipality_id = c("A", "B"),
    month = seq(as.Date("2022-01-01"), by = "month", length.out = 25L)
  ) |>
    dplyr::arrange(.data$stable_municipality_id, .data$month) |>
    dplyr::mutate(payer_count = 10 + dplyr::row_number())
  errors <- tibble::tibble(origin = tsibble::yearmonth("2024 Jan"))

  covariates <- build_forecast_reliability_covariates(panel, errors)
  expect_equal(nrow(covariates), 2L)
  expect_true(all(c(
    "log_historical_mean",
    "historical_cv",
    "recent_growth"
  ) %in% names(covariates)))
  expect_true(all(is.finite(covariates$recent_growth)))
})
