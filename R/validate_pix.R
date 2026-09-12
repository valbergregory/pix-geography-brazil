required_pix_fields <- c(
  "AnoMes",
  "Municipio_Ibge",
  "Municipio",
  "Estado_Ibge",
  "Estado",
  "Sigla_Regiao",
  "Regiao",
  "VL_PagadorPF",
  "QT_PagadorPF",
  "VL_PagadorPJ",
  "QT_PagadorPJ",
  "VL_RecebedorPF",
  "QT_RecebedorPF",
  "VL_RecebedorPJ",
  "QT_RecebedorPJ",
  "QT_PES_PagadorPF",
  "QT_PES_PagadorPJ",
  "QT_PES_RecebedorPF",
  "QT_PES_RecebedorPJ"
)

nonnegative_pix_fields <- c(
  "VL_PagadorPF",
  "QT_PagadorPF",
  "VL_PagadorPJ",
  "QT_PagadorPJ",
  "VL_RecebedorPF",
  "QT_RecebedorPF",
  "VL_RecebedorPJ",
  "QT_RecebedorPJ",
  "QT_PES_PagadorPF",
  "QT_PES_PagadorPJ",
  "QT_PES_RecebedorPF",
  "QT_PES_RecebedorPJ"
)

validate_pix_schema <- function(data) {
  missing_fields <- setdiff(required_pix_fields, names(data))
  if (length(missing_fields) > 0L) {
    stop(
      "BCB schema changed. Missing fields: ",
      paste(missing_fields, collapse = ", "),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

validate_pix_months <- function(data, minimum_months = 36L) {
  months <- sort(unique(as.integer(data$AnoMes)))
  months <- months[!is.na(months)]
  if (length(months) < minimum_months) {
    stop(
      "Only ", length(months), " months were found; expected at least ",
      minimum_months, ".",
      call. = FALSE
    )
  }

  calendar_month <- months %% 100L
  if (any(calendar_month < 1L | calendar_month > 12L)) {
    stop("AnoMes contains an invalid calendar month.", call. = FALSE)
  }

  parsed <- as.Date(sprintf(
    "%04d-%02d-01",
    months %/% 100L,
    months %% 100L
  ))
  expected <- seq(min(parsed), max(parsed), by = "month")
  missing_months <- expected[!expected %in% parsed]

  if (length(missing_months) > 0L) {
    stop(
      "Missing reference months: ",
      paste(format(missing_months, "%Y-%m"), collapse = ", "),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

validate_pix_keys <- function(data) {
  key_check <- data |>
    dplyr::mutate(
      municipality_audit_key = dplyr::if_else(
        is.na(.data$Municipio_Ibge),
        "N/D",
        as.character(.data$Municipio_Ibge)
      )
    ) |>
    dplyr::count(.data$AnoMes, .data$municipality_audit_key, name = "n") |>
    dplyr::filter(.data$n != 1L)

  if (nrow(key_check) > 0L) {
    stop("Duplicate month-municipality keys detected in raw BCB data.", call. = FALSE)
  }
  invisible(TRUE)
}

validate_nonnegative_fields <- function(data) {
  violations <- vapply(
    nonnegative_pix_fields,
    function(field) any(data[[field]] < 0, na.rm = TRUE),
    logical(1)
  )

  if (any(violations)) {
    stop(
      "Negative raw Pix values detected in: ",
      paste(names(violations)[violations], collapse = ", "),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

validate_nonmissing_measures <- function(data) {
  missing_values <- vapply(
    nonnegative_pix_fields,
    function(field) any(is.na(data[[field]])),
    logical(1)
  )

  if (any(missing_values)) {
    stop(
      "Missing raw Pix measures detected in: ",
      paste(names(missing_values)[missing_values], collapse = ", "),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

geographic_coverage_by_month <- function(data) {
  identified <- data |>
    dplyr::filter(!is.na(.data$Municipio_Ibge)) |>
    dplyr::count(.data$AnoMes, name = "identified_units")
  data |>
    dplyr::distinct(.data$AnoMes) |>
    dplyr::left_join(identified, by = "AnoMes") |>
    dplyr::mutate(identified_units = tidyr::replace_na(.data$identified_units, 0L)) |>
    dplyr::arrange(.data$AnoMes)
}

validate_geographic_coverage <- function(
    data,
    minimum_identified_units = 5568L,
    strict = TRUE) {
  coverage <- geographic_coverage_by_month(data)
  minimum_units <- if (nrow(coverage) == 0L) {
    NA_integer_
  } else {
    min(coverage$identified_units)
  }

  if (!is.finite(minimum_units) || minimum_units < minimum_identified_units) {
    message_text <- paste0(
      "Unexpected municipal coverage. Minimum identified units in a month: ",
      minimum_units,
      "; required: ",
      minimum_identified_units,
      "."
    )
    if (isTRUE(strict)) {
      stop(message_text, call. = FALSE)
    }
    warning(message_text, call. = FALSE)
  }
  invisible(coverage)
}

validate_pix_raw <- function(
    data,
    minimum_months = 36L,
    minimum_identified_units = 5568L,
    strict_geographic_coverage = TRUE) {
  validate_pix_schema(data)
  validate_pix_months(data, minimum_months = minimum_months)
  validate_pix_keys(data)
  validate_nonmissing_measures(data)
  validate_nonnegative_fields(data)
  validate_geographic_coverage(
    data,
    minimum_identified_units = minimum_identified_units,
    strict = strict_geographic_coverage
  )

  tibble::tibble(
    test = c(
      "schema",
      "monthly continuity",
      "unique raw keys",
      "complete raw measures",
      "nonnegative raw measures",
      "municipal coverage"
    ),
    status = "passed"
  )
}
