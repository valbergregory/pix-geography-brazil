# Alterações da versão 2 corrigida

- Pipeline de modelagem e relatórios integrado ao DAG do `targets`.
- Piloto ampliado para Alagoas e Roraima.
- Diagnóstico explícito do parâmetro `DataBase` da API do BCB.
- Limite finito de paginação e detecção de página repetida.
- Snapshot Parquet com SHA-256 e metadados de extração.
- Validação mensal de cobertura e de lacunas município–mês.
- Lacunas nunca são imputadas automaticamente como zero.
- MASE e RMSSE protegidos contra escala sazonal nula.
- Checkpoints vinculados a hashes dos dados e do código crítico.
- Malha `sf` validada, reparada quando possível e armazenada em cache.
- Catálogo DuckDB com tabela materializada e sem dependência do caminho Parquet.
- Análise econométrica de confiabilidade dos erros de previsão.
- Manifestos dos resultados com SHA-256 e arquivos `sessionInfo()`.
- Testes adicionais de extração, geografia, calendário e métricas.
- Manual do RStudio reescrito para o novo fluxo.
