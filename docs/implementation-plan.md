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
- [x] Install and smoke-test R and required packages.
- [x] Verify sources and lock analytic definitions.
- [x] Implement and test acquisition, preparation, and SQL.
- [x] Run and validate survey analyses.
- [x] Build and inspect the Excel handoff workbook.
- [x] Build and inspect the Word research brief.
- [ ] Complete review and clean rerun.

Run of 2026-09-10 (R 4.6.1, Windows): full suite green, pipeline end to end. Master 15,560
rows; primary CAP 7,767; primary regression 7,325. Obesity benchmark 41.87% against the
published 41.9%, inside the rounding tolerance, so the design gate passes. The SQL
`exclusion_cascade` view matches the R exclusion log at all eight stages. The
5.397605e-79 reader artifact did not occur under haven (0 conversions), which confirms it
as a pandas decoder issue rather than a property of the files.

Missingness addendum, same day. Weighted missingness is now estimated by sex,
race/ethnicity, and age group inside the adult MEC, primary CAP, and regression samples,
with Rao-Scott second-order F tests (`missingness_by_group.csv`, `missingness_tests.csv`,
`figures/income_missingness.png`). Income-to-poverty ratio: 11.6% missing among adults,
8.9% to 18.3% by race/ethnicity, p = 6.6e-09. Drinking status unknown: 5.1% overall, 3.4%
to 14.1% by race/ethnicity, p = 1.1e-09 - and that one gates the regression sample, so the
complete-case model sample is differently composed, not just smaller. Two bugs found and
fixed on the way: `cap_reliable_sensitivity` was carrying NA instead of being a domain
flag, which broke `prevalence_row` on that domain, and `survey::update` is not exported so
the missingness-CI code had never actually run. Existing outputs (benchmark, prevalence,
models, exclusion log) are byte-identical after both fixes.

Excel handoff, same day. `scripts/build_workbook.R` (openxlsx) replaces an earlier Node
builder that lived under the gitignored `outputs/` tree and depended on a package a
reviewer cannot install; the workbook is now regenerated from the tracked repo in the
stack the README actually claims. Twenty sheets, 3.1 MB, including the full 15,560-row
master. Scope ruling: keep every raw table rather than curating, because the analyst
preparing the data should not be deciding for the clinician which columns matter. Two
defects were caught by rendering the file rather than trusting it: openxlsx writes a
drawing and a VML relationship on every sheet without writing those parts, so the builder
now prunes any relationship whose target is absent; and `nchar(NA)` is NA, which had
written `ht="NA"` row heights that Excel would have offered to repair.

Word brief, same day. `scripts/build_brief.R` (officer + flextable) produces
`outputs/word_brief/nhanes_liver_brief.docx`, six pages: background, methods, findings
with the two planned figures plus the income-missingness panel, limitations, a
data-quality memo in the issue/action/prevention/evidence format the review asked for,
and the longitudinal-design note as the final section rather than a separate file. Like
the workbook builder, every statistic including those inside sentences is read from
`outputs/tables`, so the prose cannot drift from the analysis. One builder bug caught by
rendering the draft to PDF and reading every page: the heading and plain-paragraph
helpers returned the modified document but callers did not reassign it, so under
officer's value semantics every section heading and unformatted paragraph was silently
dropped; fixed by threading `doc` through every helper.

Ruling: retain alcohol in the core pipeline because the user's revised research question requires it. Ruling: leave parent repository state untouched; migrating unrelated work is unnecessary for this project. Ruling: use R for data preparation as well as inference, matching the user's stated technology stack and avoiding the observed pandas decoder artifact.
