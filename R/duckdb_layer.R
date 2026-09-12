sql_quote_path <- function(connection, path) {
  as.character(DBI::dbQuoteString(connection, normalizePath(path, winslash = "/")))
}

create_duckdb_catalog <- function(parquet_path, config) {
  ensure_project_directories(config)
  database_path <- file.path(config$project$processed_dir, "pix_geography.duckdb")
  connection <- DBI::dbConnect(duckdb::duckdb(), dbdir = database_path)
  on.exit(DBI::dbDisconnect(connection, shutdown = TRUE), add = TRUE)

  quoted_path <- sql_quote_path(connection, parquet_path)
  existing <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT table_type FROM information_schema.tables",
      "WHERE table_name = 'pix_stable_municipality'"
    )
  )
  if (nrow(existing) > 0L) {
    if (any(grepl("VIEW", existing$table_type, fixed = TRUE))) {
      DBI::dbExecute(connection, "DROP VIEW pix_stable_municipality")
    } else {
      DBI::dbExecute(connection, "DROP TABLE pix_stable_municipality")
    }
  }
  DBI::dbExecute(
    connection,
    paste0(
      "CREATE TABLE pix_stable_municipality AS ",
      "SELECT * FROM read_parquet(", quoted_path, ")"
    )
  )

  normalizePath(database_path, winslash = "/", mustWork = TRUE)
}
