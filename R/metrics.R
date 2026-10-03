classify_hierarchy_level <- function(data) {
  region_aggregated <- fabletools::is_aggregated(data$region_code)
  state_aggregated <- fabletools::is_aggregated(data$state_code)
  municipality_aggregated <- fabletools::is_aggregated(
    data$stable_municipality_id
  )

  dplyr::case_when(
    region_aggregated & state_aggregated & municipality_aggregated ~ "national",
    !region_aggregated & state_aggregated & municipality_aggregated ~ "region",
    !region_aggregated & !state_aggregated & municipality_aggregated ~ "state",
    !region_aggregated & !state_aggregated & !municipality_aggregated ~ "municipality",
    TRUE ~ "other"
  )
}

valid_forecast_scale <- function(x) {
  ifelse(is.finite(x) & x > 0, x, NA_real_)
}

finite_mean <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) == 0L) NA_real_ else mean(x)
}

finite_root_mean <- function(x) {
  value <- finite_mean(x)
  if (is.na(value)) NA_real_ else sqrt(value)
}

safe_wape <- function(absolute_error, actual) {
  denominator <- sum(abs(actual), na.rm = TRUE)
  if (!is.finite(denominator) || denominator <= 0) {
    return(NA_real_)
  }
  sum(absolute_error, na.rm = TRUE) / denominator
}

seasonal_scale_table <- function(training, response = "payer_count", seasonal_period = 12L) {
  keys <- tsibble::key_vars(training)
  index <- tsibble::index_var(training)

  training |>
    tibble::as_tibble() |>
    dplyr::arrange(dplyr::across(dplyr::all_of(c(keys, index)))) |>
    dplyr::group_by(dplyr::across(dplyr::all_of(keys))) |>
    dplyr::summarise(
      mae_scale = mean(
        abs(.data[[response]] - dplyr::lag(.data[[response]], seasonal_period)),
        na.rm = TRUE
      ),
      rmsse_scale = sqrt(mean(
        (.data[[response]] - dplyr::lag(.data[[response]], seasonal_period))^2,
        na.rm = TRUE
      )),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      mae_scale = valid_forecast_scale(.data$mae_scale),
      rmsse_scale = valid_forecast_scale(.data$rmsse_scale)
    )
}

forecast_error_rows <- function(
    forecasts,
    actual,
    training,
    origin,
    horizons,
    response = "payer_count",
    seasonal_period = 12L) {
  keys <- tsibble::key_vars(actual)
  index <- tsibble::index_var(actual)
  join_columns <- c(keys, index)

  actual_table <- actual |>
    tibble::as_tibble() |>
    dplyr::select(dplyr::all_of(c(join_columns, response))) |>
    dplyr::rename(actual = dplyr::all_of(response))

  scale_table <- seasonal_scale_table(
    training,
    response = response,
    seasonal_period = seasonal_period
  )

  purrr::map_dfr(as.integer(horizons), function(horizon) {
    target_month <- origin + horizon

    forecasts |>
      tibble::as_tibble() |>
      dplyr::filter(.data[[index]] == target_month) |>
      dplyr::mutate(prediction = as.numeric(.data$.mean)) |>
      dplyr::select(dplyr::all_of(c(join_columns, ".model", "prediction"))) |>
      dplyr::left_join(actual_table, by = join_columns) |>
      dplyr::left_join(scale_table, by = keys) |>
      dplyr::mutate(
        origin = origin,
        horizon = horizon,
        hierarchy_level = classify_hierarchy_level(dplyr::pick(dplyr::all_of(keys))),
        error = .data$actual - .data$prediction,
        absolute_error = abs(.data$error),
        squared_error = .data$error^2
      )
  })
}

summarise_forecast_accuracy <- function(error_rows) {
  error_rows |>
    dplyr::mutate(
      scaled_absolute_error = dplyr::if_else(
        is.finite(.data$mae_scale) & .data$mae_scale > 0,
        .data$absolute_error / .data$mae_scale,
        NA_real_
      ),
      scaled_squared_error = dplyr::if_else(
        is.finite(.data$rmsse_scale) & .data$rmsse_scale > 0,
        .data$squared_error / (.data$rmsse_scale^2),
        NA_real_
      )
    ) |>
    dplyr::group_by(
      .data$.model,
      .data$horizon,
      .data$hierarchy_level
    ) |>
    dplyr::summarise(
      series_origins = dplyr::n(),
      scaled_origins = sum(is.finite(.data$scaled_absolute_error)),
      MAE = mean(.data$absolute_error, na.rm = TRUE),
      RMSE = sqrt(mean(.data$squared_error, na.rm = TRUE)),
      MASE = finite_mean(.data$scaled_absolute_error),
      RMSSE = finite_root_mean(.data$scaled_squared_error),
      WAPE = safe_wape(.data$absolute_error, .data$actual),
      .groups = "drop"
    )
}
