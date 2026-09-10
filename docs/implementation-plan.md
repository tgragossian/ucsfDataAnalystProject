# NHANES liver health implementation

Updated 2026-09-08. This plan supersedes the implementation decisions in `designs/nhanes-liver-analysis.md` using the user's revised scope and second review. Alcohol is core, not deferred.

## Scope

Create a reusable, documented dataset from NHANES 2017–March 2020 examination, laboratory, demographic and alcohol questionnaire data. Estimate CAP-defined hepatic steatosis prevalence and examine associations with alcohol consumption. Report liver stiffness descriptively, not as a confirmed cirrhosis diagnosis. Use SQL, R, Excel, and Word. All estimates are cross-sectional associations, not causal effects or clinical recommendations.

## Decisions before analysis

- Source files: P_DEMO, P_LUX, P_BMX, P_GHB, P_ALQ. Preserve immutable source files and their codebooks; record SHA256 checksums, retrieval dates, source URLs, versions and row counts.
- R/haven for SAS import, R/survey for inference. Independently verify the previously observed pandas zero-conversion issue with haven. No generic clustered-SE substitute.
- Preserve all demographic rows in a master dataset. Build the survey design on examined participants with valid positive MEC weights and design identifiers before adult and analysis-domain subsetting.
- Primary CAP domain: age 18+, complete LUX exam, available valid CAP. Sensitivities: all available CAP including partial exams; primary exams with CAP IQR/median <0.30. Preserve and report partial-exam reasons and the selection limitation.
- Use a literature-supported primary CAP threshold and report threshold sensitivity. The threshold source and final choice will be recorded before statistical analysis.
- Alcohol frequency groups distinguish never drinkers, former/past-year non-drinkers, and three current-frequency categories. Unknown responses remain missing. Approximate grams/day is supplemental, with midpoint assumptions and quantity top-coding documented.
- Primary association model: continuous CAP on alcohol frequency group, BMI, age plus 80+ indicator, sex and categorical race/ethnicity. HbA1c-adjusted model is a secondary specification. Reference group: current drinking less than weekly, to avoid conflating former drinkers with never drinkers. Report unadjusted and adjusted results without predeclaring a positive association.
- Separate descriptive and regression flags; do not require alcohol/covariates for overall prevalence. Flag plausible extreme values and device boundaries, retain in primary analyses. Invalid values become missing with audit counts and source values preserved in domain tables.
- Validate the design independently against the same-release age-adjusted adult obesity benchmark, using its age-standardization and pregnancy exclusions. Validation tolerance must reflect published rounding, not the broad published CI.
- Report estimate-specific DEFF, effective n, confidence intervals, and a separate assumption-based prevalence precision-planning illustration. Do not present observed power.

## Work sequence and acceptance

1. Isolated project repository and R runtime. Preserve the existing notebook and source download locally; no parent-repository restore or migration.
2. Acquisition, source metadata, tested preparation functions and SQL schema. Master rows and joins reconcile; alcohol skip tests pass; distinct exclusion logs and dictionary exist.
3. Survey design benchmark, prevalence, alcohol association, sensitivity results, missingness comparisons and figures. Pipeline fails if benchmark or integrity checks fail.
4. Excel handoff workbook, Word research brief, README, methods and longitudinal note. Tables and charts come from the analysis outputs. Visually inspect the delivered artifacts.
5. Independent code/method review, end-to-end rerun and final verification. Local handoff first; publishing is a separate action.

## Progress

- [x] Inspect current files and parent Git state.
- [x] Initialize an isolated project repository on codex/nhanes-liver-analysis.
- [ ] Install and smoke-test R and required packages.
- [ ] Verify sources and lock analytic definitions.
- [ ] Implement and test acquisition, preparation, and SQL.
- [ ] Run and validate survey analyses.
- [ ] Build and inspect Excel and Word deliverables.
- [ ] Complete review and clean rerun.

Ruling: retain alcohol in the core pipeline because the user's revised research question requires it. Ruling: leave parent repository state untouched; migrating unrelated work is unnecessary for this project. Ruling: use R for data preparation as well as inference, matching the user's stated technology stack and avoiding the observed pandas decoder artifact.
