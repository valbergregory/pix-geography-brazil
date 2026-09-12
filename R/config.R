read_project_config <- function(path = "config.yml") {
  if (!file.exists(path)) {
    stop("Configuration file not found: ", path, call. = FALSE)
  }

  config <- yaml::read_yaml(path)
  validate_project_config(config)
  config
}

validate_project_config <- function(config) {
  required_sections <- c(
    "project",
    "bcb",
    "quality",
    "analysis",
    "geography",
    "models",
    "execution",
    "reporting"
  )
  missing_sections <- setdiff(required_sections, names(config))

  if (length(missing_sections) > 0L) {
    stop(
      "Missing config sections: ", paste(missing_sections, collapse = ", "),
      call. = FALSE
    )
  }

  horizons <- as.integer(unlist(config$analysis$horizons))
  if (length(horizons) == 0L || any(horizons <= 0L)) {
    stop("Forecast horizons must be positive integers.", call. = FALSE)
  }

  if (as.integer(config$analysis$initial_window_months) < 24L) {
    stop("The initial training window must contain at least 24 months.", call. = FALSE)
  }
  if (as.integer(config$bcb$page_size) <= 0L) {
    stop("BCB page_size must be a positive integer.", call. = FALSE)
  }
  if (as.integer(config$bcb$max_tries) < 2L) {
    stop("BCB max_tries must be at least two.", call. = FALSE)
  }
  max_pages <- suppressWarnings(as.integer(config$bcb$max_pages))
  if (
    length(max_pages) != 1L ||
      is.na(max_pages) ||
      !is.finite(max_pages) ||
      max_pages < 1L
  ) {
    stop("BCB max_pages must be a finite positive integer.", call. = FALSE)
  }
  if (!nzchar(as.character(config$bcb$database_parameter))) {
    stop("BCB database_parameter must not be empty.", call. = FALSE)
  }
  if (as.integer(config$quality$minimum_identified_units) < 1L) {
    stop("quality$minimum_identified_units must be positive.", call. = FALSE)
  }
  if (!is.logical(config$quality$strict_geographic_coverage)) {
    stop("quality$strict_geographic_coverage must be TRUE or FALSE.", call. = FALSE)
  }
  if (!is.logical(config$quality$require_complete_panel)) {
    stop("quality$require_complete_panel must be TRUE or FALSE.", call. = FALSE)
  }
  if (as.integer(config$geography$geometry_year) < 2000L) {
    stop("geography$geometry_year is invalid.", call. = FALSE)
  }
  if (!nzchar(as.character(config$geography$geometry_cache_file))) {
    stop("geography$geometry_cache_file must not be empty.", call. = FALSE)
  }

  lags <- as.integer(unlist(config$models$global$lags))
  rolling_windows <- as.integer(unlist(config$models$global$rolling_windows))
  if (length(lags) == 0L || any(lags <= 0L)) {
    stop("Global-model lags must be positive integers.", call. = FALSE)
  }
  if (length(rolling_windows) == 0L || any(rolling_windows <= 1L)) {
    stop("Global-model rolling windows must be integers greater than one.", call. = FALSE)
  }

  enabled_global <- c(
    ridge_global = isTRUE(config$models$global$ridge$enabled),
    xgboost_global = isTRUE(config$models$global$xgboost$enabled)
  )
  if (!any(enabled_global)) {
    stop("At least one global R model must be enabled.", call. = FALSE)
  }

  pilot_states <- unique(as.integer(unlist(config$analysis$pilot_state_codes)))
  if (length(pilot_states) < 2L) {
    warning(
      "The pilot contains fewer than two states; hierarchy diagnostics will be degenerate.",
      call. = FALSE
    )
  }

  invisible(TRUE)
}

is_full_run <- function(config) {
  variable <- config$analysis$full_run_environment_variable
  value <- tolower(Sys.getenv(variable, unset = "false"))
  value %in% c("1", "true", "yes")
}

ensure_project_directories <- function(config) {
  dirs <- c(
    unlist(config$project[c("raw_dir", "processed_dir", "output_dir")]),
    unlist(config$reporting[c("tables_dir", "figures_dir", "latex_dir")])
  )
  invisible(lapply(dirs, dir.create, recursive = TRUE, showWarnings = FALSE))
}

timestamp_id <- function(time = Sys.time()) {
  format(time, "%Y%m%dT%H%M%SZ", tz = "UTC")
}
