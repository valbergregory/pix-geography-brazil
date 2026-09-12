test_that("BCB query preserves the configured OData contract", {
  config <- list(
    bcb = list(
      page_size = 100L,
      database_parameter = "20232"
    )
  )
  query <- pix_query_parameters(config, skip = 200L)

  expect_identical(query[["@DataBase"]], "'20232'")
  expect_identical(query[["$format"]], "json")
  expect_identical(query[["$top"]], 100L)
  expect_identical(query[["$skip"]], 200L)
})

test_that("pagination guard rejects a repeated page", {
  page <- tibble::tibble(AnoMes = 202401L, Municipio_Ibge = 2704302L)
  seen <- pix_page_fingerprint(page)

  expect_error(
    assert_new_pix_page(page, seen, skip = 100L),
    "did not advance"
  )
})
