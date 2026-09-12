r_directory <- normalizePath(
  file.path("..", "..", "R"),
  winslash = "/",
  mustWork = TRUE
)

for (file in sort(list.files(
  r_directory,
  pattern = "[.]R$",
  full.names = TRUE
))) {
  source(file, local = TRUE)
}

test_config <- function() {
  list(
    quality = list(
      require_complete_panel = TRUE
    ),
    geography = list(
      unidentified_key = "N/D",
      stable_mt_key = "MT_STABLE",
      stable_mt_name = "Stable Mato Grosso area",
      stable_mt_codes = c(5101837, 5106240, 5107925)
    )
  )
}

global_test_config <- function() {
  list(
    analysis = list(
      horizons = c(1L, 3L, 6L),
      seasonal_period = 12L,
      initial_window_months = 12L,
      origin_step_months = 1L
    ),
    models = list(
      global = list(
        lags = c(1L, 2L, 3L),
        rolling_windows = c(3L, 6L),
        optional_covariates = character(),
        target_transform = "log1p",
        ridge = list(enabled = TRUE, lambda = 1),
        xgboost = list(
          enabled = TRUE,
          nrounds = 2L,
          eta = 0.1,
          max_depth = 2L,
          min_child_weight = 1,
          subsample = 1,
          colsample_bytree = 1,
          lambda = 1,
          alpha = 0
        )
      )
    ),
    execution = list(
      random_seed = 1L,
      parallel_threads = 1L,
      resume = FALSE,
      shap_sample_rows = 10L
    )
  )
}

synthetic_pix_raw <- function() {
  tibble::tibble(
    AnoMes = c(202301L, 202301L, 202302L, 202302L),
    Municipio_Ibge = c(5106240L, 5107925L, 5106240L, 5107925L),
    Municipio = c("Nova Ubirata", "Sorriso", "Nova Ubirata", "Sorriso"),
    Estado_Ibge = 51L,
    Estado = "Mato Grosso",
    Sigla_Regiao = "CO",
    Regiao = "Centro-Oeste",
    VL_PagadorPF = c(100, 200, 110, 210),
    QT_PagadorPF = c(10, 20, 11, 21),
    VL_PagadorPJ = c(50, 60, 55, 65),
    QT_PagadorPJ = c(5, 6, 5, 7),
    VL_RecebedorPF = 999,
    QT_RecebedorPF = 999,
    VL_RecebedorPJ = 999,
    QT_RecebedorPJ = 999,
    QT_PES_PagadorPF = c(4, 8, 4, 9),
    QT_PES_PagadorPJ = c(2, 3, 2, 3),
    QT_PES_RecebedorPF = 999,
    QT_PES_RecebedorPJ = 999
  )
}
