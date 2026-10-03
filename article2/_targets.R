library(targets)

tar_source("R")

tar_option_set(
  packages = c("arrow", "dplyr", "readr", "tibble", "tidyr", "yaml"),
  format = "rds"
)

list(
  tar_target(a2_config_file, "config.yml", format = "file"),
  tar_target(a2_config, read_a2_config(a2_config_file)),
  tar_target(main_config_file, a2_config$shared$main_config, format = "file"),
  tar_target(geography_rules, read_geography_rules(main_config_file)),

  tar_target(panel_file, a2_config$shared$panel_parquet, format = "file"),
  tar_target(panel, arrow::read_parquet(panel_file)),

  tar_target(population_file, a2_input_path(a2_config, "population"), format = "file"),
  tar_target(banking_file, a2_input_path(a2_config, "banking"), format = "file"),
  tar_target(connectivity_file, a2_input_path(a2_config, "connectivity"), format = "file"),
  tar_target(population, read_a2_input(population_file, "population")),
  tar_target(banking, read_a2_input(banking_file, "banking")),
  tar_target(connectivity, read_a2_input(connectivity_file, "connectivity")),

  tar_target(
    adoption,
    build_adoption_outcome(panel, population, geography_rules, a2_config)
  ),
  tar_target(adoption_audit, audit_adoption(adoption, a2_config)),

  tar_target(
    exposure,
    build_exposure_table(population, banking, connectivity, geography_rules)
  ),
  tar_target(feasibility, check_scarcity_connectivity(exposure, a2_config)),

  tar_target(
    a2_outputs,
    write_a2_tables(
      list(
        adoption_audit_summary = adoption_audit$summary,
        adoption_audit_by_month = adoption_audit$by_month,
        exposure = exposure,
        feasibility_summary = feasibility$summary,
        feasibility_cells = feasibility$cells
      ),
      a2_config
    ),
    format = "file"
  )
)
