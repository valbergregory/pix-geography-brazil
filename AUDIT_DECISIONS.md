# Decisões sobre os pareceres externos

As recomendações foram comparadas com o código e incorporadas apenas quando
confirmadas pelo contrato do projeto ou por um risco reproduzível.

## Incorporadas

- ampliar testes de extração, geografia, calendário e métricas;
- impedir imputação silenciosa de lacunas como zero;
- proteger MASE/RMSSE contra denominadores nulos;
- melhorar hashes de checkpoints e proveniência dos artefatos;
- integrar modelos e relatórios ao `targets`;
- usar piloto com dois estados de regiões diferentes;
- validar e armazenar em cache a malha municipal;
- produzir análise explícita de heterogeneidade da confiabilidade preditiva.

## Não incorporadas automaticamente

- substituir o endpoint oficial do BCB por outro sem confirmação;
- interpretar `DataBase = 20232` obrigatoriamente como uma data `YYYYMM`;
- preencher observações ausentes com zero;
- reduzir o limiar de cobertura municipal sem evidência;
- exigir uma matriz espacial W quando o delineamento atual é de previsão
  hierárquica, não de econometria espacial;
- usar `devtools::test()` em um projeto que não é um pacote R;
- recriar um ambiente com `renv::init()` sobre um projeto existente sem verificar
  se há lockfile;
- forçar `st_union()` manual quando a sumarização do objeto `sf` já dissolve as
  geometrias agrupadas.

O parâmetro da API continua centralizado e deve ser validado com
`probe_bcb_database()` antes de congelar o snapshot usado no artigo.

## Critérios de aprovação do piloto (2026-10-02, aprovado pelo autor)

Os critérios C1–C4 (execução, integridade geográfica e hierárquica, desempenho
preditivo contra o ingênuo sazonal e reconciliação) estão operacionalizados em
`docs/PILOT_APPROVAL_CRITERIA.md`, com métrica, limiar e fonte de cada
verificação. `check_pilot.R` os avalia e grava `output/pilot_approval.csv` e
`output/pilot_approval.md`; dado ausente conta como FAIL. A execução nacional só
deve começar com C1–C4 = PASS.

## 2026-10-02 — Snapshot congelado de 30/08/2026 para o piloto

- O recurso `TransacoesPixPorMunicipio` do BCB devolveu HTTP 500 em todas as
  chamadas testadas em 02/10/2026 (`diagnose_bcb3.R`: com e sem `$skip`, com
  `DataBase` 20232, 202306 e 202312, JSON e CSV). Não é defeito do código.
- A extração completa de 30/08/2026 existe localmente
  (`data/raw/pix_municipality_20260830T144952Z.parquet` + `.json`).
- Nova opção `bcb.frozen_snapshot` em `config.yml`: quando preenchida, o alvo
  `raw_snapshot_files` reutiliza esse Parquet (conferindo o SHA-256 gravado no
  `.json`) em vez de baixar de novo. Deixe `""` para extrair um snapshot novo.
- Consequência: o piloto e, se aprovado, a análise nacional usam a série
  disponível em 30/08/2026. O mês final da amostra é o registrado no `.json`.

## 2026-10-02 — Exclusão de dois municípios do RN (decisão do autor)

- O painel de geografia estável tinha 106 células município-mês ausentes, todas
  em 2401305 (Campo Grande, RN) e 2405306 (Januário Cicco, RN): os dois códigos
  só aparecem na série do BCB a partir de 2025-04, sem código antigo que termine
  em 2025-03. As transações anteriores foram registradas em outra rubrica
  (provavelmente N/D ou homônimo), então preencher com zero seria incorreto.
- Decisão do autor: excluir os dois municípios do painel de análise via
  `geography.excluded_municipality_codes` em `config.yml`
  (`exclude_municipalities()`, aplicada antes da agregação). Eles saem também
  dos agregados de UF, região e Brasil, o que mantém a hierarquia coerente.
- Peso desprezível (2 de 5.570 municípios); não afeta o piloto (AL e RR).
  O artigo deve registrar a exclusão em nota.
- A validação bruta (`minimum_identified_units = 5568`) continua sobre os dados
  originais, antes da exclusão.

## 2026-10-02 — Ridge com lambda por validação temporal (decisão do autor, pós-piloto)

- No primeiro piloto (02/10), `ridge_global_bottom_up` perdeu para o ingênuo
  sazonal em AL nos 3 horizontes (C3 = FAIL), com `lambda = 1.0` fixo e sem
  seleção. O XGBoost venceu nas duas UFs.
- Decisão do autor (opção a): escolher `lambda` por validação temporal em cada
  origem — últimos `validation_months` (6) da janela de estimação, só rótulos
  com mês ≤ origem (sem look-ahead), MAE na escala original; depois reestimar na
  janela inteira com o lambda escolhido. `config.yml`: `lambda: "temporal_cv"`.
- **Mudança feita depois de ver o piloto**: registrar no artigo. O critério C3
  NÃO foi alterado; o piloto será refeito com o mesmo critério.

## 2026-10-02 — XGBoost como modelo global principal; Ridge como comparação (decisão do autor)

- 2º piloto (lambda do Ridge por validação temporal): o Ridge perdeu para o
  ingênuo sazonal em AL (0/3 horizontes) e em RR (1/3). O XGBoost venceu nos
  3 horizontes nas duas UFs. C2 e C4 continuaram PASS.
- Decisão do autor (opção b): o C3 passa a exigir só o modelo global principal
  (`xgboost_global_bottom_up`); o Ridge segue estimado e reportado como modelo de
  comparação (`C3-info` no relatório de aprovação).
- **Mudança de critério feita depois de ver o piloto**: registrar no artigo.
  Leitura substantiva para o texto: o modelo global linear não supera o ingênuo
  sazonal; a não linearidade da difusão do Pix parece essencial.
- O lambda por validação temporal foi mantido (voltar a `lambda = 1` por ter dado
  número melhor seria escolher o resultado).

## 2026-10-02 — ARIMA nulo em todas as séries: faltava o pacote `urca`

- No piloto, `baseline_models` registrou "105 errors (1 unique) encountered for
  arima": o ARIMA ficou nulo em 105 de 105 séries. Causa: o `fable::ARIMA()` usa o
  pacote `urca` nos testes de raiz unitária, e ele não estava instalado nem
  listado. Ajustado manualmente numa série, o modelo estima normalmente
  (ARIMA(1,1,2)(1,0,1)[12] com drift).
- Correção: `urca` entra em `required_packages` (R/setup.R) e no `renv.lock`.
  Os resultados do ARIMA dos pilotos anteriores não valem; o piloto é refeito.
