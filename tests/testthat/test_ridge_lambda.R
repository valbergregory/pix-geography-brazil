make_ridge_data <- function(n_months = 30L, units = 20L, seed = 1L) {
  set.seed(seed)
  months <- seq(as.Date("2022-01-01"), by = "month", length.out = n_months)
  grid <- expand.grid(unit = seq_len(units), month = months)
  x <- cbind(a = rnorm(nrow(grid)), b = rnorm(nrow(grid)), noise = rnorm(nrow(grid)))
  y <- expm1(pmax(2 + 0.8 * x[, "a"] - 0.5 * x[, "b"] + rnorm(nrow(grid), sd = 0.3), 0))
  list(x = x, y = y, months = grid$month)
}

test_that("validation split uses only the last months of the window", {
  months <- seq(as.Date("2023-01-01"), by = "month", length.out = 12L)
  split <- ridge_validation_split(rep(months, each = 2L), 3L)
  expect_equal(sum(split), 6L)
  expect_true(all(rep(months, each = 2L)[split] > as.Date("2023-09-01")))
  expect_error(ridge_validation_split(months[1:2], 5L), "both training and")
  expect_error(ridge_validation_split(months, 0L), "positive integer")
})

test_that("temporal CV picks a lambda from the path and refits", {
  d <- make_ridge_data()
  design <- list(x_train = d$x, x_predict = d$x[1:5, , drop = FALSE])
  config <- list(models = list(global = list(
    target_transform = "log1p",
    ridge = list(enabled = TRUE, lambda = "temporal_cv", validation_months = 6L)
  )))
  fit <- fit_ridge_global(design, d$y, config, target_months = d$months)
  expect_true(fit$lambda %in% fit$selection$path)
  expect_equal(length(fit$prediction), 5L)
  expect_true(all(fit$prediction >= 0))
  expect_true(fit$selection$validation_rows == 20L * 6L)
})

test_that("a numeric lambda keeps the fixed behaviour", {
  d <- make_ridge_data()
  design <- list(x_train = d$x, x_predict = d$x[1:3, , drop = FALSE])
  config <- list(models = list(global = list(
    target_transform = "log1p",
    ridge = list(enabled = TRUE, lambda = 1)
  )))
  fit <- fit_ridge_global(design, d$y, config)
  expect_equal(fit$lambda, 1)
  expect_null(fit$selection)
  expect_error(
    fit_ridge_global(design, d$y, list(models = list(global = list(
      target_transform = "log1p", ridge = list(lambda = "temporal_cv", validation_months = 6L)
    )))),
    "label months"
  )
})
