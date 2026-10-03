write_a2_tables <- function(tables, config) {
  dir.create(config$paths$output_dir, recursive = TRUE, showWarnings = FALSE)
  paths <- vapply(names(tables), function(name) {
    path <- file.path(config$paths$output_dir, paste0(name, ".csv"))
    readr::write_csv(tables[[name]], path)
    path
  }, character(1))
  unname(paths)
}
