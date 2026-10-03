# Artigo 2 — contrato dos insumos (`article2/data/inputs/`)

Um CSV por tema, uma linha por município, `municipality_code` = código IBGE de 7 dígitos (sem NA, sem duplicatas).
Valores ausentes = NA (nunca zero). Os três municípios do MT estáveis são somados e os dois do RN excluídos
automaticamente (regras lidas de `config.yml` do Artigo F). **Fontes e anos: status "a verificar" — nenhuma foi
conferida (o ambiente de nuvem não alcança as fontes); o autor baixa e confirma definição e ano.**

| Arquivo | Colunas | Fonte pretendida | Referência |
|---|---|---|---|
| `population.csv` | `municipality_code, population_total, population_adult` | IBGE (estimativa 2020 ou Censo) | a verificar |
| `banking.csv` | `municipality_code, branches` | BCB/ESTBAN, agências 2019 | a verificar |
| `connectivity.csv` | `municipality_code, broadband_accesses, households, coverage_4g_share` | Anatel 2019–2020; domicílios IBGE | a verificar |

`coverage_4g_share` em [0, 1]. Não há controles ainda (PIB, urbanização, Auxílio Emergencial): entram depois da checagem.

## Como rodar (RStudio, pasta `article2/` como diretório de trabalho)
1. Gerar o painel do Artigo F (`data/processed/pix_stable_municipality.parquet`).
2. Colocar os três CSVs em `article2/data/inputs/`.
3. `setwd("article2"); targets::tar_make()` → `article2/output/*.csv`
   (`adoption_audit_*`, `exposure`, `feasibility_*`).
4. Testes: `testthat::test_dir("article2/tests/testthat")`.
