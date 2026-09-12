library(targets)

tar_source("R")

tar_option_set(
  packages = setdiff(
    required_packages,
    c("renv", "targets", "testthat")
  ),
  format = "rds",
  memory = "transient",
  garbage_collection = TRUE
)

list(
  tar_target(
    config_file,
    "config.yml",
    format = "file"
  ),
  tar_target(
    config,
    read_project_config(config_file)
  ),
  tar_target(
    full_run_flag,
    is_full_run(config),
    cue = tar_cue(mode = "always")
  ),
  tar_target(
    package_check,
    check_required_packages()
  ),
  tar_target(
    raw_snapshot_files,
    {
      package_check
      extract_pix_snapshot(config)
    },
    format = "file"
  ),
  tar_target(
    raw_pix,
    read_pix_snapshot(raw_snapshot_files)
  ),
  tar_target(
    raw_validation,
    validate_pix_raw(
      raw_pix,
      minimum_months = config$analysis$initial_window_months,
      minimum_identified_units = config$quality$minimum_identified_units,
      strict_geographic_coverage = config$quality$strict_geographic_coverage
    )
  ),
  tar_target(
    analysis_panel,
    {
      raw_validation
      build_analysis_panel(raw_pix, config)
    }
  ),
  tar_target(
    processed_panel_file,
    write_analysis_panel(analysis_panel, config),
    format = "file"
  ),
  tar_target(
    data_quality_outputs,
    export_data_quality_outputs(raw_pix, analysis_panel, config),
    format = "file"
  ),
  tar_target(
    identified_panel,
    select_analysis_scope(
      analysis_panel,
      config,
      full_run = TRUE
    )
  ),
  tar_target(
    descriptive_outputs,
    create_descriptive_outputs(identified_panel, config),
    format = "file"
  ),
  tar_target(
    duckdb_file,
    create_duckdb_catalog(processed_panel_file, config),
    format = "file"
  ),
  tar_target(
    scoped_panel,
    select_analysis_scope(
      analysis_panel,
      config,
      full_run = full_run_flag
    )
  ),
  tar_target(
    hierarchy_ts,
    build_hierarchical_tsibble(scoped_panel)
  ),
  tar_target(
    global_feature_panel,
    build_global_feature_panel(scoped_panel, config)
  ),
  tar_target(
    rolling_origins,
    make_rolling_origins(
      months = hierarchy_ts$month,
      initial_window = config$analysis$initial_window_months,
      maximum_horizon = max(as.integer(unlist(config$analysis$horizons))),
      step = config$analysis$origin_step_months
    )
  ),
  tar_target(
    scope_label,
    if (full_run_flag) "national" else "pilot_alagoas_roraima"
  ),
  tar_target(
    local_errors,
    rolling_origin_evaluate(
      hierarchy_ts = hierarchy_ts,
      config = config,
      reconciled = FALSE,
      include_arima = TRUE,
      label = scope_label
    )
  ),
  tar_target(
    reconciled_errors,
    rolling_origin_evaluate(
      hierarchy_ts = hierarchy_ts,
      config = config,
      reconciled = TRUE,
      include_arima = FALSE,
      label = scope_label
    ) |>
      dplyr::filter(.data$.model != "ets")
  ),
  tar_target(
    global_errors,
    rolling_origin_global_evaluate(
      panel = scoped_panel,
      hierarchy_ts = hierarchy_ts,
      config = config,
      label = scope_label,
      feature_panel = global_feature_panel
    )
  ),
  tar_target(
    global_model_artifact_files,
    {
      global_errors
      export_final_global_model_artifacts(
        scoped_panel,
        config,
        label = scope_label,
        feature_panel = global_feature_panel
      )
    },
    format = "file"
  ),
  tar_target(
    all_errors,
    dplyr::bind_rows(local_errors, reconciled_errors, global_errors)
  ),
  tar_target(
    forecast_output_files,
    export_forecast_results(all_errors, config, label = scope_label),
    format = "file"
  ),
  tar_target(
    reliability_output_files,
    export_forecast_reliability_analysis(
      all_errors,
      scoped_panel,
      config,
      label = scope_label
    ),
    format = "file"
  ),
  tar_target(
    forecast_map_files,
    safe_export_gain_map(
      all_errors,
      config,
      label = scope_label,
      horizon = 1L
    ),
    format = "file"
  )
)
