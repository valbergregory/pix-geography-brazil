source("R/setup.R")
options(error = NULL)

required_files <- c(
  "pix-geography.Rproj",
  "config.yml",
  "_targets.R",
  "R/setup.R",
  "R/global_models.R",
  "prepare_pilot.R",
  "run_pilot.R",
  "check_pilot.R",
  "docs/PILOT_APPROVAL_CRITERIA.md",
  "run_national.R",
  "run_national_background.R",
  "render_article.R",
  "diagnose_bcb.R",
  "RSTUDIO_STEP_BY_STEP.md",
  "VERSION_2_CHANGELOG.md"
)

diagnostics <- list()
add_diagnostic <- function(component, ok, detail) {
  diagnostics[[length(diagnostics) + 1L]] <<- tibble::tibble(
    component = component,
    status = if (isTRUE(ok)) "OK" else "ATTENTION",
    detail = as.character(detail)
  )
}

add_diagnostic(
  "Project root",
  all(file.exists(required_files)),
  if (all(file.exists(required_files))) {
    normalizePath(getwd(), winslash = "/")
  } else {
    paste("Missing:", paste(required_files[!file.exists(required_files)], collapse = ", "))
  }
)

version_ok <- getRversion() >= "4.4.0"
add_diagnostic("R version", version_ok, as.character(getRversion()))

source("R/setup.R")
missing <- missing_required_packages()
add_diagnostic(
  "R packages",
  length(missing) == 0L,
  if (length(missing) == 0L) "All required packages are installed" else {
    paste("Missing:", paste(missing, collapse = ", "))
  }
)

if (requireNamespace("renv", quietly = TRUE)) {
  renv_text <- paste(utils::capture.output(renv::status()), collapse = " ")
  renv_ok <- grepl("No issues found", renv_text, fixed = TRUE)
  add_diagnostic("renv", renv_ok, renv_text)
} else {
  add_diagnostic("renv", FALSE, "Package renv is not installed")
}

if (length(missing) == 0L) {
  manifest_result <- tryCatch(
    targets::tar_manifest(
      fields = tidyselect::any_of(c("name", "command"))
    ),
    error = identity
  )
  add_diagnostic(
    "targets manifest",
    !inherits(manifest_result, "error"),
    if (inherits(manifest_result, "error")) {
      conditionMessage(manifest_result)
    } else {
      paste(nrow(manifest_result), "targets parsed successfully")
    }
  )

  test_results <- testthat::test_dir(
    "tests/testthat",
    reporter = "summary",
    stop_on_failure = FALSE
  )
  test_table <- as.data.frame(test_results)
  failed <- if ("failed" %in% names(test_table)) {
    sum(as.numeric(test_table$failed), na.rm = TRUE)
  } else {
    0
  }
  errors <- if ("error" %in% names(test_table)) {
    sum(test_table$error %in% TRUE, na.rm = TRUE)
  } else {
    0
  }
  add_diagnostic(
    "Unit tests",
    failed + errors == 0L,
    paste("Failures:", failed, "| Errors:", errors)
  )

  targets::tar_source("R")
  bcb_result <- tryCatch(check_bcb_connection(), error = identity)
  add_diagnostic(
    "BCB Pix service",
    !inherits(bcb_result, "error"),
    if (inherits(bcb_result, "error")) {
      conditionMessage(bcb_result)
    } else {
      paste("Available; test rows:", bcb_result$rows_in_test[[1]])
    }
  )

  latex_result <- tryCatch(check_latex_environment(), error = identity)
  add_diagnostic(
    "Quarto and LaTeX",
    !inherits(latex_result, "error"),
    if (inherits(latex_result, "error")) {
      conditionMessage(latex_result)
    } else {
      "Available"
    }
  )
}

diagnostic_table <- dplyr::bind_rows(diagnostics)
print(diagnostic_table, n = Inf)
dir.create("output", recursive = TRUE, showWarnings = FALSE)
readr::write_csv(diagnostic_table, "output/project_diagnostics.csv")

if (any(diagnostic_table$status == "ATTENTION")) {
  message(
    "Diagnostics finished with attention items. External BCB or LaTeX availability ",
    "does not invalidate the R code or unit tests."
  )
} else {
  message("All project diagnostics passed.")
}
