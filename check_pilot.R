# Verifica os critérios de aprovação do piloto (C1-C4) depois de run_pilot.R.
# Critérios: docs/PILOT_APPROVAL_CRITERIA.md. Este script apenas lê os alvos e
# as saídas do piloto; não reexecuta modelos. Dados ausentes contam como FAIL.
source("R/setup.R")
check_required_packages()
options(error = NULL)
targets::tar_source("R")

config <- read_project_config("config.yml")
thresholds <- pilot_approval_thresholds()
expected_label <- "pilot_alagoas_roraima"
expected_states <- as.integer(unlist(config$analysis$pilot_state_codes))
horizons <- as.integer(unlist(config$analysis$horizons))

# Lê um insumo; qualquer falha vira NULL e, portanto, FAIL no critério.
read_or_null <- function(expr, what) {
  tryCatch(
    expr,
    error = function(error) {
      message("Unavailable input (", what, "): ", conditionMessage(error))
      NULL
    }
  )
}

# fabletools carrega os métodos das chaves agregadas (agg_vec) das linhas de erro.
invisible(requireNamespace("fabletools", quietly = TRUE))
invisible(requireNamespace("tsibble", quietly = TRUE))

required_targets <- read_or_null(
  targets::tar_manifest(fields = tidyselect::any_of("name"))$name,
  "tar_manifest"
)
meta <- read_or_null(
  targets::tar_meta(
    names = tidyselect::any_of(required_targets),
    fields = tidyselect::any_of(c("name", "error", "warnings"))
  ),
  "tar_meta"
)
scope_label <- read_or_null(targets::tar_read(scope_label), "scope_label")
warning_explanations <- read_or_null(
  read_pilot_warning_explanations("docs/pilot_warning_explanations.csv"),
  "docs/pilot_warning_explanations.csv"
)

label <- expected_label
gaps_path <- file.path(config$project$output_dir, "analysis_panel_calendar_gaps.csv")
calendar_gaps <- if (file.exists(gaps_path)) {
  read_or_null(readr::read_csv(gaps_path, show_col_types = FALSE), gaps_path)
} else {
  NULL
}
panel <- read_or_null(targets::tar_read(scoped_panel), "scoped_panel")
error_rows_path <- file.path(
  config$project$output_dir,
  paste0("forecast_error_rows_", label, ".rds")
)
error_rows <- if (file.exists(error_rows_path)) {
  read_or_null(readRDS(error_rows_path), error_rows_path)
} else {
  NULL
}
map_files <- read_or_null(targets::tar_read(forecast_map_files), "forecast_map_files")

checks <- dplyr::bind_rows(
  check_pilot_execution(
    meta = meta,
    required_targets = required_targets,
    scope_label = scope_label,
    expected_label = expected_label,
    warning_explanations = warning_explanations
  ),
  check_pilot_geography(
    calendar_gaps = calendar_gaps,
    panel = panel,
    expected_states = expected_states,
    error_rows = error_rows,
    map_files = map_files,
    tolerance = thresholds$coherence_relative_tolerance
  ),
  check_pilot_predictive(
    error_rows = error_rows,
    expected_states = expected_states,
    horizons = horizons,
    benchmark_model = config$reporting$benchmark_model,
    thresholds = thresholds
  ),
  check_pilot_reconciliation(
    error_rows = error_rows,
    horizons = horizons,
    thresholds = thresholds
  )
)

report <- write_pilot_approval_report(checks, config$project$output_dir)

message("Pilot approval criteria (docs/PILOT_APPROVAL_CRITERIA.md):")
print(report$summary, n = Inf)
print(
  checks |>
    dplyr::select("criterion", "check", "status", "value"),
  n = Inf,
  width = Inf
)
message("Report written to ", report$csv, " and ", report$markdown, ".")

if (all(report$summary$status == "PASS")) {
  message("C1-C4 = PASS. The national run may be started with run_national_background.R.")
} else {
  message(
    "At least one criterion FAILED. Do not start run_national_background.R; ",
    "read ", report$markdown, "."
  )
}
