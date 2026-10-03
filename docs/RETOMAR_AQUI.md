# RETOMAR AQUI — Pix (estado em 03/10/2026)

## Onde está
- Pasta local: `D:\R - Projetos\pix-geography-r` (RStudio, R 4.4.3). Snapshot congelado de 30/08/2026.
- **Piloto APROVADO em 03/10: C1–C4 = PASS** (`output/pilot_approval.md`). ARIMA com urca: 10.614
  previsões por modelo local, nenhuma NA/NaN. C3-info (Ridge perde do ingênuo) é só informativo.
- **Rodada nacional iniciada em 03/10** (`run_national_background.R`, Background Job) com
  `execution: workers: 13` no `config.yml` local (14 núcleos físicos, ≥ 64 GB). Estimativa 10–12 h.
- Decisões de 02–03/10: todas em AUDIT_DECISIONS.md (snapshot, exclusão RN, ridge temporal_cv,
  XGBoost principal, urca, avisos do local_errors, paralelização).

## Acompanhar o nacional
```r
f <- list.files("data/processed/checkpoints", "progress.log", recursive = TRUE, full.names = TRUE)
for (x in f) { cat("\n==", x, "\n"); cat(tail(readLines(x), 5), sep = "\n") }
```
29 origens no local (ARIMA) e 29 na reconciliação. Se cair: rodar o mesmo Job de novo (checkpoints).
Erro de memória: baixar `workers` e rodar de novo.

## Ao terminar
1. Guardar a lista de arquivos impressa no fim e mandar para a conversa.
2. Ler os resultados na ordem das perguntas do Artigo F (precisão global × local; reconciliação; confiabilidade).
3. `renv::status()` ainda acusa "out-of-sync": rever com calma (não usar `renv::restore()`).

## Programa de pesquisa (proposta, aguardando o autor)
`docs/PROGRAMA_DE_PESQUISA.md`: o repositório hoje é o **Artigo F (previsão)**; propostos mais dois
artigos complementares — **Artigo 2 (banking deserts / leapfrogging × conectividade; P1 + P2 aprovadas
como centrais em 03/10)** e **Artigo 1 (difusão espacial; decidir após descritivas)**. Covariáveis ainda
NÃO implementadas: aguardam aprovação do programa e entram num projeto `targets` separado.
