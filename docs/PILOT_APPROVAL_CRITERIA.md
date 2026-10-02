# Critérios de aprovação do piloto (C1–C4)

**Decisão registrada em 2026-10-02 — critérios aprovados pelo autor.**

O piloto (Alagoas = 27, Roraima = 14) só é considerado aprovado quando os quatro
critérios abaixo estiverem em `PASS`. Só então se executa
`run_national_background.R`. A verificação é automática:

```r
source("check_pilot.R")
```

O script lê os alvos do `{targets}` e os arquivos de `output/`, imprime a tabela
PASS/FAIL e grava `output/pilot_approval.csv` (uma linha por verificação) e
`output/pilot_approval.md` (resumo por critério e detalhes). Ele não reexecuta
modelos nem altera resultados.

Regras gerais:

- **dado ausente nunca é PASS**: arquivo, alvo, modelo, estado, horizonte ou
  métrica ausente/não finita conta como falha;
- um critério só é PASS se tiver pelo menos uma verificação e todas forem PASS;
- os limiares ficam em `pilot_approval_thresholds()` (`R/pilot_approval.R`), fora
  do `config.yml`, para que registrá-los não invalide alvos já executados;
- alterar um limiar é decisão do autor e deve ser registrada neste arquivo.

Rótulo do piloto: `pilot_alagoas_roraima`. Horizontes: os de
`analysis.horizons` (1, 3 e 6). Benchmark: `reporting.benchmark_model`
(`seasonal_naive`).

## C1. Execução

O piloto roda até o fim sem erros; avisos registrados e explicados.

| Verificação | Regra operacional | Fonte |
|---|---|---|
| alvos construídos | todo alvo de `targets::tar_manifest()` tem metadados | `targets::tar_meta()` |
| sem erros | coluna `error` vazia em todos os alvos | `targets::tar_meta()` |
| avisos explicados | todo alvo com `warnings` não vazio aparece, com explicação não vazia, em `docs/pilot_warning_explanations.csv` (colunas `target,explanation`) | `targets::tar_meta()` + CSV |
| escopo | `scope_label == "pilot_alagoas_roraima"` | `targets::tar_read(scope_label)` |

O CSV de explicações é preenchido pelo autor depois de ler cada aviso; o
`check_pilot.R` lista o texto de cada aviso em `output/pilot_approval.md`.

## C2. Integridade geográfica e hierárquica

| Verificação | Regra operacional | Fonte |
|---|---|---|
| lacunas | 0 linhas | `output/analysis_panel_calendar_gaps.csv` |
| geografia estável | estados observados = {14, 27}; chave (mês, município estável) única; todo município estável presente em todos os meses; cada município estável com uma única UF e uma única região | `targets::tar_read(scoped_panel)` |
| soma da hierarquia | para cada modelo, origem e horizonte, o valor observado de cada UF = soma dos municípios; região = soma das UFs; Brasil = soma das regiões, com \|agregado − soma\| ≤ 1e-6 × max(1, \|agregado\|) | `output/forecast_error_rows_pilot_alagoas_roraima.rds` (coluna `actual`) |
| mapas | `forecast_map_files` contém figura `figure_forecast_gain_map_*` (PDF/PNG) existente e **não** contém o marcador `forecast_gain_map_unavailable_*` | `targets::tar_read(forecast_map_files)` |

No piloto, falha de mapa é aviso no `{targets}`, mas reprova C2.

## C3. Desempenho preditivo

Na avaliação por origem móvel, os modelos globais superam o benchmark ingênuo
sazonal em pelo menos uma métrica de escala livre na maioria dos horizontes,
para os dois estados.

- Modelos globais: **a partir de 02/10/2026 (decisão do autor, após o 2º piloto),
  só o modelo global principal, `xgboost_global_bottom_up`, decide o C3** e
  precisa passar em **cada** estado. O `ridge_global_bottom_up` continua sendo
  avaliado e aparece no relatório como `C3-info` (modelo de comparação), sem
  bloquear a aprovação. Versão original (até 02/10): cada modelo global
  precisava passar em cada estado.
- Unidade: nível municipal, por UF (27 e 14), por horizonte.
- Pareamento: só entram pares (município, origem, horizonte) presentes no modelo
  global e no `seasonal_naive`, com escala sazonal válida para ambos.
- Métricas: MASE e RMSSE com as mesmas escalas sazonais de
  `summarise_forecast_accuracy()` (escala calculada apenas na janela de treino).
- Vitória no horizonte h: MASE_global < MASE_snaive **ou**
  RMSSE_global < RMSSE_snaive, e pelo menos 90% dos pares com escala válida.
- Aprovação: vitórias em pelo menos ⌊H/2⌋ + 1 horizontes (2 de 3).

Lacuna atendida: o pipeline só resumia as métricas por nível hierárquico, não por
UF. O cálculo por UF foi implementado em
`paired_scale_free_accuracy_by_state()` (`R/pilot_approval.R`), sem alterar as
métricas do artigo.

## C4. Reconciliação

A previsão reconciliada não piora a previsão agregada (UF/Brasil) em relação à
não reconciliada além de uma margem pequena pré-definida, e as previsões
reconciliadas são coerentes.

- Não reconciliada: `ets` (lote local). Reconciliada principal: `ets_wls`
  (MinT-WLS). `ets_bottom_up` entra apenas na verificação de coerência.
- Níveis: `state` e `national`; cada horizonte separadamente; pares
  (série, origem, horizonte) comuns aos dois modelos.
- Regra: MASE_ets_wls / MASE_ets ≤ 1,05 **e** RMSSE_ets_wls / RMSSE_ets ≤ 1,05
  em todos os horizontes e nos dois níveis (margem de 5%).
- Coerência: para `ets_wls`, `ets_bottom_up` e os `*_global_bottom_up`, as
  previsões satisfazem município→UF→região→Brasil com a mesma tolerância de C2
  (1e-6 relativa).
- Fonte: `output/forecast_error_rows_pilot_alagoas_roraima.rds`.

No piloto, cada região contém uma única UF (AL no Nordeste, RR no Norte); por
isso o nível regional é coberto pela coerência, mas não é avaliado separadamente
quanto à acurácia.
