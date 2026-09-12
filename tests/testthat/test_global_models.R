synthetic_global_panel <- function() {
  tidyr::expand_grid(
    stable_municipality_id = c("2700102", "2700201"),
    month = seq(as.Date("2020-01-01"), by = "month", length.out = 24L)
  ) |>
    dplyr::arrange(.data$stable_municipality_id, .data$month) |>
    dplyr::mutate(
      state_code = "27",
      region_code = "NE",
      payer_count = 100 + dplyr::row_number()
    )
}

test_that("global stacked labels never exceed the forecast origin", {
  config <- global_test_config()
  features <- build_global_feature_panel(synthetic_global_panel(), config)
  origin <- as.Date("2021-06-01")
  stacked <- stack_direct_horizon_data(features, origin, config)

  expect_true(max(stacked$target_months) <= origin)
  expect_equal(sort(unique(stacked$x_train$horizon)), c(1L, 3L, 6L))
  expect_equal(nrow(stacked$x_predict), 6L)
})

test_that("bottom-up global predictions are geographically coherent", {
  predictions <- tidyr::expand_grid(
    stable_municipality_id = c("2700102", "2700201"),
    horizon = c(1L, 3L)
  ) |>
    dplyr::mutate(
      origin = tsibble::yearmonth("2024 Jan"),
      month = .data$origin + .data$horizon,
      region_code = "NE",
      state_code = "27",
      hierarchy_level = "municipality",
      .model = "ridge_global",
      prediction = 10
    )

  coherent <- aggregate_bottom_up_predictions(predictions)
  national <- coherent |>
    dplyr::filter(.data$hierarchy_level == "national")
  expect_equal(national$prediction, c(20, 20))
  expect_true(all(grepl("_bottom_up$", coherent$.model)))
})
