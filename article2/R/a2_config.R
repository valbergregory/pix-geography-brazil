read_a2_config <- function(path = "config.yml") {
  if (!file.exists(path)) {
    stop("Article 2 configuration not found: ", path, call. = FALSE)
  }
  config <- yaml::read_yaml(path)
  required <- c("shared", "paths", "inputs", "adoption", "feasibility")
  missing <- setdiff(required, names(config))
  if (length(missing) > 0L) {
    stop("Missing Article 2 config sections: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  if (as.integer(config$feasibility$connectivity_groups) < 2L) {
    stop("feasibility$connectivity_groups must be at least 2.", call. = FALSE)
  }
  if (as.integer(config$feasibility$minimum_cell_municipalities) < 1L) {
    stop("feasibility$minimum_cell_municipalities must be positive.", call. = FALSE)
  }
  config
}

# Geography rules (stable Mato Grosso area, excluded municipalities) come from the
# Article F config so both projects use the same panel definition.
read_geography_rules <- function(main_config_path) {
  main <- yaml::read_yaml(main_config_path)
  geography <- main$geography
  list(
    stable_codes = as.integer(unlist(geography$stable_mt_codes)),
    stable_key = geography$stable_mt_key,
    excluded_codes = as.integer(unlist(geography$excluded_municipality_codes))
  )
}

a2_input_path <- function(config, name) {
  file.path(config$paths$inputs_dir, config$inputs[[name]])
}
