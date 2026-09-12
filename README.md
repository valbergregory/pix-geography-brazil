# pix-geography-brazil

Compêndio reproduzível (R, {targets}, {renv}, DuckDB) do manuscrito em desenvolvimento:

> **Forecasting Pix Across Brazil: Global Models and Coherent Geographic Reconciliation**
> Valber Gregory Barbosa Costa Bezerra Santos (UFAL / TJAL)

Pergunta: é possível prever a difusão e o volume do Pix por município, com modelos
globais e reconciliação hierárquica município → UF → região → Brasil, e onde a
previsão é menos confiável? **Situação (2026-09):** pipeline e testes prontos;
extração municipal do BCB, descritivas e quebras estruturais executadas; modelos
globais e artigo ainda não estimados/escritos. Este repositório contém código,
testes e o esqueleto do artigo; a interpretação e o texto são do autor e não
fazem parte do repositório.

![R](https://img.shields.io/badge/R-4.4-276DC3?logo=r) ![targets](https://img.shields.io/badge/pipeline-targets%20%7C%20DuckDB-1f6b73) ![License](https://img.shields.io/badge/code-MIT-green)

## Versão 2 corrigida

Projeto integralmente em R para extrair dados municipais do Pix, construir uma
geografia temporalmente estável, avaliar previsões por origem móvel, reconciliar
a hierarquia município–UF–região–Brasil e produzir tabelas e figuras para LaTeX.

## Fonte dos dados

Os dados de transações Pix são obtidos do serviço oficial de dados abertos do
Banco Central do Brasil (BCB):

- catálogo: <https://dadosabertos.bcb.gov.br/dataset/pix>;
- recurso por município:
  <https://dadosabertos.bcb.gov.br/dataset/pix/resource/268e3bf6-b096-4006-83cd-813697012ece>.

O endpoint e o parâmetro `DataBase` ficam centralizados em `config.yml`. Como a
disponibilidade e o contrato do serviço são externos ao projeto, execute
`diagnose_bcb.R` antes de uma nova extração. O código não transforma falha HTTP
em zero e não troca silenciosamente o parâmetro da API.

## Fluxo recomendado

1. Abra `pix-geography.Rproj` no RStudio.
2. Execute `install_packages.R` como **Background Job**.
3. No Console, carregue o código e rode os testes:

```r
options(error = NULL)
targets::tar_source("R")
testthat::test_dir(
  "tests/testthat",
  reporter = "summary",
  stop_on_failure = FALSE
)
```

4. Execute `diagnose_bcb.R` como Background Job.
5. Com a API disponível, execute `prepare_pilot.R` como Background Job.
6. Execute `run_pilot.R` como Background Job.
7. Confira os resultados em `output/` e execute `render_article.R`.
8. Somente depois da aprovação do piloto, execute
   `run_national_background.R`.

As instruções completas estão em `RSTUDIO_STEP_BY_STEP.md`.

## Principais saídas

- snapshot imutável em `data/raw/`, com metadados e SHA-256;
- painel Parquet e catálogo DuckDB portátil em `data/processed/`;
- métricas e erros por origem em `output/`;
- tabelas LaTeX em `output/tables/`;
- figuras PDF/PNG em `output/figures/`;
- manifestos com SHA-256 em `output/latex/`;
- `session_info_*.txt` para auditoria computacional;
- artigo Quarto em `article/manuscript.qmd`.

## Decisões de integridade

- Lacunas município–mês interrompem o fluxo; nunca são preenchidas
  automaticamente com zero.
- Escalas sazonais nulas são excluídas de MASE/RMSSE e o número de observações
  válidas é informado em `scaled_origins`.
- Checkpoints incorporam hashes dos dados, da configuração e do código crítico.
- O piloto usa dois estados de regiões diferentes: Alagoas (27) e Roraima (14).
- Falhas de mapa são avisos no piloto e erros na execução nacional.
- Modelos globais e artefatos finais fazem parte do DAG do `targets`.

## Reprodutibilidade

O ZIP não traz uma biblioteca binária do Windows. Na primeira execução,
`install_packages.R` inicializa o `renv`, instala as dependências e cria
`renv.lock`. Preserve esse arquivo junto com a versão submetida do artigo.

Para verificar o projeto inteiro sem iniciar a modelagem:

```r
source("check_project.R")
```

Uma indisponibilidade do BCB ou do LaTeX pode aparecer como item de atenção sem
significar erro nos pacotes R ou nos testes unitários.

## Uso de ferramentas de IA

Assistentes de programação foram usados para escrever e revisar código, testes e
documentação sob supervisão do autor. Desenho da pesquisa, escolha dos dados,
estratégia de modelagem, interpretação e texto do manuscrito são do autor. Nenhuma
ferramenta de IA gerou ou alterou resultados.

## Licença

Código: MIT (`LICENSE`). Dados do Banco Central do Brasil: dados abertos, nos termos
da fonte (não redistribuídos aqui; o pipeline os baixa). Ver `LICENSING.md`.

Página do projeto: <https://valbergregory.github.io/pesquisa/pix-geography-brazil/>.
