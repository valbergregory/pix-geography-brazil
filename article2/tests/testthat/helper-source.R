for (file in sort(list.files(
  normalizePath(file.path("..", "..", "R"), winslash = "/", mustWork = TRUE),
  pattern = "[.]R$", full.names = TRUE
))) {
  source(file, local = TRUE)
}

test_rules <- function() {
  list(stable_codes = c(5101837L, 5106240L, 5107925L), stable_key = "MT_STABLE", excluded_codes = 2401305L)
}

test_a2_config <- function() {
  list(
    adoption = list(numerator = "QT_PES_PagadorPF", denominator = "population_adult", ratio_flag_threshold = 1),
    feasibility = list(connectivity_groups = 2L, minimum_cell_municipalities = 2L)
  )
}
