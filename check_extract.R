# check_extract.R ----------------------------------------------------------
# Baixa a serie completa com o extract_pix.R corrigido e roda, uma a uma,
# as seis validacoes de validate_pix_raw(), reportando TODAS as que falharem
# em vez de parar na primeira.
#
# Rode no Console, na raiz do projeto, DEPOIS de substituir R/extract_pix.R
# e config.yml. Nao escreve nada em disco e nao mexe no targets.

source("R/setup.R")
source("R/config.R")
source("R/extract_pix.R")
source("R/validate_pix.R")

config <- read_project_config("config.yml")

cat("\n=== Download ===\n")
tempo <- system.time(dados <- fetch_all_pix(config))
cat("Tempo: ", round(tempo[["elapsed"]], 1), " s\n", sep = "")

# --------------------------------------------------------------------------
cat("\n=== Panorama ===\n")
# --------------------------------------------------------------------------

cat("linhas            : ", nrow(dados), "\n", sep = "")
cat("colunas           : ", ncol(dados), "\n", sep = "")
cat("AnoMes distintos  : ", length(unique(dados$AnoMes)), "\n", sep = "")
cat("AnoMes minimo     : ", min(dados$AnoMes), "\n", sep = "")
cat("AnoMes maximo     : ", max(dados$AnoMes), "\n", sep = "")
cat("municipios        : ", length(unique(dados$Municipio_Ibge)), "\n", sep = "")
cat("UFs               : ", length(unique(dados$Estado_Ibge)), "\n", sep = "")
cat("Municipio_Ibge NA : ", sum(is.na(dados$Municipio_Ibge)), "\n", sep = "")

cat("\nClasse de Municipio_Ibge: ", class(dados$Municipio_Ibge), "\n", sep = "")
cat("Valores nao numericos em Municipio_Ibge (amostra):\n")
print(utils::head(unique(dados$Municipio_Ibge[
  is.na(suppressWarnings(as.numeric(dados$Municipio_Ibge)))
]), 10))

cat("\nAlagoas (Estado_Ibge == 27):\n")
al <- dados[!is.na(dados$Estado_Ibge) & dados$Estado_Ibge == 27, ]
cat("  linhas: ", nrow(al),
    " | municipios: ", length(unique(al$Municipio_Ibge)),
    " | meses: ", length(unique(al$AnoMes)), "\n", sep = "")

# --------------------------------------------------------------------------
cat("\n=== Cobertura municipal por mes (10 menores) ===\n")
# --------------------------------------------------------------------------

cobertura <- dados |>
  dplyr::filter(!is.na(.data$Municipio_Ibge)) |>
  dplyr::count(.data$AnoMes, name = "municipios_identificados") |>
  dplyr::arrange(.data$municipios_identificados)

print(utils::head(cobertura, 10))
cat("\nA validacao exige no minimo 5568 em TODO mes.\n")

# --------------------------------------------------------------------------
cat("\n=== Validacoes, uma a uma ===\n")
# --------------------------------------------------------------------------

rodar <- function(rotulo, expressao) {
  resultado <- tryCatch(
    {
      force(expressao)
      "OK"
    },
    error = function(condition) paste("FALHOU:", conditionMessage(condition))
  )
  cat(sprintf("  %-28s %s\n", rotulo, resultado))
  invisible(resultado)
}

rodar("schema",             validate_pix_schema(dados))
rodar("continuidade mensal", validate_pix_months(
  dados,
  minimum_months = config$analysis$initial_window_months
))
rodar("chaves unicas",      validate_pix_keys(dados))
rodar("medidas completas",  validate_nonmissing_measures(dados))
rodar("medidas nao negativas", validate_nonnegative_fields(dados))
rodar("cobertura municipal", validate_geographic_coverage(dados))

assign("pix_bruto", dados, envir = globalenv())

cat("\n", strrep("=", 74), "\n", sep = "")
cat("Objeto pix_bruto disponivel no ambiente global.\n")
cat("Se as seis validacoes deram OK, rode:\n")
cat('  targets::tar_invalidate(raw_snapshot_files)\n')
cat('  targets::tar_make()\n')
