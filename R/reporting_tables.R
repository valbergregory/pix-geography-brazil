article_table <- function(
    data,
    filename,
    caption,
    config,
    notes = NULL,
    digits = 3L,
    width = 1) {
  ensure_project_directories(config)
  path <- file.path(config$reporting$tables_dir, filename)

  table <- tinytable::tt(
    data,
    caption = caption,
    notes = notes,
    digits = as.integer(digits),
    width = width,
    escape = TRUE
  )
  tinytable::save_tt(table, output = path, overwrite = TRUE)
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

data_coverage_table <- function(panel) {
  tibble::tibble(
    Characteristic = c(
      "First reference month",
      "Last reference month",
      "Monthly observations",
      "Stable municipality-equivalent units",
      "States",
      "Macroregions",
      "Primary target",
      "Unidentified geography in hierarchy"
    ),
    Value = c(
      format(min(panel$month), "%Y-%m"),
      format(max(panel$month), "%Y-%m"),
      format(nrow(panel), big.mark = ",", scientific = FALSE),
      format(
        dplyr::n_distinct(panel$stable_municipality_id),
        big.mark = ",",
        scientific = FALSE
      ),
      as.character(dplyr::n_distinct(panel$state_code)),
      as.character(dplyr::n_distinct(panel$region_code)),
      "Outgoing transactions: payer PF + payer PJ",
      "No"
    )
  )
}

experimental_design_table <- function(config) {
  tibble::tibble(
    Component = c(
      "Forecast target",
      "Frequency",
      "Hierarchy",
      "Initial training window",
      "Origin update",
      "Forecast horizons",
      "Local benchmarks",
      "Global challengers",
      "Reconciliation",
      "Primary accuracy metrics",
      "Statistical comparison",
      "Structural-break diagnostics"
    ),
    Specification = c(
      "QT_PagadorPF + QT_PagadorPJ",
      "Monthly",
      "Municipality-equivalent / state / macroregion / Brazil",
      paste(config$analysis$initial_window_months, "months"),
      paste("Every", config$analysis$origin_step_months, "month"),
      paste(as.integer(unlist(config$analysis$horizons)), collapse = ", "),
      "Naive, seasonal naive, drift, ETS, ARIMA",
      "Global Ridge (glmnet) and global XGBoost, estimated entirely in R",
      "Bottom-up, WLS variance scaling, optional MinT-shrink",
      "MASE and RMSSE; MAE, RMSE, and WAPE as complements",
      "Origin-level paired loss with Newey-West uncertainty",
      "Bai-Perron for aggregates and PELT for scalable exploration"
    )
  )
}

municipal_accuracy_table <- function(accuracy) {
  accuracy |>
    dplyr::filter(.data$hierarchy_level == "municipality") |>
    dplyr::select(
      Model = .model,
      Horizon = horizon,
      MASE,
      RMSSE,
      WAPE
    ) |>
    tidyr::pivot_wider(
      names_from = Horizon,
      values_from = c(MASE, RMSSE, WAPE),
      names_glue = "{.value} h={Horizon}"
    ) |>
    dplyr::arrange(.data$Model)
}

hierarchy_accuracy_table <- function(accuracy) {
  accuracy |>
    dplyr::transmute(
      Model = .data$.model,
      Horizon = .data$horizon,
      Level = .data$hierarchy_level,
      `Total N` = .data$series_origins,
      `Scaled N` = .data$scaled_origins,
      MASE = .data$MASE,
      RMSSE = .data$RMSSE,
      WAPE = .data$WAPE,
      MAE = .data$MAE,
      RMSE = .data$RMSE
    ) |>
    dplyr::arrange(.data$Level, .data$Horizon, .data$MASE)
}

scaled_metric_coverage_table <- function(accuracy) {
  accuracy |>
    dplyr::transmute(
      Model = .data$.model,
      Horizon = .data$horizon,
      Level = .data$hierarchy_level,
      `Total series-origins` = .data$series_origins,
      `Valid seasonal scales` = .data$scaled_origins,
      `Excluded zero/invalid scales` =
        .data$series_origins - .data$scaled_origins
    ) |>
    dplyr::arrange(.data$Level, .data$Horizon, .data$Model)
}

relative_gain_table <- function(error_rows, benchmark_model) {
  average_loss <- model_loss_by_origin(error_rows, loss = "absolute") |>
    dplyr::group_by(
      .data$horizon,
      .data$hierarchy_level,
      .data$.model
    ) |>
    dplyr::summarise(mean_loss = mean(.data$loss), .groups = "drop")

  benchmark <- average_loss |>
    dplyr::filter(.data$.model == benchmark_model) |>
    dplyr::select(
      horizon,
      hierarchy_level,
      benchmark_loss = mean_loss
    )

  average_loss |>
    dplyr::left_join(
      benchmark,
      by = c("horizon", "hierarchy_level")
    ) |>
    dplyr::mutate(
      relative_gain_percent = dplyr::if_else(
        is.finite(.data$benchmark_loss) & .data$benchmark_loss > 0,
        100 * (.data$benchmark_loss - .data$mean_loss) /
          .data$benchmark_loss,
        NA_real_
      )
    ) |>
    dplyr::transmute(
      Model = .data$.model,
      Horizon = .data$horizon,
      Level = .data$hierarchy_level,
      `Mean absolute loss` = .data$mean_loss,
      `Gain versus benchmark (%)` = .data$relative_gain_percent
    ) |>
    dplyr::arrange(.data$Level, .data$Horizon, dplyr::desc(.data$`Gain versus benchmark (%)`))
}

negative_prediction_table <- function(error_rows) {
  error_rows |>
    dplyr::group_by(
      .data$.model,
      .data$horizon,
      .data$hierarchy_level
    ) |>
    dplyr::summarise(
      Predictions = dplyr::n(),
      Negative = sum(.data$prediction < 0, na.rm = TRUE),
      `Negative share (%)` = 100 * mean(
        .data$prediction < 0,
        na.rm = TRUE
      ),
      .groups = "drop"
    ) |>
    dplyr::rename(
      Model = .model,
      Horizon = horizon,
      Level = hierarchy_level
    )
}

runtime_table <- function(error_rows) {
  error_rows |>
    dplyr::filter(
      !is.na(.data$evaluation_batch),
      !is.na(.data$origin_elapsed_seconds)
    ) |>
    dplyr::distinct(
      .data$origin,
      .data$evaluation_batch,
      .data$origin_elapsed_seconds
    ) |>
    dplyr::group_by(.data$evaluation_batch) |>
    dplyr::summarise(
      Origins = dplyr::n(),
      `Total time (minutes)` = sum(.data$origin_elapsed_seconds) / 60,
      `Mean time per origin (seconds)` = mean(.data$origin_elapsed_seconds),
      `Maximum time per origin (seconds)` = max(.data$origin_elapsed_seconds),
      .groups = "drop"
    ) |>
    dplyr::rename(`Evaluation batch` = evaluation_batch)
}

export_modelsummary_latex <- function(
    models,
    filename,
    config,
    coefficient_map = NULL,
    goodness_of_fit_map = NULL,
    vcov = NULL,
    notes = NULL) {
  ensure_project_directories(config)
  path <- file.path(config$reporting$tables_dir, filename)
  table <- modelsummary::modelsummary(
    models,
    output = "tinytable",
    coef_map = coefficient_map,
    gof_map = goodness_of_fit_map,
    vcov = vcov,
    estimate = "{estimate}{stars}",
    statistic = "({std.error})",
    stars = c("*" = 0.1, "**" = 0.05, "***" = 0.01),
    fmt = modelsummary::fmt_decimal(digits = 3, pdigits = 3),
    notes = notes,
    escape = TRUE
  )
  tinytable::save_tt(table, output = path, overwrite = TRUE)
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

export_fixest_latex <- function(models, filename, config, ...) {
  ensure_project_directories(config)
  path <- file.path(config$reporting$tables_dir, filename)
  arguments <- c(
    unname(models),
    list(
      tex = TRUE,
      file = path,
      replace = TRUE,
      style.tex = fixest::style.tex(main = "aer")
    ),
    list(...)
  )
  do.call(fixest::etable, arguments)
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

export_descriptive_tables <- function(panel, config) {
  c(
    article_table(
      data_coverage_table(panel),
      "table_data_coverage.tex",
      "Coverage and construction of the municipal Pix panel",
      config,
      notes = "The unidentified geographic category is retained for auditing but excluded from the forecasting hierarchy.",
      digits = 0L
    ),
    article_table(
      experimental_design_table(config),
      "quadro_experimental_design.tex",
      "Experimental design",
      config,
      notes = "Break dates obtained from the full sample are descriptive and are not used as forecasting features.",
      digits = 0L,
      width = c(0.28, 0.72)
    )
  )
}

export_forecast_tables <- function(error_rows, config) {
  accuracy <- summarise_forecast_accuracy(error_rows)
  benchmark <- config$reporting$benchmark_model
  comparison <- config$reporting$comparison_model

  paths <- c(
    article_table(
      municipal_accuracy_table(accuracy),
      "table_forecast_accuracy_municipal.tex",
      "Municipality-level forecast accuracy by model and horizon",
      config,
      notes = "Lower values indicate better performance. MASE and RMSSE use seasonal scaling based only on each training window."
    ),
    article_table(
      hierarchy_accuracy_table(accuracy),
      "table_forecast_accuracy_hierarchy.tex",
      "Forecast accuracy across geographic aggregation levels",
      config,
      notes = "Results are reported separately for municipality, state, macroregion, and national levels."
    ),
    article_table(
      relative_gain_table(error_rows, benchmark),
      "table_relative_gain.tex",
      paste("Forecast gains relative to", benchmark),
      config,
      notes = "Positive values indicate lower mean absolute loss than the benchmark."
    ),
    article_table(
      negative_prediction_table(error_rows),
      "table_negative_predictions.tex",
      "Incidence of negative point forecasts",
      config,
      notes = paste(
        "Local statistical negatives are reported without silent truncation.",
        "Global count forecasts use a nonnegative inverse transformation."
      )
    ),
    article_table(
      scaled_metric_coverage_table(accuracy),
      "table_scaled_metric_coverage.tex",
      "Coverage of seasonally scaled accuracy metrics",
      config,
      notes = paste(
        "MASE and RMSSE exclude series-origins with a zero, missing,",
        "or non-finite training scale; unscaled metrics retain valid forecasts."
      ),
      digits = 0L
    )
  )

  available_models <- unique(error_rows$.model)
  if (all(c(comparison, benchmark) %in% available_models)) {
    statistical_comparison <- compare_models_newey_west(
      error_rows,
      model_a = comparison,
      model_b = benchmark,
      loss = "absolute"
    ) |>
      dplyr::rename(
        Horizon = horizon,
        Level = hierarchy_level,
        `Model A` = model_a,
        `Model B` = model_b,
        Origins = origins,
        `Mean loss difference` = mean_loss_difference,
        `HAC standard error` = hac_standard_error,
        `p-value` = p_value,
        `95% CI lower` = confidence_low,
        `95% CI upper` = confidence_high
      )

    paths <- c(
      paths,
      article_table(
        statistical_comparison,
        "table_newey_west_comparison.tex",
        paste("Paired loss comparison:", comparison, "versus", benchmark),
        config,
        notes = "A negative difference favors Model A. Uncertainty uses a Newey-West covariance estimator over forecast origins."
      )
    )
  }

  if (all(c("evaluation_batch", "origin_elapsed_seconds") %in% names(error_rows))) {
    paths <- c(
      paths,
      article_table(
        runtime_table(error_rows),
        "table_runtime.tex",
        "Computational time of rolling-origin evaluation",
        config,
        notes = "Time is measured for each jointly estimated model batch at each origin and should be interpreted with the reported hardware configuration."
      )
    )
  }

  paths
}
