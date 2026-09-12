synthetic_error_rows <- function() {
  tidyr::expand_grid(
    stable_municipality_id = c("2700102", "2700201"),
    region_code = "NE",
    state_code = "27",
    origin = tsibble::yearmonth(c("2024 Jan", "2024 Feb")),
    horizon = c(1L, 3L, 6L),
    .model = c("seasonal_naive", "ets_wls")
  ) |>
    dplyr::mutate(
      month = .data$origin + .data$horizon,
      hierarchy_level = "municipality",
      actual = 100,
      prediction = dplyr::if_else(.data$.model == "ets_wls", 98, 94),
      error = .data$actual - .data$prediction,
      absolute_error = abs(.data$error),
      squared_error = .data$error^2,
      mae_scale = 10,
      rmsse_scale = 12
    )
}

test_that("publication tables retain all requested forecast horizons", {
  accuracy <- summarise_forecast_accuracy(synthetic_error_rows())
  table <- municipal_accuracy_table(accuracy)

  expect_true("Model" %in% names(table))
  expect_true(all(c("MASE h=1", "MASE h=3", "MASE h=6") %in% names(table)))
  expect_equal(nrow(table), 2L)
})

test_that("relative gains are positive for the lower-loss model", {
  gains <- relative_gain_table(
    synthetic_error_rows(),
    benchmark_model = "seasonal_naive"
  ) |>
    dplyr::filter(.data$Model == "ets_wls")

  expect_true(all(gains$`Gain versus benchmark (%)` > 0))
})

test_that("reporting functions create ggplot objects", {
  panel <- tibble::tibble(
    month = rep(seq(as.Date("2023-01-01"), by = "month", length.out = 12), 2),
    region_code = rep(c("NE", "SE"), each = 12),
    state_code = rep(c("27", "35"), each = 12),
    payer_count = seq_len(24)
  )
  figure <- plot_pix_evolution(panel, level = "region")
  expect_s3_class(figure, "ggplot")
})

test_that("R global predictions fail loudly when a hierarchy key is absent", {
  incomplete <- tibble::tibble(
    origin = as.Date("2024-01-01"),
    month = as.Date("2024-02-01"),
    .model = "xgboost_global",
    horizon = 1L,
    prediction = 100
  )
  expect_error(
    validate_r_global_prediction_schema(incomplete),
    "region_code"
  )
})
