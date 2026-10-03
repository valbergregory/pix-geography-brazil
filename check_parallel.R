# Teste rápido da avaliação paralela por origem (decisão de 2026-10-03, AUDIT_DECISIONS.md).
# Usa o painel do piloto já calculado (targets::tar_read(hierarchy_ts)), roda as 2
# primeiras origens dos modelos locais SEM ARIMA em sequência e em 2 workers e
# confere que os resultados são idênticos. Não grava checkpoints nem altera alvos.
# Uso (Console, na pasta do projeto): source("check_parallel.R")  (~2-5 min)
source("R/setup.R")
check_required_packages()
targets::tar_source("R")
for (package in c("dplyr", "tsibble", "fabletools", "fable", "feasts")) {
  suppressPackageStartupMessages(library(package, character.only = TRUE))
}

config <- read_project_config("config.yml")
hierarchy_ts <- targets::tar_read(hierarchy_ts)
horizons <- as.integer(unlist(config$analysis$horizons))
origins <- make_rolling_origins(
  months = hierarchy_ts$month,
  initial_window = config$analysis$initial_window_months,
  maximum_horizon = max(horizons),
  step = config$analysis$origin_step_months
)
spec <- list(
  origins = origins, horizons = horizons, reconciled = FALSE, include_mint_shrink = FALSE,
  include_arima = FALSE, seasonal_period = config$analysis$seasonal_period,
  batch = "parallel_check", checkpoint_directory = NULL
)
data <- list(hierarchy_ts = hierarchy_ts, spec = spec)

time_seq <- system.time(sequential <- run_origin_tasks(1:2, evaluate_origin_index, workers = 1L, worker_data = data))
time_par <- system.time(parallel_run <- run_origin_tasks(1:2, evaluate_origin_index, workers = 2L,
                                                          worker_setup = setup_origin_worker, worker_data = data))
drop_time <- function(x) dplyr::select(dplyr::bind_rows(x), -"origin_elapsed_seconds")
same <- isTRUE(all.equal(drop_time(sequential), drop_time(parallel_run)))
message(sprintf("Sequential: %.0f s | 2 workers: %.0f s | identical results: %s",
                time_seq[["elapsed"]], time_par[["elapsed"]], same))
cat("Cores (physical/logical):", parallel::detectCores(logical = FALSE), "/", parallel::detectCores(), "\n")
if (!same) stop("Parallel and sequential results differ: do not use execution$workers > 1.", call. = FALSE)
message("OK: set execution$workers in config.yml before run_national_background.R.")
