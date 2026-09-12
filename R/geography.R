validate_municipality_geometry <- function(geometry) {
  if (!inherits(geometry, "sf")) {
    stop("Municipality geometry must be an sf object.", call. = FALSE)
  }
  required <- "stable_municipality_id"
  missing <- setdiff(required, names(geometry))
  if (length(missing) > 0L) {
    stop(
      "Municipality geometry is missing: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  if (is.na(sf::st_crs(geometry))) {
    stop("Municipality geometry has no coordinate reference system.", call. = FALSE)
  }
  if (anyDuplicated(geometry$stable_municipality_id)) {
    stop("Municipality geometry contains duplicated stable keys.", call. = FALSE)
  }
  if (any(sf::st_is_empty(geometry), na.rm = TRUE)) {
    stop("Municipality geometry contains empty geometries.", call. = FALSE)
  }
  validity <- sf::st_is_valid(geometry)
  if (any(is.na(validity)) || any(!validity)) {
    geometry <- sf::st_make_valid(geometry)
  }
  validity <- sf::st_is_valid(geometry)
  if (any(is.na(validity)) || any(!validity)) {
    stop("Municipality geometry remains invalid after repair.", call. = FALSE)
  }
  geometry
}

read_municipality_geometry <- function(config, year = NULL, refresh = FALSE) {
  if (is.null(year)) {
    year <- as.integer(config$geography$geometry_year)
  }
  cache_path <- config$geography$geometry_cache_file
  cache_signature <- digest::digest(list(
    year = as.integer(year),
    stable_key = config$geography$stable_mt_key,
    stable_codes = sort(as.integer(unlist(config$geography$stable_mt_codes)))
  ))
  if (!isTRUE(refresh) && file.exists(cache_path)) {
    cached <- readRDS(cache_path)
    if (identical(attr(cached, "pix_geometry_signature"), cache_signature)) {
      return(validate_municipality_geometry(cached))
    }
    warning(
      "Cached municipality geometry does not match the current configuration; rebuilding it.",
      call. = FALSE
    )
  }

  geometry <- geobr::read_municipality(
    code_muni = "all",
    year = as.integer(year),
    simplified = TRUE,
    showProgress = FALSE
  )
  if (!"code_muni" %in% names(geometry)) {
    stop("The geobr municipality schema no longer contains code_muni.", call. = FALSE)
  }

  stable_codes <- as.integer(unlist(config$geography$stable_mt_codes))
  geometry <- geometry |>
    dplyr::mutate(
      municipality_code = as.integer(.data$code_muni),
      stable_municipality_id = dplyr::if_else(
        .data$municipality_code %in% stable_codes,
        config$geography$stable_mt_key,
        as.character(.data$municipality_code)
      )
    ) |>
    dplyr::group_by(.data$stable_municipality_id) |>
    dplyr::summarise(.groups = "drop")

  geometry <- validate_municipality_geometry(geometry)
  attr(geometry, "pix_geometry_signature") <- cache_signature
  dir.create(dirname(cache_path), recursive = TRUE, showWarnings = FALSE)
  saveRDS(geometry, cache_path)
  geometry
}

validate_geometry_coverage <- function(geometry, required_ids) {
  required <- required_ids |>
    dplyr::transmute(
      stable_municipality_id = as.character(.data$stable_municipality_id)
    ) |>
    dplyr::distinct()
  available <- geometry |>
    sf::st_drop_geometry() |>
    dplyr::transmute(
      stable_municipality_id = as.character(.data$stable_municipality_id)
    ) |>
    dplyr::distinct()
  missing <- dplyr::anti_join(
    required,
    available,
    by = "stable_municipality_id"
  )
  if (nrow(missing) > 0L) {
    stop(
      "The map is missing ",
      nrow(missing),
      " required municipality keys. Examples: ",
      paste(utils::head(missing$stable_municipality_id, 10L), collapse = ", "),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

safe_export_gain_map <- function(error_rows, config, label, horizon = 1L) {
  tryCatch(
    {
      required_ids <- error_rows |>
        dplyr::filter(.data$hierarchy_level == "municipality") |>
        dplyr::distinct(.data$stable_municipality_id)
      geometry <- read_municipality_geometry(config)
      validate_geometry_coverage(geometry, required_ids)
      geometry <- geometry |>
        dplyr::inner_join(required_ids, by = "stable_municipality_id")
      plot <- plot_forecast_gain_map(
        municipality_geometry = geometry,
        error_rows = error_rows,
        benchmark_model = config$reporting$benchmark_model,
        comparison_model = config$reporting$comparison_model,
        horizon = horizon
      )
      save_article_figure(
        plot,
        paste0("figure_forecast_gain_map_", label, "_h", as.integer(horizon)),
        config,
        width = 7.2,
        height = 6.6
      )
    },
    error = function(error) {
      message_text <- paste0(
        "The forecast-gain map was not generated: ",
        conditionMessage(error)
      )
      if (
        is_full_run(config) &&
          isTRUE(config$geography$fail_on_map_error_full_run)
      ) {
        stop(message_text, call. = FALSE)
      }
      warning(
        message_text,
        call. = FALSE
      )
      ensure_project_directories(config)
      marker <- file.path(
        config$project$output_dir,
        paste0("forecast_gain_map_unavailable_", label, ".txt")
      )
      writeLines(
        c(
          message_text,
          paste("Generated UTC:", format(Sys.time(), tz = "UTC", usetz = TRUE))
        ),
        marker,
        useBytes = TRUE
      )
      normalizePath(marker, winslash = "/", mustWork = TRUE)
    }
  )
}
