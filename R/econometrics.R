prepare_forecast_reliability_panel <- function(error_rows, municipality_covariates = NULL) {
  panel <- error_rows |>
    dplyr::filter(.data$hierarchy_level == "municipality") |>
    dplyr::mutate(
      scaled_absolute_error = dplyr::if_else(
        is.finite(.data$mae_scale) & .data$mae_scale > 0,
        .data$absolute_error / .data$mae_scale,
        NA_real_
      ),
      log_scaled_absolute_error = log1p(.data$scaled_absolute_error)
    ) |>
    dplyr::filter(is.finite(.data$log_scaled_absolute_error)) |>
    dplyr::group_by(
      .data$stable_municipality_id,
      .data$region_code,
      .data$state_code,
      .data$origin,
      .data$horizon,
      .data$.model
    ) |>
    dplyr::summarise(
      scaled_absolute_error = mean(.data$scaled_absolute_error),
      log_scaled_absolute_error = mean(.data$log_scaled_absolute_error),
      absolute_error = mean(.data$absolute_error),
      .groups = "drop"
    )

  if (is.null(municipality_covariates)) {
    return(panel)
  }

  join_keys <- intersect(
    c("stable_municipality_id", "origin"),
    names(municipality_covariates)
  )
  if (!"stable_municipality_id" %in% join_keys) {
    stop("Covariates require stable_municipality_id.", call. = FALSE)
  }
  panel |>
    dplyr::left_join(municipality_covariates, by = join_keys)
}

build_forecast_reliability_covariates <- function(panel, error_rows) {
  origins <- sort(unique(as.Date(error_rows$origin)))
  purrr::map_dfr(origins, function(origin_date) {
    history <- panel |>
      dplyr::filter(.data$month <= origin_date) |>
      dplyr::arrange(.data$stable_municipality_id, .data$month) |>
      dplyr::group_by(.data$stable_municipality_id) |>
      dplyr::summarise(
        historical_mean = mean(.data$payer_count),
        historical_sd = stats::sd(.data$payer_count),
        recent_mean = mean(utils::tail(.data$payer_count, 3L)),
        previous_mean = mean(utils::tail(.data$payer_count, 6L)[1:3]),
        .groups = "drop"
      ) |>
      dplyr::mutate(
        origin = tsibble::yearmonth(origin_date),
        log_historical_mean = log1p(.data$historical_mean),
        historical_cv = dplyr::if_else(
          .data$historical_mean > 0,
          .data$historical_sd / .data$historical_mean,
          NA_real_
        ),
        recent_growth = log1p(.data$recent_mean) - log1p(.data$previous_mean)
      ) |>
      dplyr::select(
        stable_municipality_id,
        origin,
        log_historical_mean,
        historical_cv,
        recent_growth
      )
    history
  })
}

fit_forecast_reliability_model <- function(
    data,
    covariates,
    outcome = "log_scaled_absolute_error",
    fixed_effects = c("region_code", "horizon", ".model"),
    cluster = "stable_municipality_id") {
  missing <- setdiff(
    c(outcome, covariates, fixed_effects, cluster),
    names(data)
  )
  if (length(missing) > 0L) {
    stop(
      "Reliability model is missing variables: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }

  formula <- stats::as.formula(paste0(
    outcome,
    " ~ ",
    paste(covariates, collapse = " + "),
    " | ",
    paste(fixed_effects, collapse = " + ")
  ))
  cluster_formula <- stats::as.formula(paste0("~", cluster))
  fixest::feols(formula, data = data, cluster = cluster_formula)
}

export_forecast_reliability_analysis <- function(
    error_rows,
    panel,
    config,
    label) {
  ensure_project_directories(config)
  covariates <- build_forecast_reliability_covariates(panel, error_rows)
  reliability_panel <- prepare_forecast_reliability_panel(
    error_rows,
    municipality_covariates = covariates
  )
  model_covariates <- c(
    "log_historical_mean",
    "historical_cv",
    "recent_growth"
  )
  reliability_panel <- reliability_panel |>
    dplyr::filter(stats::complete.cases(dplyr::pick(
      dplyr::all_of(model_covariates)
    )))
  if (nrow(reliability_panel) == 0L) {
    stop("No complete rows are available for the reliability model.", call. = FALSE)
  }

  model <- fit_forecast_reliability_model(
    reliability_panel,
    covariates = model_covariates
  )
  model_path <- file.path(
    config$project$output_dir,
    paste0("forecast_reliability_model_", label, ".rds")
  )
  panel_path <- file.path(
    config$project$output_dir,
    paste0("forecast_reliability_panel_", label, ".csv")
  )
  table_path <- export_fixest_latex(
    list(model),
    paste0("table_forecast_reliability_", label, ".tex"),
    config,
    dict = c(
      log_historical_mean = "Log historical mean",
      historical_cv = "Historical coefficient of variation",
      recent_growth = "Recent log growth"
    ),
    notes = "Outcome: log(1 + seasonally scaled absolute forecast error). Municipality-clustered standard errors; region, horizon, and model fixed effects."
  )
  saveRDS(model, model_path)
  readr::write_csv(reliability_panel, panel_path)
  paths <- normalizePath(
    c(model_path, panel_path, table_path),
    winslash = "/",
    mustWork = TRUE
  )
  manifest <- write_reporting_manifest(
    paths,
    config,
    paste0("manifest_forecast_reliability_", label, ".csv")
  )
  c(paths, manifest)
}
