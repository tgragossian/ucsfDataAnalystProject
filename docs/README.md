SCOPE AND GOALS:

This project will create a cleaned, documented dataset for studying liver health using publicly available examination, laboratory, and questionnaire data from the CDC’s NHANES 2017–March 2020 pre-pandemic release.

The analysis will estimate the prevalence of hepatic steatosis using a clearly defined controlled attenuation parameter (CAP) threshold and examine its association with self-reported alcohol consumption. Findings will be interpreted as associations rather than evidence of causation. Liver stiffness measurements will provide additional information about liver health, without being treated as confirmed diagnoses of cirrhosis.

Data preparation will include checks for missing values, inconsistent records, implausible values, and measurement quality. Extreme but plausible observations will be retained and flagged. Exclusions will follow documented eligibility and quality criteria, with sensitivity analyses assessing how key decisions affect the findings.
The final deliverables will include a reusable analytic dataset, data dictionary, quality-check and exclusion logs, statistical tables and figures, and a written report. Analyses will account for NHANES survey weights and sampling design and report confidence intervals and estimate-specific effective sample sizes.

The project will use SQL for data organization and validation, R for statistical analysis, Excel for reviewing datasets and results, and Word for the final report.

DOCUMENTATION:

Documentation will describe data sources, variable definitions, table relationships, cleaning rules, exclusions, missing-data handling, statistical methods, findings, and limitations. Instructions will explain how to reproduce the final dataset and analysis.

1. The data was pulled from the CDC's website by `scripts/download.R`, which records the
   source URL, SHA256 checksum, row and column counts, and retrieval time for each of the
   five files in `outputs/tables/source_manifest.csv`. The raw `.xpt` files are never edited.

2. The data was then cleaned/flagged for relevant topics of interest. As the scope included
   liver health of Americans and its relation to obesity and alcoholism, these were the
   primary datasets used.
    a. I merged the demographic (DEMO), liver health (LUX), alcohol usage (ALQ), body
       measurement (BMX), and glycohemoglobin (GHB) on the unique id for a subject. It is a
       left join from DEMO, so the row count never moves; a duplicate or orphan id stops the
       program instead of quietly multiplying or adding rows.
    b. I then made the program stop if any part of the survey wasn't in the correct data
       release cycle, which should match for consistency.
    c. Every column is checked against its documented codebook domain. Those domains live in
       `config/variables.csv`, not in the R code, so adding a variable means adding a row
       there. A value outside its domain becomes NA and is counted in
       `outputs/tables/validation_rules.csv`; it never deletes a row, and the original value
       is still readable in the SQLite domain tables. Refusals and "don't know" answers
       (7/9, 77/99, 777/999) are counted separately from other invalid values, because they
       mean different things. Race code 7 and age 80 are real categories, not missing codes,
       and are kept.
    d. Next, T/F flags. Eligibility, available measurement, and research quality are three
       different questions, so they get three different flags rather than one:
        i.   `mec_examined` - was the patient examined, not just interviewed?
        ii.  `adult_mec` - examined, positive examination weight, and 18 or older.
        iii. `broad_cap` - is there a usable CAP reading at all, partial exams included?
        iv.  `primary_cap` - the same, but from a complete exam (`LUAXSTAT == 1`). This is
             the primary prevalence sample.
        v.   `cap_reliable_sensitivity` - the primary sample restricted to a CAP IQR/median
             below 0.30, as a measurement-quality sensitivity check.
        vi.  `regression_primary` - the complete-case sample for the model, which also needs
             alcohol and the covariates. Prevalence deliberately does not require those,
             because it is answering a different question.
    e. CAP values sitting at the device floor (100 dB/m) and ceiling (400 dB/m) are flagged
       and kept, not deleted. They are censoring points, and excluding on outcome magnitude
       would delete the disease.
    f. Alcohol is classified from ALQ111 and ALQ121 together, so never-drinkers, past-year
       non-drinkers, and non-responders stay three different things instead of collapsing
       into one. Anyone who says they never drank but then answers the frequency question is
       flagged as a contradiction; their derived group and volume go missing while their
       original answers are preserved.
    g. Missingness is then analysed rather than just counted. For income-to-poverty ratio,
       BMI, drinking status, and HbA1c, the pipeline builds a 0/1 missing indicator and
       estimates its weighted rate by sex, race/ethnicity, and age group, with confidence
       intervals, inside each analytic sample. Group differences are tested with the
       Rao-Scott second-order F (`svychisq`), never `chisq.test()`, which would ignore the
       weights, strata, and PSUs and report far too small a p-value. `SDMVSTRA` is not used
       as a grouping variable: it is a variance-estimation device, not a subgroup anyone
       would want a missingness rate for, and it is already carrying the uncertainty. The
       reported quantity of record is the percentage-point spread and its interval; the
       p-value only says the spread is not noise. Where a variable is required by the
       sample rule - BMI and drinking status inside the regression sample - there is
       nothing left to explain and the row records "Not applicable" instead of a test.

3. Results:
    a. Of 15,560 people in the release, 14,300 were examined in the MEC, 8,965 of those were
       adults, 8,317 had a CAP reading, 7,767 of those came from a complete exam, and 7,325
       had everything the model needs. The SQL view `exclusion_cascade` rebuilds this count
       independently from the database and matches the R log at every stage.
    b. The survey design validates against an outside number: age-standardized adult obesity
       comes out at 41.87% against the published 41.9%, within the published rounding
       precision.
    c. Steatosis prevalence at CAP >= 274 dB/m is 42.2% (95% CI 40.5-44.0). At 248 dB/m it
       is 56.4% and at 302 dB/m it is 27.3%, which is exactly why the threshold is reported
       four ways instead of one.
    d. Drinking nearly every day or daily is associated with about +9.6 dB/m of CAP compared
       with drinking less than weekly (95% CI 2.4-16.8), adjusting for BMI, age, sex, and
       race/ethnicity. That is a cross-sectional association, not an effect.
    e. The 5.397605e-79 tiny-number artifact never appeared: haven decoded those bytes as
       true zeros. The exact-match normalization stays in the pipeline as a guard and
       logs a count of 0, which is the evidence that it was a reader problem rather than
       something in the data.
    f. Missing data is not spread evenly, and that is a finding rather than a footnote.
       Income-to-poverty ratio is missing for 11.6% of adults, ranging from 8.9% of
       Non-Hispanic White adults to 18.3% of Other Hispanic adults - a 9.4 point spread
       (Rao-Scott F, p < 1e-08). Income is not a model covariate, so nobody was excluded
       for it. But the same pattern appears in a variable that does gate the model:
       drinking status is unknown for 3.4% of Non-Hispanic White adults against 14.1% of
       Non-Hispanic Asian adults, a 10.8 point spread. The regression sample is therefore
       not merely smaller than the prevalence sample, it is differently composed, which is
       why prevalence is reported on a sample that does not require alcohol at all.
       `missingness_by_group.csv` and `missingness_tests.csv` carry this by sex,
       race/ethnicity, and age group, within the adult MEC, primary CAP, and regression
       samples; `outputs/figures/income_missingness.png` plots the income panel.

4. The Excel handoff, `outputs/excel_handoff/nhanes_liver_handoff.xlsx`, built by
   `scripts/build_workbook.R` after the pipeline runs. Twenty sheets: a Read Me with a
   sheet guide, a Summary, then the documentation sheets this project is actually about -
   Data Loss, Cleaning and Validation, Quality Findings, Alcohol Notes, Liver CAP Notes,
   and Bias Notes - followed by every analysis table in full and the complete 15,560-row
   master dataset with all its flags.
    a. The raw tables are kept rather than curated down. Whoever uses this decides what
       matters clinically; this pipeline does not get to make that call for them, so the
       workbook stays a working dataset and not just a report.
    b. No number is computed in the builder. Every figure, including the ones inside the
       written notes, is read back out of `outputs/tables`, so the prose cannot drift away
       from the tables it describes. Rerunning the pipeline rewrites both together.
    c. Weighted percentages and the unweighted counts they came from sit next to each
       other on every sheet, and the Read Me says why they do not match.
    d. Excel's own reproducibility check: `scripts/build_workbook.R` regenerates the whole
       file from the CSVs, so the workbook is an output, never a document anyone hand-edits.

5. The Word research brief, `outputs/word_brief/nhanes_liver_brief.docx`, built by
   `scripts/build_brief.R` after the pipeline runs. Six pages: background, data and
   methods, findings with three figures, limitations, a data-quality memo, and a
   longitudinal-design note that states why this repeated cross-sectional release cannot
   support a within-person analysis and what a study that could would need.
    a. Same discipline as the workbook: no statistic is typed into the builder. Every
       number, including those inside sentences, is read from `outputs/tables` and
       `outputs/figures`, so rerunning the pipeline rewrites the brief in step with it.
    b. Written as a genuine research brief - third person, cross-sectional framing, no
       causal language - because that is what demonstrates the analysis, not a memo about it.
