fit_reconciled_ets <- function(hierarchy_ts, include_mint_shrink = FALSE) {
  base_models <- hierarchy_ts |>
    fabletools::model(ets = fable::ETS(payer_count))

  if (include_mint_shrink) {
    return(
      base_models |>
        fabletools::reconcile(
          ets_bottom_up = fabletools::bottom_up(ets),
          ets_wls = fabletools::min_trace(
            ets,
            method = "wls_var",
            sparse = TRUE
          ),
          ets_mint_shrink = fabletools::min_trace(
            ets,
            method = "mint_shrink",
            sparse = TRUE
          )
        )
    )
  }

  base_models |>
    fabletools::reconcile(
      ets_bottom_up = fabletools::bottom_up(ets),
      ets_wls = fabletools::min_trace(
        ets,
        method = "wls_var",
        sparse = TRUE
      )
    )
}

forecast_reconciled_models <- function(models, horizon) {
  fabletools::forecast(models, h = as.integer(horizon))
}

negative_forecast_diagnostics <- function(forecasts) {
  forecasts |>
    tibble::as_tibble() |>
    dplyr::group_by(.data$.model) |>
    dplyr::summarise(
      forecasts = dplyr::n(),
      negative_forecasts = sum(as.numeric(.data$.mean) < 0, na.rm = TRUE),
      negative_share = mean(as.numeric(.data$.mean) < 0, na.rm = TRUE),
      .groups = "drop"
    )
}
