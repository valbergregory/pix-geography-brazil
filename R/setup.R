required_packages <- c(
  "arrow",
  "changepoint",
  "DBI",
  "digest",
  "dplyr",
  "duckdb",
  "fable",
  "fabletools",
  "feasts",
  "fixest",
  "geobr",
  "ggplot2",
  "glmnet",
  "httr2",
  "jsonlite",
  "knitr",
  "lubridate",
  "Matrix",
  "modelsummary",
  "patchwork",
  "purrr",
  "quarto",
  "ragg",
  "readr",
  "renv",
  "rlang",
  "sandwich",
  "scales",
  "sf",
  "slider",
  "strucchange",
  "targets",
  "testthat",
  "tibble",
  "tinytable",
  "tinytex",
  "tidyr",
  "tidyselect",
  "tsibble",
  "viridisLite",
  "xgboost",
  "yaml"
)

missing_required_packages <- function() {
  required_packages[
    !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
  ]
}

install_required_packages <- function() {
  missing <- missing_required_packages()

  if (length(missing) == 0L) {
    message("All required R packages are already installed.")
    return(invisible(required_packages))
  }

  message("Installing: ", paste(missing, collapse = ", "))
  install.packages(
    missing,
    dependencies = c("Depends", "Imports", "LinkingTo")
  )
  invisible(missing)
}

check_required_packages <- function() {
  missing <- missing_required_packages()

  if (length(missing) > 0L) {
    stop(
      "Missing R packages: ", paste(missing, collapse = ", "),
      ". Run source('R/setup.R'); install_required_packages().",
      call. = FALSE
    )
  }

  invisible(TRUE)
}

check_latex_environment <- function() {
  if (!quarto::quarto_available()) {
    stop("Quarto is unavailable. Install Quarto or update RStudio.", call. = FALSE)
  }
  latex_available <- tinytex::is_tinytex() || nzchar(Sys.which("pdflatex"))
  if (!latex_available) {
    stop(
      "No LaTeX distribution was found. Run tinytex::install_tinytex().",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

install_latex_dependencies <- function() {
  if (!tinytex::is_tinytex() && !nzchar(Sys.which("pdflatex"))) {
    stop(
      "Install a LaTeX distribution first. Recommended: tinytex::install_tinytex().",
      call. = FALSE
    )
  }
  if (tinytex::is_tinytex()) {
    tinytex::tlmgr_install(c(
      "booktabs",
      "tabularray",
      "siunitx",
      "ulem",
      "rotating",
      "ninecolors"
    ))
  }
  invisible(TRUE)
}
