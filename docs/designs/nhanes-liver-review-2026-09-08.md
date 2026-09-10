# NHANES liver work sample: second review

Reviewed 2026-09-08 against the supplied UCSF Research Data Analyst posting and `nhanes-liver-analysis.md`.

**Verdict: keep the project, revise the plan before implementation.** Its strongest evidence for this position is the reusable dataset, documented derivations, quality checks, SQL schema, and clear research reporting. Several previous review conclusions are too confident or incorrect. This is a scoped review using gstack engineering-review guidance, not a completed interactive gstack clearance or a validation of the final analysis. The original approved plan has not been changed.

## Evidence checked

- Read the complete local design and inspected the repository state. The Git root is still the parent `Projects for Resume` directory, with many tracked deletions and untracked project folders. `Rscript` is not on PATH. No implemented numbered pipeline or tests were found in this project.
- Read the local `P_LUX.XPT` with pandas 2.3.3: 10,409 rows; 677 partial exams with CAP. Their partial-exam reason counts are 371 insufficient fasting, 109 insufficient valid measurements, and 197 excessive stiffness IQR/median.
- Reproduced the tiny-number conversion directly: pandas' installed `_parse_float_vec` converts eight zero bytes to `5.397605346934028e-79`. Reproduced the five affected LUX column counts and CAP boundary counts of 163 at 400 and 40 at 100.
- Consulted CDC codebooks, NHANES variance guidance, the NCHS benchmark report, statistical software documentation, and methodological papers linked below. Counts claimed for P_DEMO were not independently rerun because that file is not present here.

## Findings requiring revision

### 1. P1, confidence 10/10: partial-exam inclusion is not settled

Plan locations: premise 10, verified findings, and CAP quality decision at lines 94–104 and 396–410.

`LUAXSTAT` includes fasting and measurement-count requirements, as well as stiffness variability. The local counts above contradict the explanation that all 677 recoveries represent a stiffness-variability artifact. Similar median CAP IQR ratios do not establish equivalent validity; a BMI regression cannot establish that selection bias has disappeared. See the [CDC LUX codebook](https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles/P_LUX.htm) and the [experimental meal-intake study](https://pmc.ncbi.nlm.nih.gov/articles/PMC5390386/).

The claim that CAP quality thresholds are unpublished is also incorrect: studies evaluated [absolute CAP IQR below 40 dB/m](https://pubmed.ncbi.nlm.nih.gov/28506907/) and [CAP IQR/median below 0.3](https://pubmed.ncbi.nlm.nih.gov/32213023/). These studies do not automatically establish a universal NHANES exclusion rule.

Recommendation: use complete exams with available CAP as a conservative primary operational definition, and all available CAP as an inclusion sensitivity analysis; explicitly acknowledge possible selection under either definition. Alternatively retain the broader primary sample only with a literature-supported fasting/measurement policy. Report partial reasons separately and add the cited CAP reliability sensitivity. Match strict versus inclusive threshold boundaries to the chosen source. Define eligibility, available measurement, and research quality separately.

### 2. P1, confidence 9/10: the Python fallback cannot certify survey inference

Plan locations: Day 1 Step 4, R contingency, and carried-forward concerns.

Combining stratum and PSU identifiers creates distinct clusters; it does not incorporate stratification into a generic clustered covariance estimator. `var_weights` does not by itself implement the NHANES design. The claim of necessarily conservative standard errors is not established, and the fixed “150x” error claim depends on the estimator and scaling. Statsmodels explicitly notes that other robust covariance types with weights have not been fully verified. See [statsmodels GLM documentation](https://www.statsmodels.org/stable/generated/statsmodels.genmod.generalized_linear_model.GLM.html).

Recommendation: Python for ingestion/QC/SQL; R `survey` for every submitted estimate and confidence interval. If R is delayed, release a clearly labeled dataset/QC milestone. Do not substitute unvalidated national confidence intervals. Build the design on the full eligible MEC sample with valid positive examination weights and design identifiers, then define adult and analysis domains through design subsetting. Preserve the full demographic table separately for accounting. Specify variance degrees of freedom and investigate singleton strata rather than applying an unexplained adjustment. See [NHANES variance guidance](https://wwwn.cdc.gov/nchs/nhanes/tutorials/varianceestimation.aspx) and [survey regression documentation](https://r-survey.r-forge.r-project.org/pkgdown/docs/reference/svyglm.html).

### 3. P1, confidence 9/10: coefficients are adjusted associations, not direct effects

Plan locations: premises 8 and 12; censoring claims; final success criteria.

Keeping HbA1c is compatible with an associational question. Adjusting for it does not establish a causal direct BMI effect. Temporal ordering and confounding assumptions are not established by these cross-sectional data. Likewise, neither removing ALT nor observing CAP boundary values establishes a guaranteed direction of coefficient bias. See the [methodological review of mediation assumptions](https://pubmed.ncbi.nlm.nih.gov/24019424/).

Recommendation: label all coefficients adjusted cross-sectional associations. Keep HbA1c if scientifically motivated; optionally show a prespecified model without it on the same records. Describe CAP boundary accumulation as a measurement limitation that may distort associations, without calling BMI estimates necessarily conservative. An 80+ indicator does not recover unknown ages above 80. Race/ethnicity should be explicitly categorical and interpreted in social and measurement context, not as an intrinsic biological effect.

### 4. P1, confidence 9/10: distinguish prevalence and regression samples

Plan location: Step 2's single exclusion cascade and “complete-case under a stated MAR assumption.”

A single cascade ending in complete covariates can unnecessarily restrict the prevalence estimate to people with HbA1c and BMI. Define separate flags for the descriptive CAP sample and the regression complete-case sample. The obesity validation requires its own domain, independently of CAP eligibility.

“Missing at random” alone does not justify complete-case analysis. Required assumptions depend on the estimand, model, and missingness mechanism; a comparison of observed characteristics cannot verify them. See [the methodological analysis of complete-case validity](https://pmc.ncbi.nlm.nih.gov/articles/PMC6693809/).

Recommendation: report variable-specific missingness in the eligible adult sample, distinct flow counts, and included/excluded comparisons. State complete-case limitations specifically. Do not promise nonresponse-adjusted weights without an actual adjustment model and variance procedure. Qualify inference to the US civilian noninstitutionalized population with examination eligibility and measurement nonresponse limitations.

### 5. P2, confidence 10/10: validation gate is too permissive

Plan locations: validation target and final success criterion at lines 364–365.

Reproducing a point estimate anywhere inside its published confidence interval is a weak software check. The report also excludes pregnant participants from obesity analyses, a condition absent from the proposed benchmark procedure. See [NHSR 158](https://www.cdc.gov/nchs/data/nhsr/nhsr158-508.pdf).

Recommendation: implement the exact benchmark domain, age groups, standard population proportions, and documented pregnancy handling. Compare the age-adjusted point estimate at the published rounding precision; investigate discrepancies. Compare uncertainty separately using the report's interval method. Do not tune the implementation merely to hit 41.9%. Keep one benchmark; hypertension adds unnecessary acquisition and definition work.

### 6. P2, confidence 9/10: effective sample size is not a sample-size calculation

Plan location: Day 2 Step 6 and longitudinal specification.

Reporting effective n and small subgroup counts demonstrates precision awareness, but does not establish what a model is powered to detect. Design effects are statistic-specific, not a universal multiplier for all models and subgroups. See [CDC's design-effect explanation](https://wwwn.cdc.gov/nchs/nhanes/tutorials/varianceestimation.aspx).

Recommendation: retain estimate-specific DEFF and confidence-interval widths. Add a short precision-based planning calculation for a future comparable prevalence survey: specify target margin of error, confidence level, assumed prevalence, assumed design effect, and anticipated response proportion. Show sensitivity to assumptions. Label it a planning illustration, not observed power or a clinical study recommendation. A written longitudinal specification demonstrates knowledge, not hands-on longitudinal-modeling experience; represent that distinction honestly.

### 7. P2, confidence 10/10: the strongest job-facing outputs are underspecified

Plan locations: deliverables, final criteria, and Day 2 schedule.

The plan names scientific communication but makes the README nearly the entire presentation. It lacks explicit acceptance criteria for charts, an analyst handoff, or a publication-style write-up. CSV and SQLite do not demonstrate Excel or Access proficiency.

Recommendation: retain CSV as the canonical data format, then generate an Excel review workbook with dictionary, QC, exclusions, and final tables. Add a concise Word research brief with methods, two well-labeled figures, findings, and limitations. A useful figure pair is threshold-specific weighted prevalence with CIs and an adjusted-coefficient plot. Include a short data-quality memo with observed issue, corrective action, prevention recommendation, and evidence. Describe SQLite as relational database experience; do not claim Access experience. A solo project also cannot prove teamwork or service orientation.

Fund these outputs by deferring alcohol processing, additional liver biomarkers, and MASLD work. Alcohol currently has no specified download of `P_ALQ` and runs after the database and primary analysis, so its output contract is unclear. Keep the longitudinal methods note brief and concrete: repeated-measure schema, time variable, estimand, correlation structure, missing-visit assumptions, and limitations.

### 8. P2, confidence 10/10: the execution contract has contradictions

- The promised Day 1 result is scheduled after the Day 1 shipping gate. Choose a dataset-only milestone or move the validated result before the gate.
- The artifact sweep is described both before joins and in the later cleaning script. Normalize verified import artifacts at ingestion and record the change before any eligibility logic.
- Attribute the artifact to the observed pandas conversion behavior. Preserve raw files, pin the reader version, verify zeros independently during implementation, and avoid a broad rule that turns every small number into zero. This is an import-QC finding, not a new hepatology discovery.
- Replace the repository-migration command recipe with a state-aware task that inventories and backs up current changes before any restore operation. The parent repository currently has tracked deletions; a blanket checkout is not a safe generic setup step. No migration was executed during this review.
- Resolve whether SQLite is optional or required; the premises call it a cut line, while final criteria require it. For this posting, keep the small SQL deliverable.
- Correct the assertion that `P_HDL` requires fasting-subsample weights. HDL uses examination weights when analyzed without a more restrictive component; triglycerides are a different case. See the [HDL analytic notes](https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles/P_HDL.htm).
- Keep R-squared out of scope if it distracts, but remove the blanket mathematical impossibility claim. Survey methods include defined goodness-of-fit measures; for example, the package documents [survey pseudo-R-squared](https://r-survey.r-forge.r-project.org/pkgdown/docs/reference/psrsq.html), which is not ordinary linear-model R-squared.

## Implementation and test review

Recommended flow:

```text
Source manifest + immutable XPT files
  -> reader normalization + variable-specific codebook rules
  -> full demographic left joins, unique SEQN checks
  -> documented master table + separate analysis flags
       -> SQLite domain tables/views + reusable CSV handoff
       -> full MEC survey design in R
            -> independent obesity benchmark domain
            -> CAP descriptive domain -> prevalence + CIs
            -> regression domain -> associations + sensitivities
  -> QC workbook + research brief + README
```

No implementation tests currently exist here. Add meaningful checks alongside the pipeline, before its first release:

| Path | Acceptance check |
|---|---|
| Acquisition | Fail clearly on HTTP error, HTML returned as XPT, wrong release, missing columns, or duplicate SEQN; record URLs and checksums. |
| Import/QC | Distinguish zero and missing; reproduce the observed decoder case; preserve race code 7 and age top-code 80; enforce units; keep valid boundary CAP values. |
| Joins and domains | One-to-one keys, unchanged master row count, no orphan domain IDs, disjoint exclusion accounting, distinct prevalence/regression flags. |
| Survey estimates | Match the benchmark domain and rounded estimate; inspect design degrees of freedom; valid bounded prevalence CIs; categorical covariates and intended reference levels. |
| Comparisons | Same records/specification for weighted and unweighted model comparison; do not label their variance ratio automatically as DEFF or predeclare which SE must be larger. |
| SQLite | Enable foreign-key enforcement; reject duplicate/orphan keys; compare SQL view IDs against Python flags. |
| Reproduction | A documented clean run regenerates the dataset, tables, figures, workbook, and brief; record Python/R dependencies and session versions. |

Performance review: this is a small public-data pipeline. A single-process implementation, cached downloads, and keyed joins suffice. No concurrency framework, warehouse platform, dashboard, or separate inference implementation is needed. The real bottlenecks are methodological decisions, toolchain setup, and report quality, not computation. The existing 16-hour schedule has not been validated.

## Recommended final scope

Python ingestion/QC, small SQLite database, R survey analysis, one independently matched benchmark, threshold and inclusion sensitivities, Excel handoff workbook, concise Word research brief, and a short longitudinal/precision-planning methods note. Defer alcohol and MASLD extensions until those outputs are complete.

This would provide strong evidence for data management, quantitative reasoning, quality assurance, SQL/Python/R, and nontechnical communication. It provides partial evidence for scientific writing and longitudinal-method knowledge. It does not substitute for publication history, actual longitudinal modeling experience, Access work, or interpersonal examples.
