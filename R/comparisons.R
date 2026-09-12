model_loss_by_origin <- function(error_rows, loss = c("absolute", "squared")) {
  loss <- match.arg(loss)
  loss_column <- switch(
    loss,
    absolute = "absolute_error",
    squared = "squared_error"
  )

  error_rows |>
    dplyr::group_by(
      .data$origin,
      .data$horizon,
      .data$hierarchy_level,
      .data$.model
    ) |>
    dplyr::summarise(
      loss = mean(.data[[loss_column]], na.rm = TRUE),
      .groups = "drop"
    )
}

compare_models_newey_west <- function(
    error_rows,
    model_a,
    model_b,
    loss = c("absolute", "squared")) {
  loss <- match.arg(loss)

  paired <- model_loss_by_origin(error_rows, loss = loss) |>
    dplyr::filter(.data$.model %in% c(model_a, model_b)) |>
    tidyr::pivot_wider(names_from = .model, values_from = loss)

  if (!all(c(model_a, model_b) %in% names(paired))) {
    stop("Both requested models must be present in error_rows.", call. = FALSE)
  }

  paired |>
    dplyr::filter(!is.na(.data[[model_a]]), !is.na(.data[[model_b]])) |>
    dplyr::mutate(loss_difference = .data[[model_a]] - .data[[model_b]]) |>
    dplyr::group_by(.data$horizon, .data$hierarchy_level) |>
    dplyr::group_modify(function(.x, .y) {
      fit <- stats::lm(loss_difference ~ 1, data = .x)
      hac_lag <- max(0L, as.integer(.y$horizon[[1]]) - 1L)
      covariance <- sandwich::NeweyWest(
        fit,
        lag = hac_lag,
        prewhite = FALSE,
        adjust = TRUE
      )
      estimate <- unname(stats::coef(fit)[[1]])
      standard_error <- sqrt(covariance[1, 1])
      statistic <- estimate / standard_error

      tibble::tibble(
        model_a = model_a,
        model_b = model_b,
        loss = loss,
        origins = nrow(.x),
        mean_loss_difference = estimate,
        hac_standard_error = standard_error,
        statistic = statistic,
        p_value = 2 * stats::pnorm(-abs(statistic)),
        confidence_low = estimate - stats::qnorm(0.975) * standard_error,
        confidence_high = estimate + stats::qnorm(0.975) * standard_error
      )
    }) |>
    dplyr::ungroup()
}
