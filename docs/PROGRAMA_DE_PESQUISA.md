# Programa de pesquisa "A Geografia do Pix" — auditoria intelectual e proposta (2026-10-03)

**Status: PROPOSTA, aguardando decisão do autor.** Nada do projeto foi alterado por causa deste
documento. Ele registra a auditoria feita em 03/10/2026 para retomar a conversa depois.
A redação dos artigos é do autor; aqui há só desenho de pesquisa.

## A. O que o projeto é hoje (evidência no repositório)
- Título e pergunta (article/outline.md): *Forecasting Pix Across Brazil: Global Models and Coherent
  Geographic Reconciliation* — "Do global forecasting models improve municipality-level forecasts of Pix
  activity relative to local statistical benchmarks, and which scalable reconciliation strategies best
  preserve accuracy and geographic coherence across municipal, state, regional, and national levels?"
- AUDIT_DECISIONS.md recusou "exigir uma matriz espacial W quando o delineamento atual é de previsão
  hierárquica, não de econometria espacial". O outline deixa covariáveis, modelos espaciais e
  identificação causal para "journal extension".
- Conclusão: o código constrói um **artigo de previsão (Artigo F)**, não o artigo de difusão espacial e
  determinantes. O tema "Geografia do Pix" aparece no nome do repositório, não na pergunta implementada.

## B. O que existe
Pronto e testado: extração BCB, geografia estável, validação, DuckDB; descritivas e quebras estruturais;
5 modelos locais + Ridge/XGBoost globais com origem móvel (29 origens, h = 1/3/6); reconciliação
(bottom-up, WLS); Newey-West, negativos, cobertura, tempo; regressão de confiabilidade (fixest); mapa de
ganho (geobr); SHAP; piloto auditado (C1–C4 PASS em 03/10); paralelização por origem.
Não existe: covariáveis, matriz W, modelos espaciais, variáveis per capita.
Campo ainda não usado e central para os novos artigos: `QT_PES_PagadorPF` (pessoas que pagaram via Pix
no mês) → medida de **adoção** (por adulto), distinta de intensidade (transações).

## C/D. Perguntas
- Original (Artigo F): previsão em larga escala, coerente e com mapa de confiabilidade.
- Nova (Artigo 2): "Did Pix reduce the geographic disadvantage of municipalities underserved by
  traditional banking infrastructure — and did this depend on digital connectivity?" — outro desfecho,
  mecanismo, estratégia e literatura.
- Proposta pelo autor (Artigo 1): difusão espacial e determinantes da adoção.

## E. Recomendação: programa com TRÊS artigos complementares
1. **Artigo F (previsão, existente)** — preservar integralmente; concluir com a rodada nacional.
2. **Artigo 2 (banking deserts / leapfrogging)** — mais original e publicável em Banking & Finance.
3. **Artigo 1 (difusão espacial)** — decidir só após a evidência descritiva compartilhada (curvas de
   difusão, LISA por fase, convergência); risco de "ricos adotam mais" e de sobreposição com
   Alvarez, Argente, Lippi, Méndez & Van Patten (NBER 2023; **confirmar**). Se não se sustentar, essas
   análises viram a seção descritiva do Artigo 2.

Fronteiras contra salami slicing: Artigo 1 não usa banco como tese (só controle); Artigo 2 não tem
dependência espacial como resultado (só robustez: Conley, vizinhança); Artigo F não faz inferência
sobre determinantes.

## G. Desenho resumido

| Dimensão | F — Previsão | 1 — Difusão espacial | 2 — Bancos e leapfrogging |
|---|---|---|---|
| Título provisório | Forecasting Pix Across Brazil | The Spatial Diffusion of a Digital Public Infrastructure: Evidence from Pix | Digital Public Payment Infrastructure and Banking Deserts: Financial Leapfrogging and the Digital Divide |
| Desfecho | transações (`payer_count`) | adoção por adulto; parâmetros da curva de difusão | adoção por adulto; penalidade bancária β_t |
| Mecanismo | aprendizado entre séries; coerência | socioeconômico, digital, urbano (REGIC), vizinhança | escassez bancária pré-Pix × conectividade pré-Pix |
| Hipóteses | global > local; reconciliação sem perda | dependência espacial persistente; difusão hierárquica urbana; convergência condicional | β_t diminui no tempo; diminui mais com conectividade; robusto a renda/urbanização |
| Estratégia | origem móvel, MASE/RMSSE, Newey-West | curvas de difusão; Moran/LISA por fase; β-convergência; SAR/SEM/SDM | painel com EF de município e UF×mês; escassez×mês; tripla interação; Conley/cluster |
| Identificação | não causal | associação; spillover = efeito indireto do SDM | trajetórias diferenciais condicionadas a características pré-Pix; não causal |
| Revistas | IJF, J. Forecasting | Regional Studies, Papers in Regional Science, TFSC | JBF, JFI, JMCB; TFSC/Research Policy |

## H. Destino do trabalho existente
Extração/geografia/validação/DuckDB e descritivas → compartilhado. Quebras estruturais → F e fases do
Artigo 1. Modelos, reconciliação, Newey-West, negativos, tempo, confiabilidade, mapa de ganho, SHAP → F.
Covariáveis no modelo global → extensão/robustez do F (sem refazer o nacional). Propostas de 03/10:
leapfrogging e Auxílio Emergencial → Artigo 2; curvas de difusão → Artigo 1 (e medida do 2);
vizinhança → Artigo 1. Nada é descartado.

## I. Dados que faltam (medidos antes do Pix, 2019–2020, exceto desfechos)
IBGE: população total e adulta 2020, PIB municipal 2019, REGIC 2018, tipologia rural-urbana.
BCB/ESTBAN: agências por município 2019 (postos/correspondentes: verificar série municipal).
Anatel: banda larga fixa e cobertura 4G 2019–2020. Portal da Transparência: Auxílio Emergencial 2020 e
Bolsa Família 2019 (arquivos pesados). Censo 2010 (escolaridade, urbanização; 2022 só robustez).
Distância ao município com agência mais próximo (geobr). Já temos: `QT_PES_PagadorPF` e lado recebedor.
Obs.: o ambiente de nuvem não alcança IBGE/BCB/Anatel/Transparência — downloads rodam na máquina do autor.

## J. Identificação
Pix = 0 antes de nov/2020: sem pré-período do desfecho, sem event study clássico. Defensável: "a
penalidade associada à escassez bancária diminuiu ao longo do tempo", condicionada a características
pré-Pix, com EF e controles × tempo; reforços: Oster, definições alternativas, sem capitais, pareamento.
Extensão possível: desfechos bancários do ESTBAN com pré-período (endogeneidade persiste).
Checagem prévia obrigatória: variação conjunta escassez bancária × conectividade (há municípios
mal atendidos por bancos e bem conectados?).

## K. Originalidade
Artigo 2 > Artigo F > Artigo 1 (este depende da evidência descritiva e da revisão de literatura).

## L. Próximos 10 passos
1. Terminar o nacional e fechar o Artigo F no escopo atual.
2. Autor aprovar (ou ajustar) este programa.
3. Revisão de literatura dirigida (Alvarez et al. 2023; Sarkisyan 2023; BIS sobre Pix; Suri & Jack 2016;
   banking deserts) — confirmar referências antes de citar.
4. Pipeline compartilhado de covariáveis em projeto `targets` separado (não toca o `_targets.R` atual).
5. Desfecho de adoção (`QT_PES_PagadorPF` por adulto), auditando dupla contagem entre municípios.
6. Checagem da variação conjunta escassez × conectividade (viabilidade do Artigo 2).
7. Descritivas compartilhadas (mapas por fase, LISA, curvas, convergência) → decidir o Artigo 1.
8. Especificação principal do Artigo 2 (β_t, tripla interação, EF, Conley).
9. Robustez do Artigo 2 e mecanismo do Auxílio Emergencial.
10. Decisão sobre o Artigo 1.
