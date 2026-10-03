# Adoption outcome: people who paid via Pix in the month (QT_PES_PagadorPF) per adult.
# The denominator is a fixed reference-year population; missing denominators stay NA.
build_adoption_outcome <- function(panel, population, rules, config) {
  numerator <- config$adoption$numerator
  denominator <- config$adoption$denominator
  if (!numerator %in% names(panel)) {
    stop("Panel is missing the adoption numerator: ", numerator, call. = FALSE)
  }
  stable_population <- aggregate_to_stable(
    population, rules,
    sum_fields = c("population_total", "population_adult")
  )
  panel |>
    dplyr::select("stable_municipality_id", "month", dplyr::all_of(numerator)) |>
    dplyr::rename(payers_pf = dplyr::all_of(numerator)) |>
    dplyr::left_join(
      stable_population |>
        dplyr::select("stable_municipality_id", denominator_value = dplyr::all_of(denominator)),
      by = "stable_municipality_id"
    ) |>
    dplyr::mutate(
      adoption_rate = dplyr::if_else(
        is.na(.data$denominator_value) | .data$denominator_value <= 0,
        NA_real_,
        .data$payers_pf / .data$denominator_value
      )
    )
}

# Audit of the adoption ratio. A ratio above the threshold means more payers than
# adults in the municipality: possible double counting of people across
# municipalities, or a denominator problem. Reported, never silently capped.
audit_adoption <- function(adoption, config) {
  threshold <- as.numeric(config$adoption$ratio_flag_threshold)
  observed <- adoption[!is.na(adoption$adoption_rate), ]
  summary <- tibble::tibble(
    n_observations = nrow(adoption),
    n_municipalities = dplyr::n_distinct(adoption$stable_municipality_id),
    n_missing_denominator = sum(is.na(adoption$adoption_rate)),
    municipalities_missing_denominator = dplyr::n_distinct(
      adoption$stable_municipality_id[is.na(adoption$adoption_rate)]
    ),
    n_ratio_above_threshold = sum(observed$adoption_rate > threshold),
    municipalities_above_threshold = dplyr::n_distinct(
      observed$stable_municipality_id[observed$adoption_rate > threshold]
    ),
    max_ratio = if (nrow(observed)) max(observed$adoption_rate) else NA_real_,
    p99_ratio = if (nrow(observed)) unname(stats::quantile(observed$adoption_rate, 0.99)) else NA_real_
  )
  by_month <- observed |>
    dplyr::group_by(.data$month) |>
    dplyr::summarise(
      municipalities = dplyr::n(),
      national_adoption = sum(.data$payers_pf) / sum(.data$payers_pf / .data$adoption_rate),
      share_above_threshold = mean(.data$adoption_rate > threshold),
      .groups = "drop"
    )
  list(summary = summary, by_month = by_month)
}
