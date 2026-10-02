ano_mes_to_date <- function(x) {
  year <- as.integer(x) %/% 100L
  month <- as.integer(x) %% 100L
  as.Date(sprintf("%04d-%02d-01", year, month))
}

standardize_pix_columns <- function(data) {
  numeric_fields <- intersect(nonnegative_pix_fields, names(data))

  data |>
    dplyr::mutate(
      dplyr::across(dplyr::all_of(numeric_fields), as.numeric),
      month = ano_mes_to_date(.data$AnoMes),
      municipality_code = as.integer(.data$Municipio_Ibge),
      municipality_name = enc2utf8(as.character(.data$Municipio)),
      state_code = dplyr::if_else(
        is.na(.data$Estado_Ibge),
        NA_character_,
        sprintf("%02d", as.integer(.data$Estado_Ibge))
      ),
      state_name = enc2utf8(as.character(.data$Estado)),
      region_code = as.character(.data$Sigla_Regiao),
      region_name = enc2utf8(as.character(.data$Regiao))
    )
}

build_additive_targets <- function(data) {
  data |>
    dplyr::mutate(
      payer_count = .data$QT_PagadorPF + .data$QT_PagadorPJ,
      payer_value_nominal = .data$VL_PagadorPF + .data$VL_PagadorPJ,
      active_payers = .data$QT_PES_PagadorPF + .data$QT_PES_PagadorPJ
    )
}

apply_stable_geography <- function(data, config) {
  stable_codes <- as.integer(unlist(config$geography$stable_mt_codes))
  stable_key <- config$geography$stable_mt_key
  stable_name <- config$geography$stable_mt_name

  prepared <- data |>
    dplyr::mutate(
      stable_municipality_id = dplyr::case_when(
        is.na(.data$municipality_code) ~ config$geography$unidentified_key,
        .data$municipality_code %in% stable_codes ~ stable_key,
        TRUE ~ as.character(.data$municipality_code)
      ),
      stable_municipality_name = dplyr::case_when(
        is.na(.data$municipality_code) ~ "Unidentified geography",
        .data$municipality_code %in% stable_codes ~ stable_name,
        TRUE ~ .data$municipality_name
      )
    )

  sum_fields <- c(
    "payer_count",
    "payer_value_nominal",
    "active_payers",
    nonnegative_pix_fields
  )
  sum_fields <- unique(intersect(sum_fields, names(prepared)))

  prepared |>
    dplyr::group_by(
      .data$month,
      .data$stable_municipality_id,
      .data$stable_municipality_name,
      .data$state_code,
      .data$state_name,
      .data$region_code,
      .data$region_name
    ) |>
    dplyr::summarise(
      dplyr::across(dplyr::all_of(sum_fields), ~ sum(.x, na.rm = TRUE)),
      .groups = "drop"
    )
}

exclude_municipalities <- function(data, config) {
  excluded <- as.integer(unlist(config$geography$excluded_municipality_codes))
  if (length(excluded) == 0L) {
    return(data)
  }
  if (anyNA(excluded)) {
    stop(
      "geography$excluded_municipality_codes must contain IBGE codes only.",
      call. = FALSE
    )
  }
  data |>
    dplyr::filter(
      is.na(.data$municipality_code) |
        !.data$municipality_code %in% excluded
    )
}

build_analysis_panel <- function(raw_data, config) {
  raw_data |>
    standardize_pix_columns() |>
    exclude_municipalities(config) |>
    build_additive_targets() |>
    apply_stable_geography(config) |>
    dplyr::arrange(.data$stable_municipality_id, .data$month)
}

analysis_panel_calendar_gaps <- function(data, exclude_ids = character()) {
  data <- data |>
    dplyr::filter(!.data$stable_municipality_id %in% exclude_ids)
  if (nrow(data) == 0L) {
    return(tibble::tibble(
      stable_municipality_id = character(),
      month = as.Date(character())
    ))
  }
  expected_months <- seq(min(data$month), max(data$month), by = "month")
  expected <- tidyr::expand_grid(
    stable_municipality_id = unique(as.character(data$stable_municipality_id)),
    month = expected_months
  )
  observed <- data |>
    dplyr::transmute(
      stable_municipality_id = as.character(.data$stable_municipality_id),
      month = as.Date(.data$month)
    ) |>
    dplyr::distinct()
  dplyr::anti_join(
    expected,
    observed,
    by = c("stable_municipality_id", "month")
  ) |>
    dplyr::arrange(.data$stable_municipality_id, .data$month)
}

validate_analysis_panel <- function(data, config) {
  duplicates <- data |>
    dplyr::count(.data$month, .data$stable_municipality_id, name = "n") |>
    dplyr::filter(.data$n != 1L)

  if (nrow(duplicates) > 0L) {
    stop("Stable-geography panel contains duplicate keys.", call. = FALSE)
  }

  if (isTRUE(config$quality$require_complete_panel)) {
    gaps <- analysis_panel_calendar_gaps(
      data,
      exclude_ids = config$geography$unidentified_key
    )
    if (nrow(gaps) > 0L) {
      example <- utils::head(gaps, 10L)
      example_text <- paste0(
        example$stable_municipality_id,
        "@",
        format(example$month, "%Y-%m"),
        collapse = ", "
      )
      stop(
        "Stable-geography panel has ",
        nrow(gaps),
        " missing municipality-month cells. Examples: ",
        example_text,
        ". Missing rows are not converted to zero automatically.",
        call. = FALSE
      )
    }
  }

  expected_fields <- c("payer_count", "payer_value_nominal", "active_payers")
  if (any(!vapply(data[expected_fields], is.numeric, logical(1)))) {
    stop("Derived targets must be numeric.", call. = FALSE)
  }

  stable_rows <- data |>
    dplyr::filter(.data$stable_municipality_id == config$geography$stable_mt_key)
  expected_months <- dplyr::n_distinct(data$month)

  if (nrow(stable_rows) != expected_months) {
    stop("The stable Mato Grosso territorial unit is not continuous.", call. = FALSE)
  }

  invisible(TRUE)
}

write_analysis_panel <- function(data, config) {
  ensure_project_directories(config)
  validate_analysis_panel(data, config)
  path <- file.path(config$project$processed_dir, "pix_stable_municipality.parquet")
  arrow::write_parquet(data, path, compression = "zstd")
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

select_analysis_scope <- function(data, config, full_run = is_full_run(config)) {
  identified <- data |>
    dplyr::filter(
      .data$stable_municipality_id != config$geography$unidentified_key
    )

  if (full_run) {
    return(identified)
  }

  pilot_states <- sprintf(
    "%02d",
    as.integer(unlist(config$analysis$pilot_state_codes))
  )
  identified |>
    dplyr::filter(.data$state_code %in% pilot_states)
}

build_hierarchical_tsibble <- function(data) {
  bottom <- data |>
    dplyr::select(
      month,
      region_code,
      state_code,
      stable_municipality_id,
      payer_count
    ) |>
    dplyr::mutate(month = tsibble::yearmonth(.data$month)) |>
    tsibble::as_tsibble(
      key = c(region_code, state_code, stable_municipality_id),
      index = month
    )

  bottom |>
    fabletools::aggregate_key(
      region_code / state_code / stable_municipality_id,
      payer_count = sum(payer_count)
    )
}
