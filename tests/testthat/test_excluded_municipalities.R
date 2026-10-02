test_that("excluded municipalities are removed before aggregation", {
  data <- tibble::tibble(
    municipality_code = c(2401305L, 2405306L, 2700300L, NA_integer_),
    payer_count = c(1, 2, 3, 4)
  )
  config <- list(geography = list(excluded_municipality_codes = c(2401305, 2405306)))
  out <- exclude_municipalities(data, config)
  expect_equal(out$municipality_code, c(2700300L, NA_integer_))
})

test_that("no exclusion list keeps every row", {
  data <- tibble::tibble(municipality_code = c(1L, 2L))
  expect_equal(nrow(exclude_municipalities(data, list(geography = list()))), 2L)
  expect_equal(
    nrow(exclude_municipalities(data, list(geography = list(excluded_municipality_codes = list())))),
    2L
  )
})

test_that("invalid codes are rejected", {
  data <- tibble::tibble(municipality_code = 1L)
  config <- list(geography = list(excluded_municipality_codes = c("abc")))
  expect_error(suppressWarnings(exclude_municipalities(data, config)), "IBGE codes")
})

test_that("excluded municipalities no longer create calendar gaps", {
  raw <- synthetic_pix_raw()
  late <- raw[1, ]
  late$AnoMes <- 202302L
  late$Municipio_Ibge <- 2401305L
  late$Municipio <- "CAMPO GRANDE"
  late$Estado_Ibge <- 24L
  raw <- dplyr::bind_rows(raw, late)
  config <- test_config()
  config$geography$stable_mt_codes <- integer()
  config$geography$stable_mt_key <- "MT"
  config$geography$stable_mt_name <- "MT"

  with_gap <- build_analysis_panel(raw, config)
  expect_gt(nrow(analysis_panel_calendar_gaps(with_gap, "N/D")), 0L)

  config$geography$excluded_municipality_codes <- c(2401305)
  without <- build_analysis_panel(raw, config)
  expect_equal(nrow(analysis_panel_calendar_gaps(without, "N/D")), 0L)
})
