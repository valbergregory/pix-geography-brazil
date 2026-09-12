source("R/setup.R")
check_required_packages()

Sys.setenv(PIX_FULL_RUN = "false")
targets::tar_make(names = tidyselect::any_of(c(
  "forecast_output_files",
  "global_model_artifact_files",
  "reliability_output_files",
  "forecast_map_files"
)))
output_files <- c(
  targets::tar_read(forecast_output_files),
  targets::tar_read(global_model_artifact_files),
  targets::tar_read(reliability_output_files),
  targets::tar_read(forecast_map_files)
)
message("Pilot completed. Generated files:")
print(output_files)
