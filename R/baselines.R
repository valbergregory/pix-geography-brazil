fit_local_baselines <- function(hierarchy_ts, include_arima = TRUE) {
  if (include_arima) {
    return(
      hierarchy_ts |>
        fabletools::model(
          naive = fable::NAIVE(payer_count),
          seasonal_naive = fable::SNAIVE(payer_count ~ lag("year")),
          drift = fable::RW(payer_count ~ drift()),
          ets = fable::ETS(payer_count),
          arima = fable::ARIMA(payer_count)
        )
    )
  }

  hierarchy_ts |>
    fabletools::model(
      naive = fable::NAIVE(payer_count),
      seasonal_naive = fable::SNAIVE(payer_count ~ lag("year")),
      drift = fable::RW(payer_count ~ drift()),
      ets = fable::ETS(payer_count)
    )
}

forecast_local_baselines <- function(models, horizon) {
  fabletools::forecast(models, h = as.integer(horizon))
}
