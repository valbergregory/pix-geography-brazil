test_that("frozen snapshot is disabled when empty", {
  config <- list(bcb = list(frozen_snapshot = ""))
  expect_null(frozen_snapshot_files(config))
  expect_null(frozen_snapshot_files(list(bcb = list())))
})

test_that("frozen snapshot is reused when the hash matches", {
  dir <- withr::local_tempdir()
  parquet <- file.path(dir, "pix_municipality_test.parquet")
  writeLines("fake parquet bytes", parquet)
  sha <- digest::digest(parquet, algo = "sha256", file = TRUE)
  jsonlite::write_json(
    list(sha256_parquet = sha),
    sub("\\.parquet$", ".json", parquet),
    auto_unbox = TRUE
  )
  files <- frozen_snapshot_files(list(bcb = list(frozen_snapshot = parquet)))
  expect_length(files, 2L)
  expect_match(files[[1]], "\\.parquet$")
})

test_that("frozen snapshot fails on hash mismatch, missing file or metadata", {
  dir <- withr::local_tempdir()
  parquet <- file.path(dir, "snap.parquet")
  writeLines("bytes", parquet)
  config <- list(bcb = list(frozen_snapshot = parquet))
  expect_error(frozen_snapshot_files(config), "no metadata")

  jsonlite::write_json(
    list(sha256_parquet = "deadbeef"),
    sub("\\.parquet$", ".json", parquet),
    auto_unbox = TRUE
  )
  expect_error(frozen_snapshot_files(config), "does not match")

  expect_error(
    frozen_snapshot_files(list(bcb = list(frozen_snapshot = file.path(dir, "nope.parquet")))),
    "not found"
  )
  expect_error(
    frozen_snapshot_files(list(bcb = list(frozen_snapshot = "x.csv"))),
    "\\.parquet"
  )
})

test_that("frozen snapshot without stored hash warns but is reused", {
  dir <- withr::local_tempdir()
  parquet <- file.path(dir, "old.parquet")
  writeLines("bytes", parquet)
  jsonlite::write_json(list(rows = 1), sub("\\.parquet$", ".json", parquet), auto_unbox = TRUE)
  expect_warning(
    files <- frozen_snapshot_files(list(bcb = list(frozen_snapshot = parquet))),
    "integrity not verified"
  )
  expect_length(files, 2L)
})
