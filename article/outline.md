# Proposed article division

## Working title

**Forecasting Pix Across Brazil: Global Models and Coherent Geographic Reconciliation**

## Central research question

> Do global forecasting models improve municipality-level forecasts of Pix activity relative to local statistical benchmarks, and which scalable reconciliation strategies best preserve accuracy and geographic coherence across municipal, state, regional, and national levels?

## Conference-paper structure

### Abstract — approximately 180–220 words

- Context: Pix as digital payment infrastructure.
- Problem: thousands of geographically nested series with short histories.
- Method: local baselines, global models, reconciliation, rolling-origin evaluation.
- Results: to be inserted only after the experiments.
- Contribution: reproducible large-scale forecasting benchmark and geographic reliability analysis.

### 1. Introduction — 10–12%

1. Pix and the importance of forecasting digital payment infrastructure.
2. Why national totals conceal municipal heterogeneity.
3. Computational challenge: many short, related, nested time series.
4. Research gap.
5. Research question and contributions.

Proposed contributions:

1. formulation of municipal Pix activity as a large geographic forecasting hierarchy;
2. leakage-safe comparison of local statistical and global machine-learning models;
3. evaluation of scalable forecast reconciliation;
4. analysis of geographic heterogeneity in forecasting reliability.

### 2. Related Work — 12–15%

#### 2.1 Pix and instant payments as digital infrastructure

- institutional background;
- municipal Pix research;
- distinction between usage, adoption, and financial inclusion.

#### 2.2 Global forecasting models

- many-related-series setting;
- short histories and cross-series learning;
- tree-based global models and neural challengers.

#### 2.3 Hierarchical forecast reconciliation

- coherence;
- bottom-up, WLS, and MinT;
- computational challenges in large hierarchies.

#### 2.4 Structural breaks and forecast reliability

- diffusion regimes;
- changepoint stability;
- regional heterogeneity in prediction errors.

### 3. Data and Forecasting Problem — 12–14%

#### 3.1 Official data sources

- Banco Central do Brasil for the monthly Pix panel;
- IBGE municipal geometry distributed through `geobr` for cartography;
- population, connectivity, and economic variables are reserved for a later
  extension because their release calendars are not implemented in this version.

#### 3.2 Target definition

- primary: outgoing transaction count, PF plus PJ;
- nominal outgoing value and active payer counts are retained for descriptive
  auditing but are not forecast targets in the current experiment.

#### 3.3 Stable geographic hierarchy

- municipality-equivalent to state to macroregion to Brazil;
- unidentified geography;
- treatment of Boa Esperanca do Norte.

#### 3.4 Forecasting task

- monthly frequency;
- horizons 1, 3, and 6 months;
- existing-municipality forecasting, not new-municipality transfer.

### 4. Methods — 17–20%

#### 4.1 Local statistical baselines

- naive;
- seasonal naive;
- drift;
- ETS;
- ARIMA.

#### 4.2 Global forecasting models

- global Ridge with a sparse geographic design matrix;
- XGBoost as the nonlinear global challenger;
- both models estimated entirely in R;
- neural architectures reserved for a later extension only if justified.

#### 4.3 Forecast reconciliation

- bottom-up;
- WLS variance scaling;
- MinT-shrink subject to scalability;
- nonnegativity diagnostics.

#### 4.4 Structural-break diagnostics

- Bai–Perron for national, regional, and state aggregates;
- PELT for scalable exploratory detection;
- no full-sample break indicator in forecasting features.

### 5. Experimental Design — 12–14%

#### 5.1 Rolling-origin validation

- initial training window of 36 months;
- monthly expanding origins;
- horizons 1, 3, and 6;
- preprocessing and tuning restricted to each origin.

#### 5.2 Metrics

- MASE and RMSSE as primary metrics;
- MAE and WAPE at aggregate levels;
- RMSE as a complementary metric;
- explicit counts of observations with valid seasonal scales.

#### 5.3 Comparisons and ablations

- local versus global;
- unreconciled versus reconciled;
- performance by hierarchy level;
- runtime and memory.

### 6. Forecasting Results — 18–20%

#### 6.1 Overall model comparison

Central table: model by horizon by hierarchy level.

#### 6.2 Value of global learning

- municipal-level gains;
- distribution of gains, not only a national mean.

#### 6.3 Value and cost of reconciliation

- accuracy;
- coherence;
- negative-forecast incidence;
- runtime and memory.

#### 6.4 Robustness

- incidence of negative point forecasts;
- sensitivity to hierarchy level and forecast horizon;
- audit of series excluded from scaled metrics because of a zero seasonal scale.

### 7. Geographic Regimes and Forecast Reliability — 8–10%

- stable structural breaks;
- errors by region, historical Pix intensity, volatility, and recent growth;
- maps of error and model gain;
- predictive association, without causal language.

### 8. Discussion and Limitations — 5–7%

- what global learning captures;
- when coherence improves decisions;
- short history and rapidly evolving infrastructure;
- administrative geography and data revisions;
- limits of interpreting connectivity associations.

### 9. Conclusion — 3–4%

- direct answer to the research question;
- computational contribution;
- implications for monitoring digital infrastructure;
- journal extensions.

## Material moved to the journal extension

- receiver-side flows;
- PF/PJ decomposition;
- real transaction values as a second full experiment;
- population, connectivity, and release-calendar-aware economic covariates;
- probabilistic reconciliation;
- DeepAR or other neural architectures;
- explicit spatial or graph models;
- release-calendar-aware economic nowcasting;
- causal identification.
