make_rolling_origins <- function(
    months,
    initial_window = 36L,
    maximum_horizon = 6L,
    step = 1L) {
  months <- sort(unique(months))
  last_origin <- length(months) - as.integer(maximum_horizon)

  if (last_origin < as.integer(initial_window)) {
    stop("Not enough months for the requested rolling-origin design.", call. = FALSE)
  }

  indices <- seq.int(
    from = as.integer(initial_window),
    to = last_origin,
    by = as.integer(step)
  )
  months[indices]
}

evaluate_forecast_origin <- function(
    hierarchy_ts,
    origin,
    horizons,
    reconciled = FALSE,
    include_mint_shrink = FALSE,
    include_arima = TRUE,
    seasonal_period = 12L) {
  maximum_horizon <- max(as.integer(horizons))
  training <- hierarchy_ts |>
    dplyr::filter(.data$month <= origin)
  actual <- hierarchy_ts |>
    dplyr::filter(.data$month %in% (origin + as.integer(horizons)))

  models <- if (reconciled) {
    fit_reconciled_ets(
      training,
      include_mint_shrink = include_mint_shrink
    )
  } else {
    fit_local_baselines(training, include_arima = include_arima)
  }

  forecasts <- fabletools::forecast(models, h = maximum_horizon)
  forecast_error_rows(
    forecasts = forecasts,
    actual = actual,
    training = training,
    origin = origin,
    horizons = horizons,
    response = "payer_count",
    seasonal_period = seasonal_period
  )
}

rolling_origin_evaluate <- function(
    hierarchy_ts,
    config,
    reconciled = FALSE,
    include_arima = TRUE,
    label = NULL) {
  horizons <- as.integer(unlist(config$analysis$horizons))
  origins <- make_rolling_origins(
    months = hierarchy_ts$month,
    initial_window = config$analysis$initial_window_months,
    maximum_horizon = max(horizons),
    step = config$analysis$origin_step_months
  )

  batch <- dplyr::case_when(
    reconciled ~ "reconciled_ets",
    include_arima ~ "local_with_arima",
    TRUE ~ "local_without_arima"
  )
  use_checkpoints <- !is.null(label) && isTRUE(config$execution$resume)
  if (use_checkpoints) {
    signature <- substr(digest::digest(list(
      label = label,
      batch = batch,
      code_hashes = vapply(
        c(
          "R/rolling_origin.R",
          "R/baselines.R",
          "R/reconciliation.R",
          "R/metrics.R",
          "R/build_targets.R"
        ),
        function(path) digest::digest(path, file = TRUE),
        character(1)
      ),
      analysis = config$analysis,
      data_hash = digest::digest(hierarchy_ts, algo = "xxhash64"),
      # ARIMA silently returns NULL models without urca (pilot of 2026-10-02):
      # checkpoints computed without it must not be reused once it is installed.
      arima_backend = if (identical(batch, "local_with_arima")) {
        requireNamespace("urca", quietly = TRUE)
      } else {
        NA
      }
    )), 1L, 12L)
    checkpoint_directory <- file.path(
      config$project$processed_dir,
      "checkpoints",
      paste0(label, "_", batch, "_", signature)
    )
    dir.create(checkpoint_directory, recursive = TRUE, showWarnings = FALSE)
  }

  results <- vector("list", length(origins))
  for (index in seq_along(origins)) {
    origin <- origins[[index]]
    if (use_checkpoints) {
      checkpoint <- file.path(
        checkpoint_directory,
        paste0("origin_", format(as.Date(origin), "%Y-%m"), ".rds")
      )
      if (file.exists(checkpoint)) {
        message(
          "Evaluating origin ", index, "/", length(origins), " ",
          format(origin), ": checkpoint loaded."
        )
        results[[index]] <- readRDS(checkpoint)
        next
      }
    }

    message(
      "Evaluating origin ", index, "/", length(origins), " ",
      format(origin), "."
    )
    started <- proc.time()[["elapsed"]]
    result <- evaluate_forecast_origin(
      hierarchy_ts = hierarchy_ts,
      origin = origin,
      horizons = horizons,
      reconciled = reconciled,
      include_mint_shrink = isTRUE(config$analysis$include_full_mint),
      include_arima = include_arima,
      seasonal_period = config$analysis$seasonal_period
    )
    elapsed <- proc.time()[["elapsed"]] - started
    result <- result |>
      dplyr::mutate(
        evaluation_batch = batch,
        origin_elapsed_seconds = elapsed
      )
    if (use_checkpoints) {
      saveRDS(result, checkpoint)
    }
    results[[index]] <- result
  }
  dplyr::bind_rows(results)
}
