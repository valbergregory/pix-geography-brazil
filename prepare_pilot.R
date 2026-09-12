source("R/setup.R")
check_required_packages()

Sys.setenv(PIX_FULL_RUN = "false")
targets::tar_make(names = tidyselect::any_of(c(
  "data_quality_outputs",
  "descriptive_outputs",
  "duckdb_file",
  "rolling_origins"
)))

message("Pilot preparation completed. The statistical models have not run yet.")
print(targets::tar_outdated())
