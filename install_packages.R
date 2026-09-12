options(repos = c(CRAN = "https://cloud.r-project.org"))

if (!requireNamespace("renv", quietly = TRUE)) {
  install.packages("renv")
}

project_path <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
if (file.exists("renv.lock")) {
  renv::restore(project = project_path, prompt = FALSE)
} else {
  message("No renv.lock was found. Initializing a new project library.")
  renv::init(project = project_path, bare = TRUE, restart = FALSE)
}

source("R/setup.R")
install_required_packages()
check_required_packages()
renv::snapshot(prompt = FALSE)
renv::status()

message("R package installation and renv snapshot completed.")
