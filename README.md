# pix-geography-brazil

Código do estudo *Forecasting Pix Across Brazil: Global Models and Coherent
Geographic Reconciliation* (Valber Gregory Barbosa Costa Bezerra Santos,
UFAL / TJAL). Projeto em R, com `{targets}`, `{renv}` e DuckDB.

Pergunta de pesquisa: modelos globais de previsão melhoram as previsões
municipais de atividade do Pix em relação a benchmarks estatísticos locais, e
quais estratégias de reconciliação preservam acurácia e coerência geográfica na
hierarquia município → UF → região → Brasil? O estudo também examina em quais
territórios a previsão é menos confiável.

## Dados e fontes

- **Transações Pix por município** — Banco Central do Brasil, serviço de dados
  abertos (OData/Olinda), série mensal a partir de novembro de 2020.
  Catálogo: <https://dadosabertos.bcb.gov.br/dataset/pix>; recurso
  `TransacoesPixPorMunicipio`. O endpoint e os parâmetros da consulta ficam em
  `config.yml` (seção `bcb`). Os dados não são redistribuídos neste
  repositório: o pipeline os baixa, grava um snapshot Parquet com metadados e
  SHA-256 em `data/raw/` e pode reutilizar um snapshot congelado
  (`bcb.frozen_snapshot`).
- **Malha municipal** — IBGE, obtida pelo pacote `geobr`
  (`geography.geometry_year` em `config.yml`) e armazenada em cache em
  `data/processed/`.

Variável-alvo: `payer_count` = `QT_PagadorPF` + `QT_PagadorPJ` (transações
Pix enviadas, perspectiva do pagador). O dicionário de dados
(`data_dictionary.csv`) descreve cada campo da fonte, o campo correspondente
no projeto, unidade, periodicidade, nível geográfico, papel na análise e
status de verificação; as linhas de IBGE, Anatel e MTE listadas ali estão
marcadas como pendentes e não entram no pipeline atual.

Decisões sobre o tratamento dos dados (unidade territorial estável em Mato
Grosso, municípios excluídos do painel, snapshot congelado, lacunas
município-mês nunca preenchidas com zero) estão em `config.yml` e em
`AUDIT_DECISIONS.md`.

## Estrutura

```
.
├── _targets.R                   # DAG: extração → validação → painel → modelos → relatórios
├── config.yml                   # fonte, qualidade, horizontes, modelos, execução, geografia, relatórios
├── data_dictionary.csv          # dicionário de dados (fonte, campo, definição, unidade, papel, status)
├── R/
│   ├── setup.R                  # pacotes exigidos
│   ├── config.R                 # leitura e validação de config.yml
│   ├── extract_pix.R            # extração do BCB (OData), retentativas, snapshot
│   ├── validate_pix.R           # esquema, meses, chaves, valores, cobertura municipal
│   ├── build_targets.R          # painel município-mês com geografia estável; Parquet
│   ├── geography.R              # malha municipal (geobr), validação e cache
│   ├── duckdb_layer.R           # catálogo DuckDB (tabela pix_stable_municipality)
│   ├── breaks.R                 # quebras estruturais (Bai–Perron, PELT)
│   ├── baselines.R              # naive, naive sazonal, drift, ETS, ARIMA (fable)
│   ├── reconciliation.R         # ETS reconciliado: bottom-up e MinT-WLS
│   ├── global_models.R          # Ridge (glmnet) e XGBoost globais; agregação bottom-up
│   ├── rolling_origin.R         # avaliação por origem móvel, checkpoints, paralelização
│   ├── metrics.R                # MASE, RMSSE, MAE, RMSE, WAPE
│   ├── comparisons.R            # comparações pareadas de perda (Newey–West)
│   ├── econometrics.R           # regressão de confiabilidade dos erros (fixest)
│   ├── pilot_approval.R         # critérios C1–C4 do piloto
│   └── reporting_*.R            # tabelas (tinytable/modelsummary), figuras, mapas, manifestos
├── tests/testthat/              # testes de extração, geografia, métricas, modelos globais, piloto
├── docs/
│   ├── PILOT_APPROVAL_CRITERIA.md       # critérios C1–C4, métricas, limiares e fontes
│   ├── pilot_warning_explanations.csv   # avisos do piloto com explicação
│   ├── PROGRAMA_DE_PESQUISA.md          # programa de pesquisa e relação com outros artigos
│   └── RETOMAR_AQUI.md                  # notas de retomada do autor
├── AUDIT_DECISIONS.md           # decisões registradas sobre dados, modelos e execução
├── RSTUDIO_STEP_BY_STEP.md      # roteiro completo de execução no RStudio
├── VERSION_2_CHANGELOG.md, R_ONLY_CHANGELOG.md
├── install_packages.R, diagnose_bcb.R, prepare_pilot.R, run_pilot.R,
│   check_pilot.R, run_national_background.R, run_national.R,
│   render_article.R, check_project.R, check_parallel.R, check_extract.R
├── renv.lock                    # versões dos pacotes (R 4.4.3)
├── data/raw/                    # snapshot Parquet + JSON de metadados (não versionados)
├── data/processed/              # pix_stable_municipality.parquet, pix_geography.duckdb, checkpoints
└── output/                      # tables/, figures/, latex/ (manifestos SHA-256), article/, session_info_*.txt
```

Banco de dados: `data/processed/pix_geography.duckdb` contém a tabela
`pix_stable_municipality`, materializada a partir do Parquet de mesmo nome
(painel município-mês com chaves de UF e região).

## Como reproduzir

Requisitos: R >= 4.4 (lockfile gerado com R 4.4.3), RStudio, e TinyTeX/LaTeX
apenas para compilar o artigo. Pacotes em `R/setup.R` e `renv.lock`.

```r
# 1. abrir pix-geography.Rproj e instalar o ambiente (Background Job)
source("install_packages.R")

# 2. testes
targets::tar_source("R")
testthat::test_dir("tests/testthat", reporter = "summary")

# 3. API do BCB, piloto (Alagoas e Roraima) e critérios C1–C4
source("diagnose_bcb.R")
source("prepare_pilot.R")
source("run_pilot.R")
source("check_pilot.R")            # grava output/pilot_approval.{csv,md}

# 4. execução nacional (só com C1–C4 = PASS) e artigo
source("run_national_background.R")
source("render_article.R")         # article/manuscript.qmd (não versionado)

# diagnóstico geral do projeto
source("check_project.R")
```

Variáveis de ambiente usadas pelos scripts: `PIX_FULL_RUN` (escopo nacional vs.
piloto) e `PIX_CONFIRM_NATIONAL` (confirmação exigida por `run_national.R`).
Não há credenciais: os dados do BCB são abertos. Semente, número de workers e
demais parâmetros de execução ficam em `config.yml` (`execution`). O roteiro
detalhado está em `RSTUDIO_STEP_BY_STEP.md`.

## Licença

- Código (R, testes, configuração, `_targets.R`): MIT (`LICENSE`).
- Documentação, tabelas e figuras produzidas pelo pipeline: CC BY 4.0.
- Dados do Pix: Banco Central do Brasil, dados abertos, nos termos da fonte;
  não redistribuídos aqui. Malha municipal: IBGE (dados públicos).

Detalhes em `LICENSING.md`.

## Citação

Ver `CITATION.cff`. Página do projeto:
<https://valbergregory.github.io/pesquisa/pix-geography-brazil/>.
