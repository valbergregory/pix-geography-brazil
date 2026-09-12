source("R/setup.R")
check_required_packages()
targets::tar_source("R")

config <- read_project_config("config.yml")
probe <- probe_bcb_database(config)
print(probe, n = Inf)

dir.create(config$project$output_dir, recursive = TRUE, showWarnings = FALSE)
path <- file.path(config$project$output_dir, "bcb_database_probe.csv")
readr::write_csv(probe, path)
message("BCB probe saved to: ", normalizePath(path, winslash = "/"))

if (!any(probe$status == "available")) {
  stop(
    paste(
      "No configured DataBase candidate was available.",
      "Do not change packages or delete the targets cache; try again later."
    ),
    call. = FALSE
  )
}
