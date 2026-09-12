# Publication output plan

## Main-text tables and framework boxes

| File | Role in the article |
|---|---|
| `table_data_coverage.tex` | Data source, period, panel size, and stable geography |
| `quadro_experimental_design.tex` | Frozen forecasting and validation design |
| `table_forecast_accuracy_municipal.tex` | Central municipal comparison by horizon |
| `table_relative_gain.tex` | Percentage improvement over seasonal naive |
| `table_forecast_accuracy_hierarchy.tex` | Accuracy after geographic aggregation and reconciliation |
| `table_newey_west_comparison.tex` | Paired loss comparison with HAC uncertainty |
| `table_negative_predictions.tex` | Nonnegativity diagnostic |
| `table_scaled_metric_coverage.tex` | Valid and excluded seasonal scaling denominators |
| `table_runtime.tex` | Total and per-origin computation time |
| `table_global_model_parameters_national.tex` | Global R-model execution scope and frozen parameters |
| `table_xgboost_feature_importance_national.tex` | XGBoost gain and split importance |
| `table_xgboost_shap_national.tex` | Mean absolute TreeSHAP contributions |
| `table_forecast_reliability_national.tex` | Municipality-level determinants of scaled forecast error |

## Main-text figures

| File | Role in the article |
|---|---|
| `figure_pix_evolution_national.pdf` | National diffusion of outgoing Pix transactions |
| `figure_pix_evolution_regions.pdf` | Macroregional heterogeneity |
| `figure_structural_breaks.pdf` | Descriptive Bai-Perron and PELT break dates |
| `figure_accuracy_by_horizon.pdf` | Accuracy profile as horizon increases |
| `figure_relative_gain.pdf` | Model gains relative to seasonal naive |
| `figure_error_distribution.pdf` | Distribution and heterogeneity of municipal errors |
| `figure_forecast_gain_map_<scope>_h*.pdf` | Spatial distribution of gains after IBGE geometry is joined |
| `figure_xgboost_shap_national.pdf` | Global R-model predictive attribution |

Every figure is also written as a 320-dpi PNG for inspection. LaTeX must use
the PDF version because it is vector-based.

## Appendix outputs

- full accuracy table for every hierarchy level;
- zero-scale and negative-forecast diagnostics;
- computation time summary;
- model-specific hyperparameters exported by the R workflow;
- full national structural-break table.

## Econometric tables

Use `export_modelsummary_latex()` for `lm`, `glm`, and other supported model
objects. Use `export_fixest_latex()` for fixed-effects and clustered-standard-
error specifications. No inferential table should be exported with default
IID standard errors when the design requires clustering or HAC correction.
