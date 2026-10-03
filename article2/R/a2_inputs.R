# Input contract: required columns per file. See docs/ARTIGO2_DADOS.md.
a2_input_contract <- list(
  population = c("municipality_code", "population_total", "population_adult"),
  banking = c("municipality_code", "branches"),
  connectivity = c(
    "municipality_code", "broadband_accesses", "households", "coverage_4g_share"
  )
)

read_a2_input <- function(path, name) {
  if (!file.exists(path)) {
    stop("Input file for '", name, "' not found: ", path, call. = FALSE)
  }
  data <- readr::read_csv(path, show_col_types = FALSE, progress = FALSE)
  validate_a2_input(data, name)
  data
}

validate_a2_input <- function(data, name) {
  required <- a2_input_contract[[name]]
  if (is.null(required)) {
    stop("Unknown input: ", name, call. = FALSE)
  }
  missing <- setdiff(required, names(data))
  if (length(missing) > 0L) {
    stop(
      "Input '", name, "' is missing columns: ", paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  codes <- data$municipality_code
  if (anyNA(codes) || any(codes < 1000000 | codes > 9999999)) {
    stop("Input '", name, "': municipality_code must be 7-digit IBGE codes, no NA.", call. = FALSE)
  }
  if (anyDuplicated(codes)) {
    stop("Input '", name, "': duplicated municipality_code.", call. = FALSE)
  }
  numeric_fields <- setdiff(required, "municipality_code")
  for (field in numeric_fields) {
    if (!is.numeric(data[[field]])) {
      stop("Input '", name, "': column ", field, " must be numeric.", call. = FALSE)
    }
    if (any(data[[field]] < 0, na.rm = TRUE)) {
      stop("Input '", name, "': column ", field, " has negative values.", call. = FALSE)
    }
  }
  if (name == "connectivity" &&
      any(data$coverage_4g_share > 1, na.rm = TRUE)) {
    stop("Input 'connectivity': coverage_4g_share must be a share in [0, 1].", call. = FALSE)
  }
  invisible(data)
}

# Map 7-digit codes to the stable municipality id used by the Article F panel,
# dropping the municipalities that Article F excludes.
to_stable_municipality <- function(data, rules) {
  data |>
    dplyr::filter(!(.data$municipality_code %in% rules$excluded_codes)) |>
    dplyr::mutate(
      stable_municipality_id = dplyr::if_else(
        .data$municipality_code %in% rules$stable_codes,
        rules$stable_key,
        as.character(.data$municipality_code)
      )
    )
}

# Sum counts within the stable id. Shares are population-weighted by `weight`.
# Sums of all-NA groups stay NA (no silent zero fill).
aggregate_to_stable <- function(data, rules, sum_fields, share_fields = character(), weight = NULL) {
  mapped <- to_stable_municipality(data, rules)
  na_sum <- function(x) if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)
  na_wmean <- function(x, w) {
    keep <- !is.na(x) & !is.na(w)
    if (!any(keep) || sum(w[keep]) == 0) NA_real_ else stats::weighted.mean(x[keep], w[keep])
  }
  mapped |>
    dplyr::group_by(.data$stable_municipality_id) |>
    dplyr::summarise(
      dplyr::across(dplyr::all_of(sum_fields), na_sum),
      dplyr::across(
        dplyr::all_of(share_fields),
        ~ na_wmean(.x, .data[[weight]])
      ),
      .groups = "drop"
    )
}
