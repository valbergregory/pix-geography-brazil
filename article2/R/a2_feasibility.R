build_exposure_table <- function(population, banking, connectivity, rules) {
  pop <- aggregate_to_stable(population, rules, c("population_total", "population_adult"))
  bank <- aggregate_to_stable(banking, rules, "branches")
  conn <- aggregate_to_stable(
    dplyr::left_join(connectivity, population[c("municipality_code", "population_total")],
                     by = "municipality_code"),
    rules,
    sum_fields = c("broadband_accesses", "households"),
    share_fields = "coverage_4g_share",
    weight = "population_total"
  )
  pop |>
    dplyr::left_join(bank, by = "stable_municipality_id") |>
    dplyr::left_join(conn, by = "stable_municipality_id") |>
    dplyr::mutate(
      branches_per_10k_adults = dplyr::if_else(
        is.na(.data$branches) | is.na(.data$population_adult) | .data$population_adult <= 0,
        NA_real_,
        10000 * .data$branches / .data$population_adult
      ),
      broadband_per_100_households = dplyr::if_else(
        is.na(.data$broadband_accesses) | is.na(.data$households) | .data$households <= 0,
        NA_real_,
        100 * .data$broadband_accesses / .data$households
      )
    )
}

# Banking scarcity: municipalities with no branch form their own class ("none");
# the rest are split at the median of branches per 10k adults.
classify_banking_scarcity <- function(branches_per_10k) {
  positive <- branches_per_10k[!is.na(branches_per_10k) & branches_per_10k > 0]
  cut_point <- stats::median(positive)
  factor(
    dplyr::case_when(
      is.na(branches_per_10k) ~ NA_character_,
      branches_per_10k == 0 ~ "none",
      branches_per_10k <= cut_point ~ "low",
      TRUE ~ "high"
    ),
    levels = c("none", "low", "high")
  )
}

classify_connectivity <- function(x, groups) {
  breaks <- unique(stats::quantile(x, probs = seq(0, 1, length.out = groups + 1L), na.rm = TRUE))
  if (length(breaks) < groups + 1L) {
    stop(
      "Connectivity quantile breaks are not unique; cannot form ", groups, " groups.",
      call. = FALSE
    )
  }
  cut(x, breaks = breaks, include.lowest = TRUE, labels = paste0("Q", seq_len(groups)))
}

# Pre-registered feasibility check (docs/PROGRAMA_DE_PESQUISA.md, §J): is there joint
# variation between banking scarcity and connectivity (poorly served by banks AND well
# connected)? Reports the cross-tab, rank correlation and whether every cell has
# enough municipalities.
check_scarcity_connectivity <- function(exposure, config) {
  groups <- as.integer(config$feasibility$connectivity_groups)
  minimum_cell <- as.integer(config$feasibility$minimum_cell_municipalities)
  complete <- exposure |>
    dplyr::filter(
      !is.na(.data$branches_per_10k_adults),
      !is.na(.data$broadband_per_100_households)
    ) |>
    dplyr::mutate(
      scarcity = classify_banking_scarcity(.data$branches_per_10k_adults),
      connectivity = classify_connectivity(.data$broadband_per_100_households, groups)
    )
  cells <- complete |>
    dplyr::count(.data$scarcity, .data$connectivity, name = "municipalities") |>
    tidyr::complete(
      scarcity = factor(c("none", "low", "high"), levels = c("none", "low", "high")),
      connectivity = factor(paste0("Q", seq_len(groups)), levels = paste0("Q", seq_len(groups))),
      fill = list(municipalities = 0L)
    ) |>
    dplyr::arrange(.data$scarcity, .data$connectivity)
  population_by_cell <- complete |>
    dplyr::group_by(.data$scarcity, .data$connectivity) |>
    dplyr::summarise(population_adult = sum(.data$population_adult, na.rm = TRUE), .groups = "drop")
  cells <- dplyr::left_join(cells, population_by_cell, by = c("scarcity", "connectivity")) |>
    dplyr::mutate(
      population_adult = dplyr::coalesce(.data$population_adult, 0),
      below_minimum = .data$municipalities < minimum_cell
    )
  summary <- tibble::tibble(
    n_municipalities_total = nrow(exposure),
    n_municipalities_complete = nrow(complete),
    spearman_scarcity_connectivity = suppressWarnings(stats::cor(
      complete$branches_per_10k_adults,
      complete$broadband_per_100_households,
      method = "spearman"
    )),
    n_cells = nrow(cells),
    n_cells_below_minimum = sum(cells$below_minimum),
    minimum_cell_municipalities = minimum_cell,
    viable = !any(cells$below_minimum)
  )
  list(summary = summary, cells = cells)
}
