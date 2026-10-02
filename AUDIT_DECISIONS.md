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
