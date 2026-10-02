# RETOMAR AQUI — Pix (estado em 02/10/2026)

Leia primeiro. Resume o que foi feito na sessão de 02/10 e o que falta.

## Onde está
- Pasta local do autor: `D:\R - Projetos\pix-geography-r` (RStudio, R **4.4.3** — trocar em
  Tools → Global Options → General → R version, se ainda não trocou).
- Dados: snapshot congelado de 30/08/2026 (`data/raw/pix_municipality_20260830T144952Z.parquet`),
  porque a API do BCB devolveu HTTP 500 em todas as chamadas em 02/10 (`config.yml: bcb.frozen_snapshot`).

## Decisões de 02/10 (todas em AUDIT_DECISIONS.md)
1. Critérios de aprovação do piloto C1–C4 (`docs/PILOT_APPROVAL_CRITERIA.md`, `check_pilot.R`).
2. Snapshot congelado de 30/08 (API do BCB fora).
3. Exclusão de 2401305 Campo Grande (RN) e 2405306 Januário Cicco (RN): só existem no BCB a partir de 2025-04.
4. Ridge com lambda por validação temporal (`lambda: "temporal_cv"`), após o Ridge perder para o ingênuo em AL.
5. Correções de código: `export_fixest_latex` (etable sem do.call e sem `...`).

## Resultado do 1º piloto (antes da decisão 4)
- C2 PASS (117 municípios × 70 meses; hierarquia coerente; mapas OK).
- C4 PASS (reconciliação não piora UF/Brasil; previsões coerentes).
- C3 FAIL só pelo Ridge em AL (0/3 horizontes); XGBoost venceu em AL e RR.
- C1 FAIL: erro na tabela de confiabilidade (corrigido) + avisos.

## Próximos passos (na ordem)
1. Terminal: `git pull` (último commit deve conter "Ridge com lambda por validação temporal").
2. Console: `targets::tar_make()` (reestima modelos globais com o novo lambda e refaz a tabela).
3. `source("check_pilot.R")` e ler `output/pilot_approval.md`.
4. Avisos pendentes do C1:
   - `config_file`: some ao usar R 4.4.3.
   - `raw_snapshot_files`: já explicado em `docs/pilot_warning_explanations.csv`.
   - `baseline_models` e `local_errors`: **ARIMA falhou em 105/122 séries** — ver a mensagem completa
     (`m <- targets::tar_meta(fields = c(name, warnings)); cat(m$warnings[m$name == "local_errors"])`)
     antes de explicar ou corrigir.
   - `forecast_output_files`: "Removed 3 rows" no gráfico, provavelmente efeito das falhas do ARIMA.
5. Só com C1–C4 = PASS: `run_national_background.R` (horas; o script recusa sem aprovação).
6. Depois: escrever o artigo em `article/manuscript.qmd` (texto é do autor) e `render_article.R`.
   Revista-alvo ainda não definida.
