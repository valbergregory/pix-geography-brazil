pix_query_parameters <- function(
    config,
    skip,
    page_size = NULL,
    database_parameter = NULL) {
  if (is.null(page_size)) {
    page_size <- config$bcb$page_size
  }
  if (is.null(database_parameter)) {
    database_parameter <- config$bcb$database_parameter
  }
  parameters <- list(
    paste0("'", database_parameter, "'"),
    "json",
    as.integer(page_size),
    as.integer(skip)
  )
  names(parameters) <- c("@DataBase", "$format", "$top", "$skip")
  parameters
}

fetch_pix_page <- function(
    config,
    skip = 0L,
    page_size = NULL,
    database_parameter = NULL) {
  request <- httr2::request(config$bcb$endpoint)
  request <- do.call(
    httr2::req_url_query,
    c(
      list(request),
      pix_query_parameters(config, skip, page_size, database_parameter)
    )
  )
  request <- request |>
    httr2::req_user_agent("pix-geography-research/1.0-r-only") |>
    httr2::req_timeout(as.numeric(config$bcb$timeout_seconds)) |>
    httr2::req_retry(
      max_tries = as.integer(config$bcb$max_tries),
      retry_on_failure = TRUE,
      is_transient = function(response) {
        httr2::resp_status(response) %in% c(
          408L, 425L, 429L, 500L, 502L, 503L, 504L
        )
      }
    )

  response <- httr2::req_perform(request)
  body <- httr2::resp_body_json(response, simplifyVector = TRUE)
  values <- body$value

  if (is.null(values) || length(values) == 0L) {
    return(tibble::tibble())
  }

  tibble::as_tibble(values)
}

pix_page_fingerprint <- function(page) {
  digest::digest(page, algo = "xxhash64")
}

assert_new_pix_page <- function(page, seen_fingerprints, skip) {
  fingerprint <- pix_page_fingerprint(page)
  if (fingerprint %in% seen_fingerprints) {
    stop(
      "BCB pagination did not advance: a page was repeated at $skip = ",
      as.integer(skip),
      ".",
      call. = FALSE
    )
  }
  fingerprint
}

probe_bcb_database <- function(
    config = read_project_config("config.yml"),
    candidates = NULL,
    page_size = 10L) {
  if (is.character(config) && length(config) == 1L) {
    config <- read_project_config(config)
  }
  if (is.null(candidates)) {
    candidates <- unique(c(
      as.character(config$bcb$database_parameter),
      as.character(unlist(config$bcb$database_probe_candidates))
    ))
  }

  probe_config <- config
  probe_config$bcb$max_tries <- min(2L, as.integer(config$bcb$max_tries))
  probe_config$bcb$timeout_seconds <- min(
    30,
    as.numeric(config$bcb$timeout_seconds)
  )

  purrr::map_dfr(as.character(candidates), function(candidate) {
    started <- Sys.time()
    result <- tryCatch(
      fetch_pix_page(
        probe_config,
        skip = 0L,
        page_size = as.integer(page_size),
        database_parameter = candidate
      ),
      error = identity
    )
    failed <- inherits(result, "error")
    observed_months <- if (
      failed || nrow(result) == 0L || !"AnoMes" %in% names(result)
    ) {
      NA_character_
    } else {
      paste(sort(unique(as.character(result$AnoMes))), collapse = ",")
    }
    tibble::tibble(
      database_parameter = candidate,
      status = if (failed) "error" else "available",
      rows_in_probe = if (failed) NA_integer_ else nrow(result),
      observed_AnoMes = observed_months,
      elapsed_seconds = as.numeric(difftime(Sys.time(), started, units = "secs")),
      detail = if (failed) conditionMessage(result) else "ok"
    )
  })
}

check_bcb_connection <- function(config_path = "config.yml") {
  config <- read_project_config(config_path)
  started <- Sys.time()
  result <- tryCatch(
    fetch_pix_page(config, skip = 0L, page_size = 1L),
    error = identity
  )

  if (inherits(result, "error")) {
    stop(
      paste0(
        "The BCB Pix request failed. This may be a transient service failure ",
        "or an invalid/outdated DataBase parameter. Run probe_bcb_database() ",
        "before changing packages or deleting targets. Original message: ",
        conditionMessage(result)
      ),
      call. = FALSE
    )
  }

  tibble::tibble(
    service = "BCB Pix OData",
    status = "available",
    rows_in_test = nrow(result),
    observed_AnoMes = if (
      nrow(result) > 0L && "AnoMes" %in% names(result)
    ) as.character(result$AnoMes[[1]]) else NA_character_,
    elapsed_seconds = as.numeric(difftime(Sys.time(), started, units = "secs"))
  )
}

fetch_all_pix <- function(config) {
  configured_page_size <- as.integer(config$bcb$page_size)
  max_pages <- as.integer(config$bcb$max_pages)

  candidate_page_sizes <- unique(c(
    configured_page_size,
    5000L,
    2000L,
    1000L
  ))
  candidate_page_sizes <- candidate_page_sizes[
    candidate_page_sizes <= configured_page_size
  ]
  first_page <- NULL
  last_error <- NULL
  page_size <- configured_page_size

  for (candidate in candidate_page_sizes) {
    message("Downloading BCB Pix page 1 (skip = 0; top = ", candidate, ")")
    attempt <- tryCatch(
      fetch_pix_page(config, skip = 0L, page_size = candidate),
      error = identity
    )
    if (!inherits(attempt, "error")) {
      first_page <- attempt
      page_size <- candidate
      break
    }
    last_error <- attempt
    warning(
      "BCB request failed with top = ", candidate,
      "; trying a smaller page. ", conditionMessage(attempt),
      call. = FALSE
    )
  }

  if (is.null(first_page)) {
    stop(
      "BCB Pix extraction failed at every page size. Last error: ",
      conditionMessage(last_error),
      call. = FALSE
    )
  }

  pages <- list(first_page)
  seen_pages <- pix_page_fingerprint(first_page)
  if (nrow(first_page) < page_size || max_pages <= 1L) {
    return(dplyr::bind_rows(pages))
  }

  page_number <- 2L
  skip <- page_size

  repeat {
    message(
      "Downloading BCB Pix page ", page_number,
      " (skip = ", skip, "; top = ", page_size, ")"
    )
    page <- fetch_pix_page(config, skip = skip, page_size = page_size)
    if (nrow(page) == 0L) {
      break
    }
    fingerprint <- assert_new_pix_page(page, seen_pages, skip)
    seen_pages <- c(seen_pages, fingerprint)
    pages[[page_number]] <- page

    if (nrow(page) < page_size) {
      break
    }
    if (page_number >= max_pages) {
      stop(
        "BCB extraction reached the configured safety limit of ",
        max_pages,
        " full pages. Increase bcb$max_pages only after checking pagination.",
        call. = FALSE
      )
    }

    page_number <- page_number + 1L
    skip <- skip + page_size
  }

  dplyr::bind_rows(pages)
}

write_json_metadata <- function(metadata, path) {
  jsonlite::write_json(
    metadata,
    path = path,
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null"
  )
  path
}

frozen_snapshot_files <- function(config) {
  parquet_path <- config$bcb$frozen_snapshot
  if (is.null(parquet_path) || !nzchar(as.character(parquet_path))) {
    return(NULL)
  }
  parquet_path <- as.character(parquet_path)
  if (!grepl("\\.parquet$", parquet_path)) {
    stop("bcb$frozen_snapshot must point to a .parquet file.", call. = FALSE)
  }
  if (!file.exists(parquet_path)) {
    stop("Frozen snapshot not found: ", parquet_path, call. = FALSE)
  }
  metadata_path <- sub("\\.parquet$", ".json", parquet_path)
  if (!file.exists(metadata_path)) {
    stop(
      "Frozen snapshot has no metadata file next to it: ", metadata_path,
      call. = FALSE
    )
  }

  metadata <- jsonlite::read_json(metadata_path)
  observed_sha <- digest::digest(parquet_path, algo = "sha256", file = TRUE)
  if (is.null(metadata$sha256_parquet)) {
    warning(
      "Frozen snapshot metadata has no sha256_parquet; integrity not verified. ",
      "Observed SHA-256: ", observed_sha,
      call. = FALSE
    )
  } else if (!identical(as.character(metadata$sha256_parquet), observed_sha)) {
    stop(
      "Frozen snapshot SHA-256 does not match its metadata: ", parquet_path,
      call. = FALSE
    )
  }

  normalizePath(c(parquet_path, metadata_path), winslash = "/", mustWork = TRUE)
}

extract_pix_snapshot <- function(config) {
  frozen <- frozen_snapshot_files(config)
  if (!is.null(frozen)) {
    message("Using frozen BCB snapshot (no download): ", frozen[[1]])
    return(frozen)
  }

  ensure_project_directories(config)
  extraction_time <- Sys.time()
  snapshot_id <- timestamp_id(extraction_time)

  parquet_path <- file.path(
    config$project$raw_dir,
    paste0("pix_municipality_", snapshot_id, ".parquet")
  )
  metadata_path <- file.path(
    config$project$raw_dir,
    paste0("pix_municipality_", snapshot_id, ".json")
  )

  data <- fetch_all_pix(config)
  if (nrow(data) == 0L) {
    stop("The BCB endpoint returned no Pix municipality records.", call. = FALSE)
  }

  arrow::write_parquet(data, parquet_path, compression = "zstd")

  metadata <- list(
    source = config$bcb$endpoint,
    extraction_utc = format(extraction_time, tz = "UTC", usetz = TRUE),
    database_parameter = config$bcb$database_parameter,
    rows = nrow(data),
    columns = ncol(data),
    minimum_AnoMes = min(data$AnoMes, na.rm = TRUE),
    maximum_AnoMes = max(data$AnoMes, na.rm = TRUE),
    distinct_AnoMes = dplyr::n_distinct(data$AnoMes),
    sha256_parquet = digest::digest(
      parquet_path,
      algo = "sha256",
      file = TRUE
    ),
    r_version = as.character(getRversion())
  )
  write_json_metadata(metadata, metadata_path)

  normalizePath(c(parquet_path, metadata_path), winslash = "/", mustWork = TRUE)
}

read_pix_snapshot <- function(snapshot_files) {
  parquet_path <- snapshot_files[grepl("\\.parquet$", snapshot_files)]
  if (length(parquet_path) != 1L) {
    stop("Expected exactly one Parquet snapshot file.", call. = FALSE)
  }
  arrow::read_parquet(parquet_path) |>
    tibble::as_tibble()
}
