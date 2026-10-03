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

  spec <- list(
    origins = origins,
    horizons = horizons,
    reconciled = reconciled,
    include_mint_shrink = isTRUE(config$analysis$include_full_mint),
    include_arima = include_arima,
    seasonal_period = config$analysis$seasonal_period,
    batch = batch,
    checkpoint_directory = if (use_checkpoints) checkpoint_directory else NULL
  )

  results <- vector("list", length(origins))
  pending <- integer()
  for (index in seq_along(origins)) {
    checkpoint <- origin_checkpoint_path(spec, index)
    if (!is.null(checkpoint) && file.exists(checkpoint)) {
      message(
        "Evaluating origin ", index, "/", length(origins), " ",
        format(origins[[index]]), ": checkpoint loaded."
      )
      results[[index]] <- readRDS(checkpoint)
    } else {
      pending <- c(pending, index)
    }
  }

  workers <- resolve_origin_workers(config$execution$workers, length(pending))
  if (workers > 1L) {
    message(
      "Evaluating ", length(pending), " origins on ", workers,
      " parallel workers", if (use_checkpoints) {
        paste0(" (progress: ", file.path(checkpoint_directory, "progress.log"), ")")
      }, "."
    )
  }
  computed <- run_origin_tasks(
    indices = pending,
    task = evaluate_origin_index,
    workers = workers,
    worker_setup = setup_origin_worker,
    worker_data = list(hierarchy_ts = hierarchy_ts, spec = spec)
  )
  results[pending] <- computed
  dplyr::bind_rows(results)
}

origin_checkpoint_path <- function(spec, index) {
  if (is.null(spec$checkpoint_directory)) {
    return(NULL)
  }
  file.path(
    spec$checkpoint_directory,
    paste0("origin_", format(as.Date(spec$origins[[index]]), "%Y-%m"), ".rds")
  )
}

# One rolling origin: fit, forecast, score and (when resuming) save the checkpoint.
# The same function runs sequentially and inside the parallel workers, so the
# results do not depend on execution$workers.
evaluate_origin_index <- function(index, data) {
  spec <- data$spec
  origin <- spec$origins[[index]]
  message(
    "Evaluating origin ", index, "/", length(spec$origins), " ",
    format(origin), "."
  )
  started <- proc.time()[["elapsed"]]
  result <- evaluate_forecast_origin(
    hierarchy_ts = data$hierarchy_ts,
    origin = origin,
    horizons = spec$horizons,
    reconciled = spec$reconciled,
    include_mint_shrink = spec$include_mint_shrink,
    include_arima = spec$include_arima,
    seasonal_period = spec$seasonal_period
  )
  elapsed <- proc.time()[["elapsed"]] - started
  result <- result |>
    dplyr::mutate(
      evaluation_batch = spec$batch,
      origin_elapsed_seconds = elapsed
    )
  checkpoint <- origin_checkpoint_path(spec, index)
  if (!is.null(checkpoint)) {
    saveRDS(result, checkpoint)
    cat(
      sprintf(
        "%s origin %d/%d %s done in %.0f s\n",
        format(Sys.time(), "%Y-%m-%d %H:%M:%S"), index, length(spec$origins),
        format(origin), elapsed
      ),
      file = file.path(spec$checkpoint_directory, "progress.log"),
      append = TRUE
    )
  }
  result
}

# execution$workers: positive integer or "auto" (physical cores - 1); never more
# workers than pending tasks. Missing means 1 (sequential, the previous behaviour).
resolve_origin_workers <- function(value, n_tasks) {
  if (is.null(value)) {
    value <- 1L
  }
  if (identical(tolower(as.character(value)), "auto")) {
    cores <- parallel::detectCores(logical = FALSE)
    value <- if (is.na(cores)) 1L else max(1L, cores - 1L)
  }
  value <- suppressWarnings(as.integer(value))
  if (length(value) != 1L || is.na(value) || value < 1L) {
    stop("execution$workers must be a positive integer or \"auto\".", call. = FALSE)
  }
  max(1L, min(value, as.integer(n_tasks)))
}

# Runs task(index, worker_data) for every index. With workers > 1 it uses a PSOCK
# cluster (base R `parallel`, works on Windows): worker_data is sent once to each
# worker, tasks are load-balanced, and results come back in the order of indices.
run_origin_tasks <- function(indices, task, workers = 1L, worker_setup = NULL, worker_data = list()) {
  if (length(indices) == 0L) {
    return(list())
  }
  if (workers <= 1L || length(indices) == 1L) {
    return(lapply(indices, task, data = worker_data))
  }
  # Workers skip the project .Rprofile (--no-init-file): with renv, 13 workers
  # activating the project at once exceeded the connection timeout on Windows
  # (national run of 2026-10-03: "11 of 13 workers failed to connect"). The
  # master's library paths are passed below, so the same packages are used.
  cluster <- parallel::makePSOCKcluster(
    workers,
    rscript_args = "--no-init-file",
    setup_strategy = "sequential",
    setup_timeout = 600
  )
  on.exit(parallel::stopCluster(cluster), add = TRUE)
  parallel::clusterCall(cluster, function(paths) {
    .libPaths(paths)
    invisible(NULL)
  }, .libPaths())
  if (!is.null(worker_setup)) {
    parallel::clusterCall(cluster, worker_setup, getwd())
  }
  parallel::clusterCall(cluster, function(data) {
    assign(".origin_task_data", data, envir = globalenv())
    invisible(NULL)
  }, worker_data)
  runner <- local(
    function(index) task(index, data = get(".origin_task_data", envir = globalenv())),
    envir = list2env(list(task = task), parent = globalenv())
  )
  parallel::parLapplyLB(cluster, indices, runner)
}

# Worker start-up for the forecasting tasks: same packages and project code as the
# targets pipeline.
setup_origin_worker <- function(project_dir) {
  setwd(project_dir)
  for (package in c("dplyr", "tsibble", "fabletools", "fable", "feasts")) {
    suppressPackageStartupMessages(library(package, character.only = TRUE))
  }
  targets::tar_source(file.path(project_dir, "R"), envir = globalenv())
  invisible(TRUE)
}
