prepare_break_series <- function(data, value = "payer_count") {
  if (!all(c("month", value) %in% names(data))) {
    stop("Break series must contain month and ", value, ".", call. = FALSE)
  }

  data |>
    dplyr::transmute(
      month = .data$month,
      value = as.numeric(.data[[value]])
    ) |>
    dplyr::filter(is.finite(.data$value)) |>
    dplyr::arrange(.data$month)
}

detect_bai_perron <- function(data, value = "payer_count", min_segment = 12L) {
  work <- prepare_break_series(data, value = value) |>
    dplyr::mutate(
      transformed = log1p(.data$value),
      trend = dplyr::row_number()
    )

  if (nrow(work) < 2L * as.integer(min_segment)) {
    stop("Series is too short for the requested Bai-Perron segment length.", call. = FALSE)
  }

  full_model <- strucchange::breakpoints(
    transformed ~ trend,
    data = work,
    h = as.integer(min_segment)
  )
  selected <- strucchange::breakpoints(full_model)
  locations <- selected$breakpoints
  locations <- locations[!is.na(locations)]

  if (length(locations) == 0L) {
    return(tibble::tibble(
      method = character(),
      break_index = integer(),
      break_month = work$month[integer()]
    ))
  }

  tibble::tibble(
    method = "Bai-Perron",
    break_index = as.integer(locations),
    break_month = work$month[locations]
  )
}

detect_pelt <- function(data, value = "payer_count", min_segment = 6L) {
  work <- prepare_break_series(data, value = value) |>
    dplyr::mutate(growth = c(NA_real_, diff(log1p(.data$value)))) |>
    dplyr::filter(is.finite(.data$growth))

  if (nrow(work) < 2L * as.integer(min_segment)) {
    stop("Series is too short for the requested PELT segment length.", call. = FALSE)
  }

  fit <- changepoint::cpt.meanvar(
    work$growth,
    method = "PELT",
    penalty = "MBIC",
    minseglen = as.integer(min_segment),
    class = TRUE
  )
  locations <- changepoint::cpts(fit)
  locations <- locations[locations > 0L & locations < nrow(work)]

  if (length(locations) == 0L) {
    return(tibble::tibble(
      method = character(),
      break_index = integer(),
      break_month = work$month[integer()]
    ))
  }

  tibble::tibble(
    method = "PELT",
    break_index = as.integer(locations),
    break_month = work$month[pmin(locations + 1L, nrow(work))]
  )
}

aggregate_break_series <- function(panel, level = c("national", "region", "state")) {
  level <- match.arg(level)
  grouping <- switch(
    level,
    national = character(),
    region = "region_code",
    state = "state_code"
  )

  panel |>
    dplyr::group_by(dplyr::across(dplyr::all_of(c(grouping, "month")))) |>
    dplyr::summarise(payer_count = sum(.data$payer_count), .groups = "drop") |>
    dplyr::arrange(dplyr::across(dplyr::all_of(c(grouping, "month"))))
}
