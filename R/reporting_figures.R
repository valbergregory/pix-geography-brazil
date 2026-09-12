theme_article <- function(base_size = 10.5, base_family = "sans") {
  ggplot2::theme_minimal(base_size = base_size, base_family = base_family) +
    ggplot2::theme(
      plot.title.position = "plot",
      plot.title = ggplot2::element_text(face = "bold", size = base_size + 1),
      plot.subtitle = ggplot2::element_text(color = "grey30"),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major.x = ggplot2::element_blank(),
      axis.title = ggplot2::element_text(face = "bold"),
      legend.position = "bottom",
      legend.title = ggplot2::element_text(face = "bold"),
      strip.text = ggplot2::element_text(face = "bold"),
      plot.caption = ggplot2::element_text(
        color = "grey35",
        hjust = 0,
        size = base_size - 1
      )
    )
}

save_article_figure <- function(
    plot,
    filename,
    config,
    width = config$reporting$figure_width_inches,
    height = config$reporting$figure_height_inches) {
  ensure_project_directories(config)
  stem <- tools::file_path_sans_ext(filename)
  pdf_path <- file.path(config$reporting$figures_dir, paste0(stem, ".pdf"))
  png_path <- file.path(config$reporting$figures_dir, paste0(stem, ".png"))
  pdf_device <- if (capabilities("cairo")) {
    grDevices::cairo_pdf
  } else {
    grDevices::pdf
  }

  ggplot2::ggsave(
    filename = pdf_path,
    plot = plot,
    device = pdf_device,
    width = as.numeric(width),
    height = as.numeric(height),
    units = "in",
    bg = "white"
  )
  ggplot2::ggsave(
    filename = png_path,
    plot = plot,
    device = ragg::agg_png,
    width = as.numeric(width),
    height = as.numeric(height),
    units = "in",
    dpi = as.integer(config$reporting$figure_dpi),
    bg = "white"
  )

  normalizePath(c(pdf_path, png_path), winslash = "/", mustWork = TRUE)
}

plot_pix_evolution <- function(panel, level = c("national", "region", "state")) {
  level <- match.arg(level)
  group_column <- switch(
    level,
    national = character(),
    region = "region_code",
    state = "state_code"
  )

  series <- panel |>
    dplyr::group_by(dplyr::across(dplyr::all_of(c(group_column, "month")))) |>
    dplyr::summarise(payer_count = sum(.data$payer_count), .groups = "drop")

  if (level == "national") {
    series <- series |>
      dplyr::mutate(Series = "Brazil")
  } else {
    series <- series |>
      dplyr::mutate(Series = as.character(.data[[group_column]]))
  }

  ggplot2::ggplot(
    series,
    ggplot2::aes(
      x = .data$month,
      y = .data$payer_count,
      color = .data$Series,
      group = .data$Series
    )
  ) +
    ggplot2::geom_line(linewidth = 0.75, na.rm = TRUE) +
    ggplot2::scale_color_viridis_d(option = "D", end = 0.9) +
    ggplot2::scale_y_continuous(
      labels = scales::label_number(scale_cut = scales::cut_short_scale())
    ) +
    ggplot2::scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
    ggplot2::labs(
      title = paste("Evolution of outgoing Pix transactions by", level),
      x = NULL,
      y = "Monthly transactions",
      color = tools::toTitleCase(level),
      caption = "Source: Banco Central do Brasil. Payer perspective; PF and PJ combined."
    ) +
    theme_article()
}

plot_structural_breaks <- function(series, breaks) {
  plot <- ggplot2::ggplot(
    series,
    ggplot2::aes(x = .data$month, y = .data$payer_count)
  ) +
    ggplot2::geom_line(color = "#1F4E79", linewidth = 0.8) +
    ggplot2::scale_y_continuous(
      labels = scales::label_number(scale_cut = scales::cut_short_scale())
    ) +
    ggplot2::scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
    ggplot2::labs(
      title = "Structural-break diagnostics for national Pix activity",
      subtitle = "Break dates are descriptive and are not supplied to forecasting models",
      x = NULL,
      y = "Monthly transactions",
      caption = "Vertical lines report break dates selected by Bai-Perron or PELT diagnostics."
    ) +
    theme_article()

  if (nrow(breaks) > 0L) {
    plot <- plot +
      ggplot2::geom_vline(
        data = breaks,
        ggplot2::aes(xintercept = .data$break_month, linetype = .data$method),
        color = "#B22222",
        linewidth = 0.6,
        alpha = 0.85
      ) +
      ggplot2::scale_linetype_discrete(name = "Diagnostic")
  }

  plot
}

plot_accuracy_by_horizon <- function(accuracy, level = "municipality") {
  work <- accuracy |>
    dplyr::filter(.data$hierarchy_level == level)

  ggplot2::ggplot(
    work,
    ggplot2::aes(
      x = factor(.data$horizon),
      y = .data$MASE,
      color = .data$.model,
      group = .data$.model
    )
  ) +
    ggplot2::geom_hline(
      yintercept = 1,
      linewidth = 0.45,
      color = "grey55",
      linetype = "dashed"
    ) +
    ggplot2::geom_line(linewidth = 0.7) +
    ggplot2::geom_point(size = 2) +
    ggplot2::scale_color_viridis_d(option = "D", end = 0.9) +
    ggplot2::labs(
      title = paste("Forecast accuracy at the", level, "level"),
      subtitle = "MASE below one improves on the in-sample seasonal scale",
      x = "Forecast horizon (months)",
      y = "MASE",
      color = "Model"
    ) +
    theme_article()
}

plot_scaled_error_distribution <- function(error_rows, level = "municipality") {
  work <- error_rows |>
    dplyr::filter(.data$hierarchy_level == level) |>
    dplyr::mutate(
      scaled_absolute_error = .data$absolute_error / .data$mae_scale
    ) |>
    dplyr::filter(
      is.finite(.data$scaled_absolute_error),
      .data$scaled_absolute_error > 0
    )

  ggplot2::ggplot(
    work,
    ggplot2::aes(
      x = stats::reorder(.data$.model, .data$scaled_absolute_error, median),
      y = .data$scaled_absolute_error,
      fill = .data$.model
    )
  ) +
    ggplot2::geom_boxplot(
      width = 0.7,
      outlier.alpha = 0.08,
      linewidth = 0.4
    ) +
    ggplot2::facet_wrap(~ horizon, scales = "free_y") +
    ggplot2::scale_fill_viridis_d(option = "D", end = 0.9, guide = "none") +
    ggplot2::scale_y_log10() +
    ggplot2::coord_flip() +
    ggplot2::labs(
      title = "Distribution of scaled absolute forecast errors",
      subtitle = paste("Geographic level:", level),
      x = NULL,
      y = "Scaled absolute error (log scale)"
    ) +
    theme_article()
}

plot_relative_gain <- function(error_rows, benchmark_model, level = "municipality") {
  work <- relative_gain_table(error_rows, benchmark_model) |>
    dplyr::filter(.data$Level == level, .data$Model != benchmark_model)

  ggplot2::ggplot(
    work,
    ggplot2::aes(
      x = stats::reorder(.data$Model, .data$`Gain versus benchmark (%)`),
      y = .data$`Gain versus benchmark (%)`,
      fill = factor(.data$Horizon)
    )
  ) +
    ggplot2::geom_hline(yintercept = 0, color = "grey40", linewidth = 0.4) +
    ggplot2::geom_col(position = ggplot2::position_dodge(width = 0.75)) +
    ggplot2::scale_fill_viridis_d(option = "D", end = 0.9) +
    ggplot2::coord_flip() +
    ggplot2::labs(
      title = paste("Forecast gain relative to", benchmark_model),
      subtitle = paste("Geographic level:", level),
      x = NULL,
      y = "Reduction in mean absolute loss (%)",
      fill = "Horizon"
    ) +
    theme_article()
}

plot_forecast_gain_map <- function(
    municipality_geometry,
    error_rows,
    benchmark_model,
    comparison_model,
    horizon = 1L) {
  if (!inherits(municipality_geometry, "sf")) {
    stop("municipality_geometry must be an sf object.", call. = FALSE)
  }
  if (!"stable_municipality_id" %in% names(municipality_geometry)) {
    stop(
      "Municipality geometry requires stable_municipality_id.",
      call. = FALSE
    )
  }

  losses <- error_rows |>
    dplyr::filter(
      .data$hierarchy_level == "municipality",
      .data$horizon == as.integer(horizon),
      .data$.model %in% c(benchmark_model, comparison_model)
    ) |>
    dplyr::group_by(.data$stable_municipality_id, .data$.model) |>
    dplyr::summarise(loss = mean(.data$absolute_error), .groups = "drop") |>
    tidyr::pivot_wider(names_from = .model, values_from = loss)

  if (!all(c(benchmark_model, comparison_model) %in% names(losses))) {
    stop("Map requires both benchmark and comparison model losses.", call. = FALSE)
  }

  losses <- losses |>
    dplyr::mutate(
      relative_gain_percent = dplyr::if_else(
        is.finite(.data[[benchmark_model]]) & .data[[benchmark_model]] > 0,
        100 * (.data[[benchmark_model]] - .data[[comparison_model]]) /
          .data[[benchmark_model]],
        NA_real_
      )
    )

  map_data <- municipality_geometry |>
    dplyr::mutate(stable_municipality_id = as.character(.data$stable_municipality_id)) |>
    dplyr::left_join(losses, by = "stable_municipality_id")

  ggplot2::ggplot(map_data) +
    ggplot2::geom_sf(
      ggplot2::aes(fill = .data$relative_gain_percent),
      color = NA
    ) +
    ggplot2::scale_fill_gradient2(
      low = "#B2182B",
      mid = "#F7F7F7",
      high = "#2166AC",
      midpoint = 0,
      na.value = "grey85"
    ) +
    ggplot2::labs(
      title = paste("Geography of forecast gains at horizon", horizon),
      subtitle = paste(comparison_model, "relative to", benchmark_model),
      fill = "Gain (%)",
      caption = "Positive values indicate lower mean absolute loss for the comparison model."
    ) +
    ggplot2::coord_sf(datum = NA) +
    theme_article() +
    ggplot2::theme(
      axis.text = ggplot2::element_blank(),
      axis.title = ggplot2::element_blank(),
      panel.grid = ggplot2::element_blank()
    )
}

export_descriptive_figures <- function(panel, break_series, breaks, config) {
  c(
    save_article_figure(
      plot_pix_evolution(panel, level = "national"),
      "figure_pix_evolution_national",
      config
    ),
    save_article_figure(
      plot_pix_evolution(panel, level = "region"),
      "figure_pix_evolution_regions",
      config
    ),
    save_article_figure(
      plot_structural_breaks(break_series, breaks),
      "figure_structural_breaks",
      config
    )
  )
}

export_forecast_figures <- function(error_rows, config) {
  accuracy <- summarise_forecast_accuracy(error_rows)
  benchmark <- config$reporting$benchmark_model

  c(
    save_article_figure(
      plot_accuracy_by_horizon(accuracy, level = "municipality"),
      "figure_accuracy_by_horizon",
      config
    ),
    save_article_figure(
      plot_scaled_error_distribution(error_rows, level = "municipality"),
      "figure_error_distribution",
      config,
      height = 5.6
    ),
    save_article_figure(
      plot_relative_gain(error_rows, benchmark, level = "municipality"),
      "figure_relative_gain",
      config,
      height = 5.2
    )
  )
}
