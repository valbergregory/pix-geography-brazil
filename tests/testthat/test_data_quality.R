test_that("payer target does not double-count the receiver perspective", {
  targets <- synthetic_pix_raw() |>
    standardize_pix_columns() |>
    build_additive_targets()

  expect_equal(targets$payer_count, c(15, 26, 16, 28))
  expect_false(any(targets$payer_count >= 999))
})

test_that("territorial discontinuity becomes one stable monthly unit", {
  panel <- build_analysis_panel(synthetic_pix_raw(), test_config())

  expect_equal(nrow(panel), 2L)
  expect_true(all(panel$stable_municipality_id == "MT_STABLE"))
  expect_equal(panel$payer_count, c(41, 44))
  expect_silent(validate_analysis_panel(panel, test_config()))
})

test_that("raw schema check fails loudly when a source field disappears", {
  incomplete <- synthetic_pix_raw() |>
    dplyr::select(-QT_PagadorPF)

  expect_error(validate_pix_schema(incomplete), "QT_PagadorPF")
})

test_that("rolling origins respect the initial window and maximum horizon", {
  months <- tsibble::yearmonth("2020 Jan") + 0:47
  origins <- make_rolling_origins(
    months,
    initial_window = 36L,
    maximum_horizon = 6L,
    step = 1L
  )

  expect_equal(origins[[1]], months[[36]])
  expect_equal(tail(origins, 1), months[[42]])
})
