safe_break_detection <- function(series, config) {
  minimum_segment <- as.integer(config$analysis$minimum_break_segment)
  bai_perron <- tryCatch(
    detect_bai_perron(
      series,
      value = "payer_count",
      min_segment = minimum_segment
    ),
    error = function(error) {
      warning("Bai-Perron diagnostic failed: ", conditionMessage(error))
      tibble::tibble(
        method = character(),
        break_index = integer(),
        break_month = series$month[integer()]
      )
    }
  )
  pelt <- tryCatch(
    detect_pelt(
      series,
      value = "payer_count",
      min_segment = max(6L, minimum_segment %/% 2L)
    ),
    error = function(error) {
      warning("PELT diagnostic failed: ", conditionMessage(error))
      tibble::tibble(
        method = character(),
        break_index = integer(),
        break_month = series$month[integer()]
      )
    }
  )
  dplyr::bind_rows(bai_perron, pelt) |>
    dplyr::arrange(.data$break_month, .data$method)
}

write_reporting_manifest <- function(paths, config, filename) {
  ensure_project_directories(config)
  path <- file.path(config$reporting$latex_dir, filename)
  paths <- unique(paths[file.exists(paths)])
  manifest <- tibble::tibble(
    artifact = basename(paths),
    path = normalizePath(paths, winslash = "/", mustWork = TRUE),
    extension = tools::file_ext(paths),
    sha256 = vapply(
      paths,
      digest::digest,
      character(1),
      algo = "sha256",
      file = TRUE
    ),
    generated_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
  )
  readr::write_csv(manifest, path)
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

write_session_snapshot <- function(config, label = "analysis") {
  ensure_project_directories(config)
  path <- file.path(
    config$project$output_dir,
    paste0("session_info_", label, ".txt")
  )
  lockfile <- "renv.lock"
  lock_hash <- if (file.exists(lockfile)) {
    digest::digest(lockfile, algo = "sha256", file = TRUE)
  } else {
    "not available; create it with renv::snapshot()"
  }
  source_files <- sort(c("_targets.R", list.files("R", "[.]R$", full.names = TRUE)))
  source_hashes <- vapply(
    source_files,
    digest::digest,
    character(1),
    algo = "sha256",
    file = TRUE
  )
  source_tree_hash <- digest::digest(
    list(files = source_files, hashes = source_hashes),
    algo = "sha256"
  )
  lines <- c(
    paste("Generated UTC:", format(Sys.time(), tz = "UTC", usetz = TRUE)),
    paste("Configuration SHA-256:", digest::digest("config.yml", algo = "sha256", file = TRUE)),
    paste("R source tree SHA-256:", source_tree_hash),
    paste("renv.lock SHA-256:", lock_hash),
    "",
    utils::capture.output(sessionInfo())
  )
  writeLines(lines, path, useBytes = TRUE)
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

export_data_quality_outputs <- function(raw_data, panel, config) {
  ensure_project_directories(config)
  coverage_path <- file.path(
    config$project$output_dir,
    "municipal_coverage_by_month.csv"
  )
  gaps_path <- file.path(
    config$project$output_dir,
    "analysis_panel_calendar_gaps.csv"
  )
  readr::write_csv(geographic_coverage_by_month(raw_data), coverage_path)
  readr::write_csv(
    analysis_panel_calendar_gaps(
      panel,
      exclude_ids = config$geography$unidentified_key
    ),
    gaps_path
  )
  paths <- normalizePath(
    c(coverage_path, gaps_path),
    winslash = "/",
    mustWork = TRUE
  )
  manifest <- write_reporting_manifest(
    paths,
    config,
    "manifest_data_quality.csv"
  )
  c(paths, manifest)
}

create_descriptive_outputs <- function(panel, config) {
  ensure_project_directories(config)
  break_series <- aggregate_break_series(panel, level = "national")
  breaks <- safe_break_detection(break_series, config)
  break_file <- file.path(config$project$output_dir, "structural_breaks.csv")
  readr::write_csv(breaks, break_file)

  paths <- c(
    export_descriptive_tables(panel, config),
    export_descriptive_figures(panel, break_series, breaks, config),
    normalizePath(break_file, winslash = "/", mustWork = TRUE),
    write_session_snapshot(config, "descriptive")
  )
  manifest <- write_reporting_manifest(
    paths,
    config,
    "manifest_descriptive_outputs.csv"
  )
  c(paths, manifest)
}

export_forecast_results <- function(error_rows, config, label = "pilot") {
  ensure_project_directories(config)
  rds_path <- file.path(
    config$project$output_dir,
    paste0("forecast_error_rows_", label, ".rds")
  )
  accuracy_path <- file.path(
    config$project$output_dir,
    paste0("forecast_accuracy_", label, ".csv")
  )
  saveRDS(error_rows, rds_path)
  readr::write_csv(summarise_forecast_accuracy(error_rows), accuracy_path)

  paths <- c(
    normalizePath(rds_path, winslash = "/", mustWork = TRUE),
    normalizePath(accuracy_path, winslash = "/", mustWork = TRUE),
    export_forecast_tables(error_rows, config),
    export_forecast_figures(error_rows, config),
    write_session_snapshot(config, paste0("forecast_", label))
  )
  manifest <- write_reporting_manifest(
    paths,
    config,
    paste0("manifest_forecast_outputs_", label, ".csv")
  )
  c(paths, manifest)
}

export_gain_map <- function(
    municipality_geometry,
    error_rows,
    config,
    horizon = 1L) {
  plot <- plot_forecast_gain_map(
    municipality_geometry = municipality_geometry,
    error_rows = error_rows,
    benchmark_model = config$reporting$benchmark_model,
    comparison_model = config$reporting$comparison_model,
    horizon = horizon
  )
  save_article_figure(
    plot,
    paste0("figure_forecast_gain_map_h", as.integer(horizon)),
    config,
    width = 7.2,
    height = 6.6
  )
}

render_article_pdf <- function(input = "article/manuscript.qmd") {
  if (!quarto::quarto_available()) {
    stop(
      "Quarto is not available. Install Quarto or use the version bundled with RStudio.",
      call. = FALSE
    )
  }
  quarto::quarto_render(input = input, output_format = "pdf", quiet = FALSE)
  expected_name <- paste0(tools::file_path_sans_ext(basename(input)), ".pdf")
  candidates <- c(
    file.path("output/article", expected_name),
    file.path("output/article", dirname(input), expected_name)
  )
  candidates <- candidates[file.exists(candidates)]
  if (length(candidates) == 0L) {
    candidates <- list.files(
      "output/article",
      pattern = paste0("^", expected_name, "$"),
      recursive = TRUE,
      full.names = TRUE
    )
  }
  if (length(candidates) != 1L) {
    stop("Could not uniquely locate the rendered article PDF.", call. = FALSE)
  }
  output <- candidates[[1]]
  normalizePath(output, winslash = "/", mustWork = TRUE)
}
