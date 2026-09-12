legacy_paths <- c(
  "python",
  "R/python_bridge.R",
  "article/python_prediction_schema.md"
)
legacy_processed <- list.files(
  "data/processed",
  pattern = "^python_",
  full.names = TRUE
)
legacy_paths <- c(legacy_paths, legacy_processed)
legacy_paths <- legacy_paths[file.exists(legacy_paths)]

if (length(legacy_paths) == 0L) {
  message("No legacy Python files were found. The project is already R-only.")
} else {
  archive_directory <- file.path(
    "legacy_backup",
    paste0("python_", format(Sys.time(), "%Y%m%d_%H%M%S"))
  )
  dir.create(archive_directory, recursive = TRUE, showWarnings = FALSE)

  for (path in legacy_paths) {
    destination <- file.path(archive_directory, basename(path))
    moved <- file.rename(path, destination)
    if (!moved) {
      stop("Could not archive legacy path: ", path, call. = FALSE)
    }
  }
  message("Legacy Python files archived in: ", archive_directory)
}
