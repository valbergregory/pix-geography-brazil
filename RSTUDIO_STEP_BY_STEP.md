# Passo a passo completo no RStudio

Este roteiro começa em uma pasta nova. Execute cada etapa na ordem e só avance
quando a verificação indicada estiver correta.

## 1. Descompactar e abrir o projeto

1. Feche o projeto antigo no RStudio.
2. Extraia o ZIP em uma pasta curta, por exemplo
   `D:/R-Projetos/pix-geography-r-v2`.
3. Abra `pix-geography.Rproj`.
4. Confirme no Console:

```r
getwd()
file.exists("config.yml")
file.exists("_targets.R")
file.exists("R/setup.R")
```

Os três resultados de `file.exists()` devem ser `TRUE`.

Se o Console mostrar `Browse[1]>`, digite `Q`, pressione Enter e execute:

```r
options(error = NULL)
```

## 2. Conferir a versão do R

No Console:

```r
R.version.string
getRversion() >= "4.4.0"
```

O segundo comando deve retornar `TRUE`. No Windows, mantenha o RTools compatível
instalado caso algum pacote precise ser compilado a partir do código-fonte.

## 3. Criar o ambiente e instalar os pacotes

No RStudio, vá a **Tools > Jobs > Start Local Job**:

- Script: `install_packages.R`;
- Working directory: Project directory;
- clique em **Start**.

O script cria a biblioteca isolada do `renv`, instala as dependências e grava
`renv.lock`. A instalação de `duckdb`, `arrow`, `sf` e `xgboost` pode demorar.

Ao terminar, reinicie a sessão em **Session > Restart R**. Depois rode:

```r
source("R/setup.R")
check_required_packages()
renv::status()
```

Resultado esperado:

- `check_required_packages()` termina sem mensagem de erro;
- `renv::status()` informa que o projeto está em estado consistente.

Se os pacotes estiverem instalados, mas ainda não registrados no lockfile:

```r
renv::snapshot(prompt = FALSE)
renv::status()
```

Não use `renv::restore()` para substituir deliberadamente versões já aprovadas,
a menos que o `renv.lock` seja a referência que você deseja restaurar.

## 4. Carregar o código e executar os testes

No Console, exatamente nesta ordem:

```r
options(error = NULL)
targets::tar_source("R")

testthat::test_dir(
  "tests/testthat",
  reporter = "summary",
  stop_on_failure = FALSE
)
```

O resultado correto termina em `DONE`, sem `FAIL` e sem `ERROR`. O aviso de que
`testthat` foi compilado em uma revisão próxima do R não representa falha.

Confirme também que o grafo pode ser interpretado:

```r
manifesto <- targets::tar_manifest(
  fields = tidyselect::any_of(c("name", "command"))
)
print(manifesto, n = Inf)
nrow(manifesto)
```

## 5. Diagnosticar a API do Banco Central

Execute `diagnose_bcb.R` em **Tools > Jobs > Start Local Job**. O script testa os
parâmetros documentados no `config.yml` e grava `output/bcb_database_probe.csv`.

Alternativamente, no Console:

```r
targets::tar_source("R")
probe_bcb_database()
check_bcb_connection()
```

Só avance se pelo menos uma linha do diagnóstico tiver `status = "available"`.
Se aparecer HTTP 500, 502, 503 ou 504:

- não reinstale os pacotes;
- não apague `_targets/`;
- não converta a resposta em zeros;
- tente novamente mais tarde.

Se o candidato alternativo funcionar e o configurado não, confira o campo
`observed_AnoMes` antes de alterar `bcb.database_parameter` em `config.yml`. A
mudança deve ser consciente e registrada.

## 6. Preparar o piloto

Execute `prepare_pilot.R` como **Background Job**. Esse job:

- baixa e congela o snapshot do BCB;
- valida esquema, meses, chaves, valores e cobertura municipal;
- constrói o painel de geografia estável;
- rejeita lacunas município–mês em vez de preenchê-las com zero;
- cria o Parquet processado e o catálogo DuckDB;
- gera as estatísticas e figuras descritivas;
- prepara a hierarquia do piloto de Alagoas e Roraima.

Depois confira no Console:

```r
targets::tar_meta(fields = c(name, error, warnings, seconds))
targets::tar_outdated()

file.exists("data/processed/pix_stable_municipality.parquet")
file.exists("data/processed/pix_geography.duckdb")
file.exists("output/municipal_coverage_by_month.csv")
file.exists("output/analysis_panel_calendar_gaps.csv")
```

Os quatro `file.exists()` devem ser `TRUE`. A tabela de lacunas deve existir e
ter zero linhas de dados:

```r
gaps <- readr::read_csv(
  "output/analysis_panel_calendar_gaps.csv",
  show_col_types = FALSE
)
nrow(gaps)
```

O resultado deve ser `0`.

## 7. Rodar os modelos do piloto

Execute `run_pilot.R` como **Background Job**. O job roda:

- naive, naive sazonal, drift, ETS e ARIMA;
- ETS reconciliado;
- Ridge global e XGBoost global, integralmente em R;
- agregação bottom-up coerente;
- validação por origem móvel nos horizontes 1, 3 e 6;
- análise municipal de confiabilidade dos erros;
- tabelas LaTeX, figuras, mapas e manifestos.

O processo pode levar bastante tempo. Checkpoints permitem retomar uma execução
interrompida, mas só são reutilizados quando dados, configuração e código crítico
continuam iguais.

Verifique:

```r
targets::tar_read(scope_label)
targets::tar_read(forecast_output_files)
targets::tar_read(global_model_artifact_files)
targets::tar_read(reliability_output_files)
targets::tar_read(forecast_map_files)

file.exists("output/forecast_accuracy_pilot_alagoas_roraima.csv")
file.exists("output/forecast_error_rows_pilot_alagoas_roraima.rds")
file.exists("output/tables/table_forecast_reliability_pilot_alagoas_roraima.tex")
```

Os três últimos resultados devem ser `TRUE`. O mapa do piloto pode gerar aviso
se a malha remota do `geobr` estiver indisponível; na execução nacional isso é
tratado como erro para impedir uma entrega incompleta.

Para tentar novamente apenas o mapa depois que o serviço voltar:

```r
targets::tar_invalidate(forecast_map_files)
targets::tar_make(names = tidyselect::any_of("forecast_map_files"))
```

Confira as métricas:

```r
accuracy <- readr::read_csv(
  "output/forecast_accuracy_pilot_alagoas_roraima.csv",
  show_col_types = FALSE
)
print(accuracy, n = Inf)
summary(accuracy$MASE)
summary(accuracy$RMSSE)
accuracy |>
  dplyr::select(.model, horizon, hierarchy_level, series_origins, scaled_origins)
```

`scaled_origins` informa quantas observações tinham escala sazonal válida. Ele
pode ser menor que `series_origins` quando uma série de treinamento é constante.

## 8. Verificar tabelas, figuras e proveniência

```r
list.files("output/tables", full.names = TRUE)
list.files("output/figures", full.names = TRUE)
list.files("output/latex", full.names = TRUE)
list.files("output", pattern = "session_info", full.names = TRUE)
```

Os manifestos em `output/latex/` registram o caminho e SHA-256 de cada artefato.
Os arquivos `session_info_*.txt` registram o R, o sistema, a configuração e o
hash do `renv.lock`.

As tabelas são exportadas principalmente com `tinytable` e `modelsummary`, e os
modelos econométricos com `fixest`. Todos produzem LaTeX diretamente.

## 9. Instalar LaTeX e compilar o artigo

No Console:

```r
source("R/setup.R")

if (!tinytex::is_tinytex()) {
  tinytex::install_tinytex()
}

install_latex_dependencies()
check_latex_environment()
```

Reinicie o RStudio se o TinyTeX tiver acabado de ser instalado. Em seguida,
execute `render_article.R` como Background Job.

Verifique:

```r
list.files("output/article", pattern = "[.]pdf$", recursive = TRUE, full.names = TRUE)
```

## 10. Rodar a análise nacional

Só execute depois de revisar o piloto. Inicie
`run_national_background.R` como Background Job. Esse script registra a
confirmação e chama o fluxo nacional protegido.

Não use `source("run_national.R")` sem antes definir explicitamente:

```r
Sys.setenv(PIX_CONFIRM_NATIONAL = "yes")
```

A análise nacional pode exigir horas e bastante espaço em disco. A configuração
padrão usa um único thread para evitar sobrecarga no computador; altere
`execution.parallel_threads` apenas se houver memória suficiente.

Ao terminar:

```r
Sys.unsetenv("PIX_CONFIRM_NATIONAL")
Sys.unsetenv("PIX_FULL_RUN")

targets::tar_read(scope_label)
targets::tar_read(forecast_output_files)
targets::tar_read(global_model_artifact_files)
targets::tar_read(reliability_output_files)
```

O rótulo deve ser `"national"`.

## 11. Auditoria final do projeto

Execute `check_project.R` como Background Job ou, no Console:

```r
source("check_project.R")
```

O diagnóstico é salvo em `output/project_diagnostics.csv`. Depois congele o
ambiente utilizado no artigo:

```r
renv::snapshot(prompt = FALSE)
renv::status()
```

Arquive juntos: código, `renv.lock`, snapshot Parquet e JSON de metadados,
resultados, artigo e os arquivos de sessão/proveniência.

## 12. Comandos úteis de recuperação

Ver o erro de um alvo:

```r
targets::tar_meta(fields = c(name, error, warnings)) |>
  dplyr::filter(!is.na(error) | !is.na(warnings))
```

Retomar após uma interrupção:

```r
Sys.setenv(PIX_FULL_RUN = "false")
targets::tar_make(names = tidyselect::any_of(c(
  "forecast_output_files",
  "global_model_artifact_files",
  "reliability_output_files",
  "forecast_map_files"
)))
```

Reexecutar apenas a partir de uma mudança legítima nos dados ou no código:

```r
targets::tar_outdated()
targets::tar_make()
```

Não apague o cache inteiro como primeira tentativa. Primeiro leia o erro e
verifique a API, o espaço em disco e o `renv::status()`.
