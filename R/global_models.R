global_categorical_features <- c(
  "stable_municipality_id",
  "state_code",
  "region_code"
)

population_standard_deviation <- function(x) {
  if (length(x) == 0L || anyNA(x)) {
    return(NA_real_)
  }
  sqrt(mean((x - mean(x))^2))
}

global_numeric_feature_names <- function(config, panel = NULL) {
  lags <- sort(unique(as.integer(unlist(config$models$global$lags))))
  windows <- sort(unique(as.integer(
    unlist(config$models$global$rolling_windows)
  )))
  optional <- as.character(unlist(
    config$models$global$optional_covariates
  ))
  if (!is.null(panel)) {
    optional <- intersect(optional, names(panel))
  }

  c(
    "last_value",
    paste0("lag_", lags),
    unlist(lapply(windows, function(window) {
      c(
        paste0("rolling_mean_", window),
        paste0("rolling_sd_", window)
      )
    }), use.names = FALSE),
    "trend",
    "origin_month_sin",
    "origin_month_cos",
    optional
  )
}

build_global_feature_panel <- function(panel, config) {
  required <- c(
    "month",
    "stable_municipality_id",
    "state_code",
    "region_code",
    "payer_count"
  )
  missing <- setdiff(required, names(panel))
  if (length(missing) > 0L) {
    stop(
      "Global feature panel is missing: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }

  lags <- sort(unique(as.integer(unlist(config$models$global$lags))))
  windows <- sort(unique(as.integer(
    unlist(config$models$global$rolling_windows)
  )))

  data <- panel |>
    dplyr::mutate(
      month = as.Date(.data$month),
      stable_municipality_id = as.character(.data$stable_municipality_id),
      state_code = as.character(.data$state_code),
      region_code = as.character(.data$region_code),
      payer_count = as.numeric(.data$payer_count)
    ) |>
    dplyr::arrange(.data$stable_municipality_id, .data$month)

  for (lag_value in lags) {
    feature_name <- paste0("lag_", lag_value)
    data <- data |>
      dplyr::group_by(.data$stable_municipality_id) |>
      dplyr::mutate(
        !!feature_name := dplyr::lag(.data$payer_count, lag_value)
      ) |>
      dplyr::ungroup()
  }

  for (window in windows) {
    mean_name <- paste0("rolling_mean_", window)
    sd_name <- paste0("rolling_sd_", window)
    data <- data |>
      dplyr::group_by(.data$stable_municipality_id) |>
      dplyr::mutate(
        !!mean_name := slider::slide_dbl(
          .data$payer_count,
          mean,
          .before = window - 1L,
          .complete = TRUE
        ),
        !!sd_name := slider::slide_dbl(
          .data$payer_count,
          population_standard_deviation,
          .before = window - 1L,
          .complete = TRUE
        )
      ) |>
      dplyr::ungroup()
  }

  month_number <- lubridate::year(data$month) * 12L + lubridate::month(data$month)
  data |>
    dplyr::mutate(
      last_value = .data$payer_count,
      trend = as.numeric(month_number - min(month_number)),
      origin_month_sin = sin(2 * pi * lubridate::month(.data$month) / 12),
      origin_month_cos = cos(2 * pi * lubridate::month(.data$month) / 12)
    )
}

add_months_first_day <- function(date, months) {
  as.Date(tsibble::yearmonth(as.Date(date)) + as.integer(months))
}

stack_direct_horizon_data <- function(feature_panel, origin, config) {
  origin <- as.Date(origin)
  horizons <- sort(unique(as.integer(unlist(config$analysis$horizons))))
  categorical <- global_categorical_features
  numeric <- global_numeric_feature_names(config, feature_panel)

  training_blocks <- vector("list", length(horizons))
  prediction_blocks <- vector("list", length(horizons))
  metadata_blocks <- vector("list", length(horizons))
  target_month_blocks <- vector("list", length(horizons))

  for (index in seq_along(horizons)) {
    horizon <- horizons[[index]]
    work <- feature_panel |>
      dplyr::group_by(.data$stable_municipality_id) |>
      dplyr::mutate(
        .label = dplyr::lead(.data$payer_count, horizon),
        .target_month = add_months_first_day(.data$month, horizon)
      ) |>
      dplyr::ungroup()

    training <- work |>
      dplyr::filter(.data$.target_month <= origin, !is.na(.data$.label)) |>
      dplyr::mutate(
        horizon = horizon,
        target_month_sin = sin(
          2 * pi * lubridate::month(.data$.target_month) / 12
        ),
        target_month_cos = cos(
          2 * pi * lubridate::month(.data$.target_month) / 12
        )
      )

    prediction <- feature_panel |>
      dplyr::filter(.data$month == origin) |>
      dplyr::mutate(
        horizon = horizon,
        target_month_sin = sin(
          2 * pi * lubridate::month(add_months_first_day(origin, horizon)) / 12
        ),
        target_month_cos = cos(
          2 * pi * lubridate::month(add_months_first_day(origin, horizon)) / 12
        )
      )

    model_columns <- c(
      categorical,
      numeric,
      "horizon",
      "target_month_sin",
      "target_month_cos"
    )
    training_complete <- stats::complete.cases(training[, model_columns])
    prediction_complete <- stats::complete.cases(prediction[, model_columns])
    if (!all(prediction_complete)) {
      stop(
        "Incomplete global-model history at origin ", format(origin), ".",
        call. = FALSE
      )
    }

    training_blocks[[index]] <- training[training_complete, model_columns]
    training_blocks[[index]]$.label <- training$.label[training_complete]
    target_month_blocks[[index]] <- training$.target_month[training_complete]
    prediction_blocks[[index]] <- prediction[, model_columns]
    metadata_blocks[[index]] <- prediction |>
      dplyr::transmute(
        region_code = .data$region_code,
        state_code = .data$state_code,
        stable_municipality_id = .data$stable_municipality_id,
        origin = tsibble::yearmonth(origin),
        month = tsibble::yearmonth(add_months_first_day(origin, horizon)),
        horizon = horizon
      )
  }

  training <- dplyr::bind_rows(training_blocks)
  target <- as.numeric(training$.label)
  training$.label <- NULL
  prediction <- dplyr::bind_rows(prediction_blocks)
  metadata <- dplyr::bind_rows(metadata_blocks)
  target_months <- as.Date(do.call(c, target_month_blocks), origin = "1970-01-01")

  if (max(target_months) > origin) {
    stop("Temporal leakage guard failed for global-model labels.", call. = FALSE)
  }

  list(
    x_train = training,
    y_train = target,
    x_predict = prediction,
    metadata = metadata,
    target_months = target_months,
    categorical_features = categorical,
    numeric_features = setdiff(names(training), categorical)
  )
}

make_sparse_global_design <- function(stacked) {
  combined <- dplyr::bind_rows(stacked$x_train, stacked$x_predict)
  for (feature in stacked$categorical_features) {
    combined[[feature]] <- factor(as.character(combined[[feature]]))
  }

  design <- Matrix::sparse.model.matrix(
    ~ . - 1,
    data = combined,
    na.action = stats::na.fail
  )
  training_rows <- seq_len(nrow(stacked$x_train))
  prediction_rows <- seq.int(
    nrow(stacked$x_train) + 1L,
    nrow(combined)
  )

  list(
    x_train = design[training_rows, , drop = FALSE],
    x_predict = design[prediction_rows, , drop = FALSE],
    feature_names = colnames(design)
  )
}

inverse_global_target <- function(prediction, transform) {
  if (identical(transform, "log1p")) {
    prediction <- expm1(prediction)
  } else if (!identical(transform, "none")) {
    stop("Unknown global target transform: ", transform, call. = FALSE)
  }
  pmax(as.numeric(prediction), 0)
}

fit_ridge_global <- function(design, target, config) {
  transform <- config$models$global$target_transform
  transformed_target <- if (identical(transform, "log1p")) {
    log1p(target)
  } else {
    target
  }
  lambda <- as.numeric(config$models$global$ridge$lambda)
  model <- glmnet::glmnet(
    x = design$x_train,
    y = transformed_target,
    family = "gaussian",
    alpha = 0,
    lambda = lambda,
    standardize = TRUE,
    intercept = TRUE
  )
  prediction <- stats::predict(
    model,
    newx = design$x_predict,
    s = lambda
  )
  list(
    model = model,
    prediction = inverse_global_target(prediction, transform),
    lambda = lambda
  )
}

fit_xgboost_global <- function(design, target, config) {
  settings <- config$models$global$xgboost
  transform <- config$models$global$target_transform
  transformed_target <- if (identical(transform, "log1p")) {
    log1p(target)
  } else {
    target
  }
  dtrain <- xgboost::xgb.DMatrix(
    data = design$x_train,
    label = transformed_target
  )
  params <- list(
    objective = "reg:squarederror",
    eval_metric = "mae",
    eta = as.numeric(settings$eta),
    max_depth = as.integer(settings$max_depth),
    min_child_weight = as.numeric(settings$min_child_weight),
    subsample = as.numeric(settings$subsample),
    colsample_bytree = as.numeric(settings$colsample_bytree),
    lambda = as.numeric(settings$lambda),
    alpha = as.numeric(settings$alpha),
    seed = as.integer(config$execution$random_seed)
  )
  threads <- as.integer(config$execution$parallel_threads)
  if (threads > 0L) {
    params$nthread <- threads
  }
  model <- xgboost::xgb.train(
    params = params,
    data = dtrain,
    nrounds = as.integer(settings$nrounds),
    verbose = 0
  )
  prediction <- stats::predict(
    model,
    newdata = xgboost::xgb.DMatrix(design$x_predict)
  )
  list(
    model = model,
    prediction = inverse_global_target(prediction, transform),
    params = params,
    nrounds = as.integer(settings$nrounds)
  )
}

validate_r_global_prediction_schema <- function(predictions) {
  required <- c(
    "origin",
    "month",
    "region_code",
    "state_code",
    "stable_municipality_id",
    "hierarchy_level",
    ".model",
    "horizon",
    "prediction"
  )
  missing <- setdiff(required, names(predictions))
  if (length(missing) > 0L) {
    stop(
      "R global prediction rows are missing: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  duplicates <- predictions |>
    dplyr::count(
      .data$origin,
      .data$month,
      .data$region_code,
      .data$state_code,
      .data$stable_municipality_id,
      .data$.model,
      .data$horizon,
      name = "n"
    ) |>
    dplyr::filter(.data$n != 1L)
  if (nrow(duplicates) > 0L) {
    stop("R global predictions contain duplicate keys.", call. = FALSE)
  }
  invisible(TRUE)
}

aggregate_bottom_up_predictions <- function(predictions) {
  validate_r_global_prediction_schema(predictions)
  bottom <- predictions |>
    dplyr::filter(.data$hierarchy_level == "municipality") |>
    dplyr::mutate(.model = paste0(.data$.model, "_bottom_up"))

  state <- bottom |>
    dplyr::group_by(
      .data$origin,
      .data$month,
      .data$region_code,
      .data$state_code,
      .data$.model,
      .data$horizon
    ) |>
    dplyr::summarise(prediction = sum(.data$prediction), .groups = "drop") |>
    dplyr::mutate(
      stable_municipality_id = "__AGGREGATED__",
      hierarchy_level = "state"
    )

  region <- bottom |>
    dplyr::group_by(
      .data$origin,
      .data$month,
      .data$region_code,
      .data$.model,
      .data$horizon
    ) |>
    dplyr::summarise(prediction = sum(.data$prediction), .groups = "drop") |>
    dplyr::mutate(
      state_code = "__AGGREGATED__",
      stable_municipality_id = "__AGGREGATED__",
      hierarchy_level = "region"
    )

  national <- bottom |>
    dplyr::group_by(
      .data$origin,
      .data$month,
      .data$.model,
      .data$horizon
    ) |>
    dplyr::summarise(prediction = sum(.data$prediction), .groups = "drop") |>
    dplyr::mutate(
      region_code = "__AGGREGATED__",
      state_code = "__AGGREGATED__",
      stable_municipality_id = "__AGGREGATED__",
      hierarchy_level = "national"
    )

  dplyr::bind_rows(bottom, state, region, national) |>
    dplyr::select(dplyr::all_of(c(
      "origin",
      "month",
      "region_code",
      "state_code",
      "stable_municipality_id",
      "hierarchy_level",
      ".model",
      "horizon",
      "prediction"
    )))
}

canonical_hierarchy_table <- function(hierarchy_ts) {
  keys <- tsibble::key_vars(hierarchy_ts)
  hierarchy_ts |>
    tibble::as_tibble() |>
    dplyr::mutate(
      hierarchy_level = classify_hierarchy_level(
        dplyr::pick(dplyr::all_of(keys))
      ),
      dplyr::across(
        dplyr::all_of(keys),
        ~ ifelse(
          fabletools::is_aggregated(.x),
          "__AGGREGATED__",
          as.character(.x)
        )
      )
    )
}

global_predictions_to_error_rows <- function(
    predictions,
    hierarchy_ts,
    origin,
    config) {
  validate_r_global_prediction_schema(predictions)
  keys <- tsibble::key_vars(hierarchy_ts)
  index <- tsibble::index_var(hierarchy_ts)
  canonical <- canonical_hierarchy_table(hierarchy_ts)
  actual <- canonical |>
    dplyr::select(dplyr::all_of(c(keys, index, "payer_count"))) |>
    dplyr::rename(actual = payer_count)
  training <- canonical |>
    dplyr::filter(.data[[index]] <= origin)
  scales <- training |>
    dplyr::arrange(dplyr::across(dplyr::all_of(c(keys, index)))) |>
    dplyr::group_by(dplyr::across(dplyr::all_of(keys))) |>
    dplyr::summarise(
      mae_scale = mean(
        abs(
          .data$payer_count -
            dplyr::lag(
              .data$payer_count,
              as.integer(config$analysis$seasonal_period)
            )
        ),
        na.rm = TRUE
      ),
      rmsse_scale = sqrt(mean(
        (
          .data$payer_count -
            dplyr::lag(
              .data$payer_count,
              as.integer(config$analysis$seasonal_period)
            )
        )^2,
        na.rm = TRUE
      )),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      mae_scale = valid_forecast_scale(.data$mae_scale),
      rmsse_scale = valid_forecast_scale(.data$rmsse_scale)
    )

  result <- predictions |>
    dplyr::left_join(actual, by = c(keys, index)) |>
    dplyr::left_join(scales, by = keys) |>
    dplyr::mutate(
      error = .data$actual - .data$prediction,
      absolute_error = abs(.data$error),
      squared_error = .data$error^2
    )
  if (any(is.na(result$actual))) {
    stop("R global forecasts do not match the canonical hierarchy.", call. = FALSE)
  }
  result
}

global_model_summary_table <- function(fitted, config, origin) {
  rows <- list()
  if (!is.null(fitted$ridge_global)) {
    rows[[length(rows) + 1L]] <- tibble::tibble(
      Model = "ridge_global",
      Engine = "glmnet",
      Transform = config$models$global$target_transform,
      Hyperparameters = paste0("alpha=0; lambda=", fitted$ridge_global$lambda),
      `Last fitted origin` = format(as.Date(origin), "%Y-%m")
    )
  }
  if (!is.null(fitted$xgboost_global)) {
    settings <- config$models$global$xgboost
    rows[[length(rows) + 1L]] <- tibble::tibble(
      Model = "xgboost_global",
      Engine = "xgboost",
      Transform = config$models$global$target_transform,
      Hyperparameters = paste0(
        "rounds=", settings$nrounds,
        "; eta=", settings$eta,
        "; depth=", settings$max_depth,
        "; subsample=", settings$subsample,
        "; colsample=", settings$colsample_bytree
      ),
      `Last fitted origin` = format(as.Date(origin), "%Y-%m")
    )
  }
  dplyr::bind_rows(rows)
}

export_global_model_artifacts <- function(
    fitted,
    design,
    config,
    label,
    origin) {
  model_directory <- file.path(config$project$output_dir, "models")
  dir.create(model_directory, recursive = TRUE, showWarnings = FALSE)
  paths <- character()

  summary <- global_model_summary_table(fitted, config, origin)
  summary_csv <- file.path(
    config$project$output_dir,
    paste0("global_model_parameters_", label, ".csv")
  )
  readr::write_csv(summary, summary_csv)
  paths <- c(
    paths,
    normalizePath(summary_csv, winslash = "/", mustWork = TRUE),
    article_table(
      summary,
      paste0("table_global_model_parameters_", label, ".tex"),
      "Global R model specification",
      config,
      notes = "All features and labels are reconstructed within each expanding forecast origin.",
      digits = 0L
    )
  )

  if (!is.null(fitted$ridge_global)) {
    model_path <- file.path(
      model_directory,
      paste0("ridge_global_", label, ".rds")
    )
    saveRDS(fitted$ridge_global$model, model_path)
    paths <- c(paths, normalizePath(model_path, winslash = "/", mustWork = TRUE))
  }

  if (!is.null(fitted$xgboost_global)) {
    model_path <- file.path(
      model_directory,
      paste0("xgboost_global_", label, ".rds")
    )
    saveRDS(fitted$xgboost_global$model, model_path)
    paths <- c(paths, normalizePath(model_path, winslash = "/", mustWork = TRUE))

    importance <- xgboost::xgb.importance(
      model = fitted$xgboost_global$model
    ) |>
      tibble::as_tibble() |>
      dplyr::slice_head(n = 30L)
    importance_csv <- file.path(
      config$project$output_dir,
      paste0("xgboost_feature_importance_", label, ".csv")
    )
    readr::write_csv(importance, importance_csv)
    paths <- c(
      paths,
      normalizePath(importance_csv, winslash = "/", mustWork = TRUE),
      article_table(
        importance,
        paste0("table_xgboost_feature_importance_", label, ".tex"),
        "XGBoost feature importance",
        config,
        notes = "Importance is computed from the model fitted at the final rolling origin."
      )
    )

    sample_size <- min(
      as.integer(config$execution$shap_sample_rows),
      nrow(design$x_predict)
    )
    set.seed(as.integer(config$execution$random_seed))
    sample_rows <- sample(seq_len(nrow(design$x_predict)), sample_size)
    contributions <- stats::predict(
      fitted$xgboost_global$model,
      newdata = xgboost::xgb.DMatrix(
        design$x_predict[sample_rows, , drop = FALSE]
      ),
      predcontrib = TRUE
    )
    if (is.null(dim(contributions))) {
      contributions <- matrix(contributions, nrow = 1L)
    }
    contribution_names <- colnames(contributions)
    if (is.null(contribution_names)) {
      contribution_names <- c(design$feature_names, "BIAS")
    }
    keep <- contribution_names != "BIAS"
    shap <- tibble::tibble(
      Feature = contribution_names[keep],
      `Mean absolute SHAP` = colMeans(abs(contributions[, keep, drop = FALSE]))
    ) |>
      dplyr::arrange(dplyr::desc(.data$`Mean absolute SHAP`)) |>
      dplyr::slice_head(n = 25L)
    shap_csv <- file.path(
      config$project$output_dir,
      paste0("xgboost_shap_", label, ".csv")
    )
    readr::write_csv(shap, shap_csv)
    paths <- c(
      paths,
      normalizePath(shap_csv, winslash = "/", mustWork = TRUE),
      article_table(
        shap,
        paste0("table_xgboost_shap_", label, ".tex"),
        "Mean absolute TreeSHAP contributions",
        config,
        notes = "TreeSHAP is computed on a reproducible sample from the final forecast origin."
      )
    )
    shap_plot <- ggplot2::ggplot(
      shap,
      ggplot2::aes(
        x = stats::reorder(.data$Feature, .data$`Mean absolute SHAP`),
        y = .data$`Mean absolute SHAP`
      )
    ) +
      ggplot2::geom_col(fill = "#2166AC") +
      ggplot2::coord_flip() +
      ggplot2::labs(
        title = "Predictive contribution of the global XGBoost features",
        subtitle = paste("Experiment:", label),
        x = NULL,
        y = "Mean absolute TreeSHAP contribution"
      ) +
      theme_article()
    paths <- c(
      paths,
      save_article_figure(
        shap_plot,
        paste0("figure_xgboost_shap_", label),
        config,
        height = 6.2
      )
    )
  }

  paths <- c(paths, write_session_snapshot(config, paste0("global_", label)))
  manifest <- write_reporting_manifest(
    paths,
    config,
    paste0("manifest_global_model_outputs_", label, ".csv")
  )
  c(paths, manifest)
}

export_final_global_model_artifacts <- function(
    panel,
    config,
    label,
    feature_panel = NULL) {
  origins <- make_rolling_origins(
    months = panel$month,
    initial_window = config$analysis$initial_window_months,
    maximum_horizon = max(as.integer(unlist(config$analysis$horizons))),
    step = config$analysis$origin_step_months
  )
  final_origin <- utils::tail(origins, 1L)
  if (is.null(feature_panel)) {
    feature_panel <- build_global_feature_panel(panel, config)
  }
  fit <- fit_global_models_at_origin(feature_panel, final_origin, config)
  export_global_model_artifacts(
    fit$fitted,
    fit$design,
    config,
    label,
    final_origin
  )
}

fit_global_models_at_origin <- function(feature_panel, origin, config) {
  stacked <- stack_direct_horizon_data(feature_panel, origin, config)
  design <- make_sparse_global_design(stacked)
  fitted <- list()
  prediction_blocks <- list()

  if (isTRUE(config$models$global$ridge$enabled)) {
    fitted$ridge_global <- fit_ridge_global(design, stacked$y_train, config)
    prediction_blocks[[length(prediction_blocks) + 1L]] <- stacked$metadata |>
      dplyr::mutate(
        hierarchy_level = "municipality",
        .model = "ridge_global",
        prediction = fitted$ridge_global$prediction
      )
  }
  if (isTRUE(config$models$global$xgboost$enabled)) {
    fitted$xgboost_global <- fit_xgboost_global(
      design,
      stacked$y_train,
      config
    )
    prediction_blocks[[length(prediction_blocks) + 1L]] <- stacked$metadata |>
      dplyr::mutate(
        hierarchy_level = "municipality",
        .model = "xgboost_global",
        prediction = fitted$xgboost_global$prediction
      )
  }

  predictions <- dplyr::bind_rows(prediction_blocks) |>
    dplyr::select(dplyr::all_of(c(
      "origin",
      "month",
      "region_code",
      "state_code",
      "stable_municipality_id",
      "hierarchy_level",
      ".model",
      "horizon",
      "prediction"
    )))
  validate_r_global_prediction_schema(predictions)
  list(predictions = predictions, fitted = fitted, design = design)
}

global_run_signature <- function(panel, config, label) {
  digest::digest(list(
    label = label,
    code_hashes = vapply(
      c(
        "R/global_models.R",
        "R/metrics.R",
        "R/build_targets.R"
      ),
      function(path) digest::digest(path, file = TRUE),
      character(1)
    ),
    analysis = config$analysis,
    models = config$models$global,
    data_hash = digest::digest(panel, algo = "xxhash64")
  ))
}

rolling_origin_global_evaluate <- function(
    panel,
    hierarchy_ts,
    config,
    label = "pilot",
    feature_panel = NULL) {
  origins <- make_rolling_origins(
    months = panel$month,
    initial_window = config$analysis$initial_window_months,
    maximum_horizon = max(as.integer(unlist(config$analysis$horizons))),
    step = config$analysis$origin_step_months
  )
  if (is.null(feature_panel)) {
    feature_panel <- build_global_feature_panel(panel, config)
  }
  signature <- global_run_signature(panel, config, label)
  checkpoint_directory <- file.path(
    config$project$processed_dir,
    "checkpoints",
    paste0("global_", label, "_", substr(signature, 1L, 12L))
  )
  dir.create(checkpoint_directory, recursive = TRUE, showWarnings = FALSE)
  resume <- isTRUE(config$execution$resume)
  results <- vector("list", length(origins))

  for (index in seq_along(origins)) {
    origin <- origins[[index]]
    checkpoint <- file.path(
      checkpoint_directory,
      paste0("origin_", format(as.Date(origin), "%Y-%m"), ".rds")
    )
    if (resume && file.exists(checkpoint)) {
      message(
        "Global R origin ", index, "/", length(origins), " ",
        format(as.Date(origin), "%Y-%m"), ": checkpoint loaded."
      )
      results[[index]] <- readRDS(checkpoint)
      next
    }

    message(
      "Global R origin ", index, "/", length(origins), " ",
      format(as.Date(origin), "%Y-%m"), "."
    )
    started <- proc.time()[["elapsed"]]
    fit <- fit_global_models_at_origin(feature_panel, origin, config)
    coherent <- aggregate_bottom_up_predictions(fit$predictions)
    errors <- global_predictions_to_error_rows(
      coherent,
      hierarchy_ts,
      tsibble::yearmonth(as.Date(origin)),
      config
    )
    elapsed <- proc.time()[["elapsed"]] - started
    errors <- errors |>
      dplyr::mutate(
        evaluation_batch = "global_r_bottom_up",
        origin_elapsed_seconds = elapsed
      )
    saveRDS(errors, checkpoint)
    results[[index]] <- errors
  }

  dplyr::bind_rows(results)
}
