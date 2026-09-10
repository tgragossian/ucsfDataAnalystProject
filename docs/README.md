SCOPE AND GOALS:

This project will create a cleaned, documented dataset for studying liver health using publicly available examination, laboratory, and questionnaire data from the CDC’s NHANES 2017–March 2020 pre-pandemic release.

The analysis will estimate the prevalence of hepatic steatosis using a clearly defined controlled attenuation parameter (CAP) threshold and examine its association with self-reported alcohol consumption. Findings will be interpreted as associations rather than evidence of causation. Liver stiffness measurements will provide additional information about liver health, without being treated as confirmed diagnoses of cirrhosis.

Data preparation will include checks for missing values, inconsistent records, implausible values, and measurement quality. Extreme but plausible observations will be retained and flagged. Exclusions will follow documented eligibility and quality criteria, with sensitivity analyses assessing how key decisions affect the findings.
The final deliverables will include a reusable analytic dataset, data dictionary, quality-check and exclusion logs, statistical tables and figures, and a written report. Analyses will account for NHANES survey weights and sampling design and report confidence intervals and estimate-specific effective sample sizes.

The project will use SQL for data organization and validation, R for statistical analysis, Excel for reviewing datasets and results, and Word for the final report.

DOCUMENTATION:

Documentation will describe data sources, variable definitions, table relationships, cleaning rules, exclusions, missing-data handling, statistical methods, findings, and limitations. Instructions will explain how to reproduce the final dataset and analysis.

1. The data was extracted from the CDC's website, nothing worth documenting.
2. The data was then cleaned/flagged for relavent topics of interest. As the scope included liver health of Americans and its relation to obesity and alcoholism, these were the primary datasets used.
    a. I merged the demographic (DEMO), liver health (LUX), alcohol usage (ALQ), body measurement (BMX), and glycohemoglobin (GHB) on the unique id for a subject.
    b. I then made the program stop if any part of the survey wasn't in the correct data release cycle, which should match for consistency.
    c. Next, T/F flags for: 
        i. "Was the paitent examined, not just interviewed?"
        ii. "Was the liver at least partially examined?" (code 1 in documentation if fully, 2 if partially. If neither, it would not have significant use cases for the sake of this analysis)
    d. Next, I removed survey entries that were either an answer refusal or unknown in the data, replacing both cases with NA as it doesn't have significant usage on the analysis.
    e. Lastly, I created a boolean of the stiffness iqr/median ratio less than 30 using the already-made column for quality assurance of the datapoint, then made the ratio for the cap score with the same flag

3. Results:
    a. I found that 14300 people were examined, and 9771 had at least a partial exam.
    
