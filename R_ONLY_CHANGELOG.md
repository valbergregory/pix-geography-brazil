# R-only revision

## Removed from the active workflow

- Python virtual environment and `pip` installation;
- Parquet exchange files dedicated to Python;
- Python prediction-schema contract;
- LightGBM and CatBoost scripts;
- merge of external predictions in `run_pilot.R` and `run_national.R`.

## Added in R

- global Ridge with `glmnet`;
- global XGBoost with `xgboost`;
- sparse one-hot geographic design using `Matrix`;
- direct multi-horizon feature construction;
- temporal-leakage guard at every origin;
- nonnegative inverse transformation for count forecasts;
- coherent bottom-up aggregation;
- XGBoost importance and TreeSHAP;
- official municipality geometry through `geobr`;
- recoverable checkpoints for local, reconciled, and global experiments;
- robust retry of HTTP 500 and related transient BCB failures;
- BCB health check;
- consolidated project diagnostics;
- migration script that archives legacy Python files;
- expanded R tests and a complete RStudio guide.

## Preserved decisions

- payer PF plus payer PJ as the main target;
- no double counting of the receiver perspective;
- stable Mato Grosso territorial unit;
- `N/D` retained for audit and excluded from the hierarchy;
- expanding rolling origins with horizons 1, 3, and 6;
- local time-series benchmarks;
- ETS reconciliation;
- Bai-Perron and PELT diagnostics;
- MASE, RMSSE, MAE, RMSE, and WAPE;
- Newey-West paired-loss comparisons;
- `tinytable`, `modelsummary`, and `fixest` LaTeX outputs;
- PDF and high-resolution PNG figures;
- Quarto/TinyTeX manuscript rendering.
