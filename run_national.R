source("R/setup.R")
check_required_packages()

confirmation <- tolower(Sys.getenv("PIX_CONFIRM_NATIONAL", unset = "no"))
if (!confirmation %in% c("yes", "true", "1")) {
  stop(
    paste(
      "National execution is intentionally protected.",
      "After the pilot passes, run",
      "Sys.setenv(PIX_CONFIRM_NATIONAL = 'yes') and source('run_national.R')."
    ),
    call. = FALSE
  )
}

Sys.setenv(PIX_FULL_RUN = "true")
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
message("National run completed. Generated files:")
print(output_files)
