# Operational checks for the pilot approval criteria C1-C4.
#
# The criteria were approved by the author on 2026-10-02 and are documented in
# docs/PILOT_APPROVAL_CRITERIA.md. None of these functions is a target: they
# only read artefacts produced by the pipeline and never alter them. Missing
# inputs are always reported as FAIL, never as PASS.

pilot_approval_thresholds <- function() {
  list(
    # C2 and C4: |aggregate - sum(children)| <= tolerance * max(1, |aggregate|).
    coherence_relative_tolerance = 1e-6,
    # C3: scale-free metrics compared with the seasonal naive benchmark.
    scale_free_metrics = c("MASE", "RMSSE"),
    # C3: global models are identified by the bottom-up suffix used in
    # aggregate_bottom_up_predictions().
    global_model_pattern = "_global_bottom_up$",
    # C3: a horizon only counts when at least this share of paired
    # municipality-origins has a valid seasonal scale for both models.
    minimum_scaled_share = 0.90,
    # C4: unreconciled base forecast and primary reconciled forecast.
    base_model = "ets",
    reconciled_model = "ets_wls",
    reconciliation_levels = c("state", "national"),
    # C4: reconciled/base ratio of MASE and RMSSE must not exceed 1 + margin.
    reconciliation_margin = 0.05,
    # C4: forecasts that must be coherent by construction.
    coherent_model_pattern = "(_bottom_up|_wls|_mint_shrink)$"
  )
}

pilot_check_row <- function(
    criterion,
    check,
    passed,
    value = NA_character_,
    threshold = NA_character_,
    source = NA_character_,
    detail = NA_character_) {
  passed <- isTRUE(passed)
  tibble::tibble(
    criterion = criterion,
    check = check,
    status = if (passed) "PASS" else "FAIL",
    value = as.character(value),
    threshold = as.character(threshold),
    source = as.character(source),
    detail = as.character(detail)
  )
}

pilot_key_character <- function(x) {
  if (inherits(x, "agg_vec")) {
    fields <- vctrs::fields(x)
    if (all(c("x", "agg") %in% fields)) {
      values <- as.character(vctrs::field(x, "x"))
      aggregated <- vctrs::field(x, "agg")
    } else {
      values <- as.character(format(x))
      aggregated <- fabletools::is_aggregated(x)
    }
    values[!is.na(aggregated) & aggregated] <- "__AGGREGATED__"
    return(values)
  }
  as.character(x)
}

pilot_canonical_rows <- function(error_rows) {
  error_rows |>
    tibble::as_tibble() |>
    dplyr::mutate(
      region_code = pilot_key_character(.data$region_code),
      state_code = pilot_key_character(.data$state_code),
      stable_municipality_id = pilot_key_character(.data$stable_municipality_id),
      .model = as.character(.data$.model),
      horizon = as.integer(.data$horizon)
    )
}

# ---------------------------------------------------------------------------
# C1. Execution
# ---------------------------------------------------------------------------

read_pilot_warning_explanations <- function(path) {
  if (is.null(path) || !file.exists(path)) {
    return(tibble::tibble(target = character(), explanation = character()))
  }
  explanations <- readr::read_csv(
    path,
    col_types = readr::cols(.default = readr::col_character()),
    show_col_types = FALSE
  )
  if (!all(c("target", "explanation") %in% names(explanations))) {
    stop(
      "The warning explanation file must contain the columns target and explanation.",
      call. = FALSE
    )
  }
  explanations |>
    dplyr::filter(
      !is.na(.data$target),
      !is.na(.data$explanation),
      nzchar(trimws(.data$explanation))
    )
}

check_pilot_execution <- function(
    meta,
    required_targets,
    scope_label,
    expected_label = "pilot_alagoas_roraima",
    warning_explanations = NULL) {
  source <- "targets::tar_meta(); targets::tar_read(scope_label)"
  if (is.null(meta) || nrow(meta) == 0L || length(required_targets) == 0L) {
    return(pilot_check_row(
      "C1", "targets metadata available", FALSE,
      source = source,
      detail = "targets metadata or the target list is missing; run run_pilot.R first."
    ))
  }
  if (is.null(warning_explanations)) {
    warning_explanations <- tibble::tibble(
      target = character(),
      explanation = character()
    )
  }
  meta <- tibble::as_tibble(meta)
  for (column in c("error", "warnings")) {
    if (!column %in% names(meta)) {
      meta[[column]] <- NA_character_
    }
  }
  relevant <- meta |>
    dplyr::filter(.data$name %in% required_targets)
  missing_targets <- setdiff(required_targets, relevant$name)
  errored <- relevant |>
    dplyr::filter(!is.na(.data$error), nzchar(.data$error))
  warned <- relevant |>
    dplyr::filter(!is.na(.data$warnings), nzchar(.data$warnings))
  unexplained <- setdiff(warned$name, warning_explanations$target)

  dplyr::bind_rows(
    pilot_check_row(
      "C1", "all pilot targets were built",
      length(missing_targets) == 0L,
      value = paste0(
        length(required_targets) - length(missing_targets), "/",
        length(required_targets)
      ),
      threshold = "all targets in tar_manifest()",
      source = source,
      detail = if (length(missing_targets) == 0L) {
        "All targets have metadata."
      } else {
        paste("Without metadata:", paste(missing_targets, collapse = ", "))
      }
    ),
    pilot_check_row(
      "C1", "no target ended with an error",
      length(missing_targets) == 0L && nrow(errored) == 0L,
      value = nrow(errored),
      threshold = "0",
      source = source,
      detail = if (nrow(errored) == 0L) {
        "No recorded errors."
      } else {
        paste0(errored$name, ": ", errored$error, collapse = " | ")
      }
    ),
    pilot_check_row(
      "C1", "every warning is registered and explained",
      length(missing_targets) == 0L && length(unexplained) == 0L,
      value = paste0(nrow(warned), " with warnings; ", length(unexplained), " unexplained"),
      threshold = "0 unexplained",
      source = "targets::tar_meta(); docs/pilot_warning_explanations.csv",
      detail = if (nrow(warned) == 0L) {
        "No recorded warnings."
      } else {
        paste0(warned$name, ": ", warned$warnings, collapse = " | ")
      }
    ),
    pilot_check_row(
      "C1", "scope is the Alagoas-Roraima pilot",
      identical(as.character(scope_label), expected_label),
      value = if (is.null(scope_label)) "missing" else as.character(scope_label),
      threshold = expected_label,
      source = "targets::tar_read(scope_label)"
    )
  )
}

# ---------------------------------------------------------------------------
# C2. Geographic and hierarchical integrity
# ---------------------------------------------------------------------------

hierarchy_coherence_table <- function(
    error_rows,
    value = c("actual", "prediction"),
    models = NULL,
    tolerance = 1e-6) {
  value <- match.arg(value)
  rows <- pilot_canonical_rows(error_rows)
  if (!is.null(models)) {
    rows <- rows |>
      dplyr::filter(.data$.model %in% models)
  }
  rows <- rows |>
    dplyr::mutate(.value = as.numeric(.data[[value]]))
  by_level <- function(level) {
    rows |>
      dplyr::filter(.data$hierarchy_level == level)
  }
  common <- c(".model", "origin", "horizon")

  compare_link <- function(children, parents, group, link) {
    child_sum <- children |>
      dplyr::group_by(dplyr::across(dplyr::all_of(c(common, group)))) |>
      dplyr::summarise(children_sum = sum(.data$.value), .groups = "drop")
    parent_value <- parents |>
      dplyr::select(dplyr::all_of(c(common, group, ".value"))) |>
      dplyr::rename(aggregate = ".value")
    dplyr::full_join(parent_value, child_sum, by = c(common, group)) |>
      dplyr::mutate(
        link = link,
        group = if (length(group) == 0L) {
          "national"
        } else {
          as.character(.data[[group]])
        },
        absolute_difference = abs(.data$aggregate - .data$children_sum),
        allowed_difference = tolerance * pmax(1, abs(.data$aggregate)),
        coherent = is.finite(.data$absolute_difference) &
          .data$absolute_difference <= .data$allowed_difference
      ) |>
      dplyr::select(dplyr::all_of(c(
        "link", common, "group", "aggregate", "children_sum",
        "absolute_difference", "allowed_difference", "coherent"
      )))
  }

  dplyr::bind_rows(
    compare_link(by_level("municipality"), by_level("state"), "state_code", "municipality->state"),
    compare_link(by_level("state"), by_level("region"), "region_code", "state->region"),
    compare_link(by_level("region"), by_level("national"), character(), "region->national")
  )
}

summarise_coherence_check <- function(coherence, criterion, check, source, tolerance) {
  if (is.null(coherence) || nrow(coherence) == 0L) {
    return(pilot_check_row(
      criterion, check, FALSE,
      source = source,
      detail = "No hierarchy comparisons were available."
    ))
  }
  links <- c("municipality->state", "state->region", "region->national")
  missing_links <- setdiff(links, unique(coherence$link))
  failures <- coherence |>
    dplyr::filter(!.data$coherent)
  pilot_check_row(
    criterion, check,
    length(missing_links) == 0L && nrow(failures) == 0L,
    value = paste0(nrow(failures), " incoherent of ", nrow(coherence)),
    threshold = paste0("|aggregate - sum| <= ", format(tolerance), " * max(1, |aggregate|)"),
    source = source,
    detail = if (length(missing_links) > 0L) {
      paste("Missing hierarchy links:", paste(missing_links, collapse = ", "))
    } else if (nrow(failures) == 0L) {
      "All aggregates equal the sum of their children."
    } else {
      examples <- utils::head(failures, 5L)
      paste0(
        examples$link, " ", examples$.model, " ", examples$group,
        " h=", examples$horizon, " diff=", signif(examples$absolute_difference, 4),
        collapse = " | "
      )
    }
  )
}

check_pilot_geography <- function(
    calendar_gaps,
    panel,
    expected_states,
    error_rows,
    map_files,
    tolerance = pilot_approval_thresholds()$coherence_relative_tolerance) {
  expected_states <- sprintf("%02d", as.integer(expected_states))
  checks <- list()

  checks[[length(checks) + 1L]] <- if (is.null(calendar_gaps)) {
    pilot_check_row(
      "C2", "no municipality-month gaps", FALSE,
      source = "output/analysis_panel_calendar_gaps.csv",
      detail = "Gap diagnostic file is missing."
    )
  } else {
    pilot_check_row(
      "C2", "no municipality-month gaps",
      nrow(calendar_gaps) == 0L,
      value = nrow(calendar_gaps),
      threshold = "0",
      source = "output/analysis_panel_calendar_gaps.csv"
    )
  }

  checks[[length(checks) + 1L]] <- if (is.null(panel) || nrow(panel) == 0L) {
    pilot_check_row(
      "C2", "stable and balanced pilot geography", FALSE,
      source = "targets::tar_read(scoped_panel)",
      detail = "Pilot panel is missing or empty."
    )
  } else {
    panel <- tibble::as_tibble(panel) |>
      dplyr::mutate(
        stable_municipality_id = as.character(.data$stable_municipality_id),
        state_code = as.character(.data$state_code),
        region_code = as.character(.data$region_code)
      )
    months <- dplyr::n_distinct(panel$month)
    duplicates <- panel |>
      dplyr::count(.data$month, .data$stable_municipality_id) |>
      dplyr::filter(.data$n != 1L)
    per_unit <- panel |>
      dplyr::group_by(.data$stable_municipality_id) |>
      dplyr::summarise(
        months = dplyr::n_distinct(.data$month),
        states = dplyr::n_distinct(.data$state_code),
        regions = dplyr::n_distinct(.data$region_code),
        .groups = "drop"
      )
    unbalanced <- per_unit |>
      dplyr::filter(.data$months != !!months)
    unstable <- per_unit |>
      dplyr::filter(.data$states != 1L | .data$regions != 1L)
    observed_states <- sort(unique(panel$state_code))
    states_ok <- identical(observed_states, sort(expected_states))
    problems <- c(
      if (!states_ok) {
        paste0(
          "states ", paste(observed_states, collapse = "/"),
          " instead of ", paste(sort(expected_states), collapse = "/")
        )
      },
      if (nrow(duplicates) > 0L) paste(nrow(duplicates), "duplicated keys"),
      if (nrow(unbalanced) > 0L) paste(nrow(unbalanced), "units without all months"),
      if (nrow(unstable) > 0L) paste(nrow(unstable), "units changing state or region")
    )
    pilot_check_row(
      "C2", "stable and balanced pilot geography",
      length(problems) == 0L,
      value = paste0(nrow(per_unit), " units x ", months, " months"),
      threshold = "states = pilot; unique keys; balanced; one state/region per unit",
      source = "targets::tar_read(scoped_panel)",
      detail = if (length(problems) == 0L) "Geography is stable." else paste(problems, collapse = "; ")
    )
  }

  coherence <- if (is.null(error_rows)) {
    NULL
  } else {
    hierarchy_coherence_table(error_rows, value = "actual", tolerance = tolerance)
  }
  checks[[length(checks) + 1L]] <- summarise_coherence_check(
    coherence,
    "C2",
    "observed values add up municipality->state->region->Brazil",
    "output/forecast_error_rows_<label>.rds (actual)",
    tolerance
  )

  map_files <- as.character(map_files)
  unavailable <- grepl("forecast_gain_map_unavailable", basename(map_files))
  figures <- map_files[
    grepl("^figure_forecast_gain_map_", basename(map_files)) &
      grepl("[.](png|pdf)$", map_files, ignore.case = TRUE)
  ]
  map_ok <- length(map_files) > 0L &&
    !any(unavailable) &&
    length(figures) > 0L &&
    all(file.exists(map_files))
  checks[[length(checks) + 1L]] <- pilot_check_row(
    "C2", "forecast-gain map generated without failure",
    map_ok,
    value = paste(basename(map_files), collapse = ", "),
    threshold = "map PDF/PNG present; no *_unavailable_* marker",
    source = "targets::tar_read(forecast_map_files)",
    detail = if (length(map_files) == 0L) {
      "No map files were recorded."
    } else if (any(unavailable)) {
      "The map target produced the unavailability marker."
    } else if (!all(file.exists(map_files))) {
      "Some recorded map files do not exist."
    } else if (length(figures) == 0L) {
      "No map figure was recorded."
    } else {
      "Map figures exist."
    }
  )

  dplyr::bind_rows(checks)
}

# ---------------------------------------------------------------------------
# C3. Predictive performance against the seasonal naive benchmark
# ---------------------------------------------------------------------------

paired_scale_free_accuracy_by_state <- function(error_rows, models, benchmark_model) {
  rows <- pilot_canonical_rows(error_rows) |>
    dplyr::filter(.data$hierarchy_level == "municipality") |>
    dplyr::mutate(
      scaled_absolute_error = dplyr::if_else(
        is.finite(.data$mae_scale) & .data$mae_scale > 0,
        .data$absolute_error / .data$mae_scale,
        NA_real_
      ),
      scaled_squared_error = dplyr::if_else(
        is.finite(.data$rmsse_scale) & .data$rmsse_scale > 0,
        .data$squared_error / (.data$rmsse_scale^2),
        NA_real_
      )
    )
  keys <- c("state_code", "stable_municipality_id", "origin", "horizon")
  benchmark <- rows |>
    dplyr::filter(.data$.model == benchmark_model) |>
    dplyr::select(dplyr::all_of(c(keys, "scaled_absolute_error", "scaled_squared_error"))) |>
    dplyr::rename(
      benchmark_sae = "scaled_absolute_error",
      benchmark_sse = "scaled_squared_error"
    )

  rows |>
    dplyr::filter(.data$.model %in% models) |>
    dplyr::select(dplyr::all_of(c(
      ".model", keys, "scaled_absolute_error", "scaled_squared_error"
    ))) |>
    dplyr::inner_join(benchmark, by = keys) |>
    dplyr::mutate(
      valid = is.finite(.data$scaled_absolute_error) &
        is.finite(.data$benchmark_sae) &
        is.finite(.data$scaled_squared_error) &
        is.finite(.data$benchmark_sse)
    ) |>
    dplyr::group_by(.data$.model, .data$state_code, .data$horizon) |>
    dplyr::summarise(
      paired_rows = dplyr::n(),
      scaled_rows = sum(.data$valid),
      MASE = finite_mean(.data$scaled_absolute_error[.data$valid]),
      MASE_benchmark = finite_mean(.data$benchmark_sae[.data$valid]),
      RMSSE = finite_root_mean(.data$scaled_squared_error[.data$valid]),
      RMSSE_benchmark = finite_root_mean(.data$benchmark_sse[.data$valid]),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      scaled_share = dplyr::if_else(
        .data$paired_rows > 0L,
        .data$scaled_rows / .data$paired_rows,
        NA_real_
      )
    )
}

check_pilot_predictive <- function(
    error_rows,
    expected_states,
    horizons,
    benchmark_model = "seasonal_naive",
    thresholds = pilot_approval_thresholds()) {
  source <- "output/forecast_error_rows_<label>.rds (municipality level, by state)"
  if (is.null(error_rows) || nrow(error_rows) == 0L) {
    return(pilot_check_row(
      "C3", "rolling-origin error rows available", FALSE,
      source = source,
      detail = "Forecast error rows are missing."
    ))
  }
  expected_states <- sprintf("%02d", as.integer(expected_states))
  horizons <- sort(unique(as.integer(horizons)))
  available_models <- unique(as.character(error_rows$.model))
  global_models <- sort(grep(thresholds$global_model_pattern, available_models, value = TRUE))
  if (length(global_models) == 0L || !benchmark_model %in% available_models) {
    return(pilot_check_row(
      "C3", "global models and benchmark available", FALSE,
      source = source,
      detail = paste0(
        "Global models found: ",
        if (length(global_models) == 0L) "none" else paste(global_models, collapse = ", "),
        "; benchmark ", benchmark_model,
        if (benchmark_model %in% available_models) " found." else " missing."
      )
    ))
  }

  accuracy <- paired_scale_free_accuracy_by_state(error_rows, global_models, benchmark_model)
  metrics <- thresholds$scale_free_metrics
  grid <- tidyr::expand_grid(
    .model = global_models,
    state_code = expected_states,
    horizon = horizons
  ) |>
    dplyr::left_join(accuracy, by = c(".model", "state_code", "horizon"))
  beats <- function(metric) {
    model_value <- grid[[metric]]
    benchmark_value <- grid[[paste0(metric, "_benchmark")]]
    is.finite(model_value) & is.finite(benchmark_value) & model_value < benchmark_value
  }
  any_metric <- Reduce(`|`, lapply(metrics, beats))
  grid <- grid |>
    dplyr::mutate(
      coverage_ok = is.finite(.data$scaled_share) &
        .data$scaled_share >= thresholds$minimum_scaled_share,
      win = .data$coverage_ok & any_metric
    )

  required_wins <- floor(length(horizons) / 2) + 1L
  checks <- grid |>
    dplyr::group_by(.data$.model, .data$state_code) |>
    dplyr::group_map(function(.x, .y) {
      wins <- sum(.x$win)
      detail <- paste0(
        "h=", .x$horizon,
        ": MASE ", signif(.x$MASE, 4), " vs ", signif(.x$MASE_benchmark, 4),
        ", RMSSE ", signif(.x$RMSSE, 4), " vs ", signif(.x$RMSSE_benchmark, 4),
        ", scaled share ", signif(.x$scaled_share, 3),
        collapse = "; "
      )
      pilot_check_row(
        "C3",
        paste0(.y$.model, " beats ", benchmark_model, " in state ", .y$state_code),
        wins >= required_wins,
        value = paste0(wins, "/", length(horizons), " horizons"),
        threshold = paste0(
          ">= ", required_wins, "/", length(horizons),
          " horizons with lower ", paste(metrics, collapse = " or "),
          "; scaled share >= ", thresholds$minimum_scaled_share
        ),
        source = source,
        detail = detail
      )
    })
  dplyr::bind_rows(checks)
}

# ---------------------------------------------------------------------------
# C4. Reconciliation
# ---------------------------------------------------------------------------

paired_aggregate_accuracy <- function(error_rows, base_model, reconciled_model, levels) {
  rows <- pilot_canonical_rows(error_rows) |>
    dplyr::filter(.data$hierarchy_level %in% levels) |>
    dplyr::mutate(
      scaled_absolute_error = dplyr::if_else(
        is.finite(.data$mae_scale) & .data$mae_scale > 0,
        .data$absolute_error / .data$mae_scale,
        NA_real_
      ),
      scaled_squared_error = dplyr::if_else(
        is.finite(.data$rmsse_scale) & .data$rmsse_scale > 0,
        .data$squared_error / (.data$rmsse_scale^2),
        NA_real_
      )
    )
  keys <- c(
    "hierarchy_level", "region_code", "state_code",
    "stable_municipality_id", "origin", "horizon"
  )
  pick <- function(model, prefix) {
    rows |>
      dplyr::filter(.data$.model == model) |>
      dplyr::select(dplyr::all_of(c(keys, "scaled_absolute_error", "scaled_squared_error"))) |>
      dplyr::rename_with(
        ~ paste0(prefix, .x),
        dplyr::all_of(c("scaled_absolute_error", "scaled_squared_error"))
      )
  }
  dplyr::inner_join(pick(base_model, "base_"), pick(reconciled_model, "reconciled_"), by = keys) |>
    dplyr::mutate(
      valid = is.finite(.data$base_scaled_absolute_error) &
        is.finite(.data$reconciled_scaled_absolute_error) &
        is.finite(.data$base_scaled_squared_error) &
        is.finite(.data$reconciled_scaled_squared_error)
    ) |>
    dplyr::group_by(.data$hierarchy_level, .data$horizon) |>
    dplyr::summarise(
      paired_rows = dplyr::n(),
      scaled_rows = sum(.data$valid),
      MASE_base = finite_mean(.data$base_scaled_absolute_error[.data$valid]),
      MASE_reconciled = finite_mean(.data$reconciled_scaled_absolute_error[.data$valid]),
      RMSSE_base = finite_root_mean(.data$base_scaled_squared_error[.data$valid]),
      RMSSE_reconciled = finite_root_mean(.data$reconciled_scaled_squared_error[.data$valid]),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      MASE_ratio = .data$MASE_reconciled / .data$MASE_base,
      RMSSE_ratio = .data$RMSSE_reconciled / .data$RMSSE_base
    )
}

check_pilot_reconciliation <- function(
    error_rows,
    horizons,
    thresholds = pilot_approval_thresholds()) {
  source <- "output/forecast_error_rows_<label>.rds"
  if (is.null(error_rows) || nrow(error_rows) == 0L) {
    return(pilot_check_row(
      "C4", "rolling-origin error rows available", FALSE,
      source = source,
      detail = "Forecast error rows are missing."
    ))
  }
  base_model <- thresholds$base_model
  reconciled_model <- thresholds$reconciled_model
  available_models <- unique(as.character(error_rows$.model))
  missing_models <- setdiff(c(base_model, reconciled_model), available_models)
  if (length(missing_models) > 0L) {
    return(pilot_check_row(
      "C4", "base and reconciled forecasts available", FALSE,
      source = source,
      detail = paste("Missing models:", paste(missing_models, collapse = ", "))
    ))
  }

  horizons <- sort(unique(as.integer(horizons)))
  levels <- thresholds$reconciliation_levels
  limit <- 1 + thresholds$reconciliation_margin
  accuracy <- paired_aggregate_accuracy(error_rows, base_model, reconciled_model, levels)
  grid <- tidyr::expand_grid(hierarchy_level = levels, horizon = horizons) |>
    dplyr::left_join(accuracy, by = c("hierarchy_level", "horizon")) |>
    dplyr::mutate(
      ok = is.finite(.data$MASE_ratio) & .data$MASE_ratio <= limit &
        is.finite(.data$RMSSE_ratio) & .data$RMSSE_ratio <= limit
    )
  accuracy_checks <- lapply(levels, function(level) {
    part <- grid[grid$hierarchy_level == level, , drop = FALSE]
    pilot_check_row(
      "C4",
      paste0(reconciled_model, " does not worsen ", base_model, " at level ", level),
      all(part$ok),
      value = paste0(sum(part$ok), "/", nrow(part), " horizons within margin"),
      threshold = paste0("MASE and RMSSE ratio <= ", format(limit), " in every horizon"),
      source = source,
      detail = paste0(
        "h=", part$horizon,
        ": MASE ratio ", signif(part$MASE_ratio, 4),
        ", RMSSE ratio ", signif(part$RMSSE_ratio, 4),
        ", paired ", part$paired_rows,
        collapse = "; "
      )
    )
  })

  coherent_models <- sort(grep(thresholds$coherent_model_pattern, available_models, value = TRUE))
  coherence <- hierarchy_coherence_table(
    error_rows,
    value = "prediction",
    models = coherent_models,
    tolerance = thresholds$coherence_relative_tolerance
  )
  covered <- unique(coherence$.model)
  coherence_check <- summarise_coherence_check(
    coherence,
    "C4",
    paste0("reconciled forecasts are coherent (", paste(coherent_models, collapse = ", "), ")"),
    paste0(source, " (prediction)"),
    thresholds$coherence_relative_tolerance
  )
  if (!reconciled_model %in% covered || length(setdiff(coherent_models, covered)) > 0L) {
    coherence_check$status <- "FAIL"
    coherence_check$detail <- paste(
      "Some reconciled models have no hierarchy rows:",
      paste(setdiff(union(reconciled_model, coherent_models), covered), collapse = ", ")
    )
  }

  dplyr::bind_rows(accuracy_checks, coherence_check)
}

# ---------------------------------------------------------------------------
# Summary and report
# ---------------------------------------------------------------------------

summarise_pilot_approval <- function(checks) {
  criteria <- c("C1", "C2", "C3", "C4")
  checks <- dplyr::bind_rows(
    tibble::tibble(criterion = character(), status = character()),
    checks
  )
  tibble::tibble(criterion = criteria) |>
    dplyr::left_join(
      checks |>
        dplyr::group_by(.data$criterion) |>
        dplyr::summarise(
          checks = dplyr::n(),
          failed = sum(.data$status != "PASS"),
          .groups = "drop"
        ),
      by = "criterion"
    ) |>
    dplyr::mutate(
      checks = dplyr::coalesce(.data$checks, 0L),
      failed = dplyr::coalesce(.data$failed, 0L),
      status = dplyr::if_else(
        .data$checks > 0L & .data$failed == 0L,
        "PASS",
        "FAIL"
      )
    )
}

pilot_markdown_escape <- function(x) {
  x <- ifelse(is.na(x), "", as.character(x))
  gsub("|", "\\|", gsub("\n", " ", x, fixed = TRUE), fixed = TRUE)
}

write_pilot_approval_report <- function(checks, output_dir = "output", generated = Sys.time()) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  summary <- summarise_pilot_approval(checks)
  csv_path <- file.path(output_dir, "pilot_approval.csv")
  md_path <- file.path(output_dir, "pilot_approval.md")
  readr::write_csv(checks, csv_path, na = "")

  approved <- all(summary$status == "PASS")
  lines <- c(
    "# Aprovação do piloto (C1-C4)",
    "",
    paste0("Gerado em (UTC): ", format(generated, tz = "UTC", usetz = TRUE)),
    "",
    "Critérios: `docs/PILOT_APPROVAL_CRITERIA.md`. Dados ausentes contam como FAIL.",
    "",
    paste0(
      "**Resultado geral: ",
      if (approved) "PASS" else "FAIL",
      "** — ",
      if (approved) {
        "o piloto atende C1-C4; `run_national_background.R` pode ser executado."
      } else {
        "não execute `run_national_background.R` antes de resolver os itens em FAIL."
      }
    ),
    "",
    "| Critério | Situação | Verificações | Falhas |",
    "|---|---|---|---|",
    paste0(
      "| ", summary$criterion, " | ", summary$status, " | ",
      summary$checks, " | ", summary$failed, " |"
    ),
    "",
    "## Verificações",
    "",
    "| Critério | Verificação | Situação | Valor | Limiar | Fonte | Detalhe |",
    "|---|---|---|---|---|---|---|",
    if (nrow(checks) > 0L) {
      paste0(
        "| ", pilot_markdown_escape(checks$criterion),
        " | ", pilot_markdown_escape(checks$check),
        " | ", pilot_markdown_escape(checks$status),
        " | ", pilot_markdown_escape(checks$value),
        " | ", pilot_markdown_escape(checks$threshold),
        " | ", pilot_markdown_escape(checks$source),
        " | ", pilot_markdown_escape(checks$detail), " |"
      )
    }
  )
  writeLines(enc2utf8(lines), md_path, useBytes = TRUE)
  invisible(list(summary = summary, csv = csv_path, markdown = md_path))
}
