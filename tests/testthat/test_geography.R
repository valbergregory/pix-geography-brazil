test_that("municipality geometry requires valid unique spatial keys", {
  square <- sf::st_polygon(list(matrix(
    c(0, 0, 1, 0, 1, 1, 0, 1, 0, 0),
    ncol = 2,
    byrow = TRUE
  )))
  shifted_square <- sf::st_polygon(list(matrix(
    c(2, 0, 3, 0, 3, 1, 2, 1, 2, 0),
    ncol = 2,
    byrow = TRUE
  )))
  geometry <- sf::st_sf(
    stable_municipality_id = c("A", "B"),
    geometry = sf::st_sfc(square, shifted_square, crs = 4674)
  )

  expect_s3_class(validate_municipality_geometry(geometry), "sf")
  duplicated <- geometry
  duplicated$stable_municipality_id <- c("A", "A")
  expect_error(
    validate_municipality_geometry(duplicated),
    "duplicated stable keys"
  )

  required <- tibble::tibble(stable_municipality_id = c("A", "C"))
  expect_error(
    validate_geometry_coverage(geometry, required),
    "missing 1 required municipality keys"
  )
})
