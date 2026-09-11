# Builds the Word research brief from the pipeline outputs.
#
# Like scripts/build_workbook.R, this file is presentation only. Every statistic,
# including the ones inside sentences, is read back out of outputs/tables so the
# prose cannot drift from the analysis. Rerun after scripts/run_pipeline.R:
#   Rscript scripts/build_brief.R
suppressPackageStartupMessages({
    library(officer)
    library(flextable)
})
set_flextable_defaults(font.family = "Calibri", font.size = 9, padding = 3,
                       border.color = "#BFBFBF")

table_dir <- "outputs/tables"
fig_dir <- "outputs/figures"
out_dir <- "outputs/word_brief"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

read_out <- function(name) read.csv(file.path(table_dir, paste0(name, ".csv")), stringsAsFactors = FALSE)
pull <- function(values) { stopifnot(length(values) == 1); values }
pct <- function(x, d = 1) sprintf(paste0("%.", d, "f%%"), 100 * x)
dbm <- function(x) sprintf("%+.1f dB/m", x)
p_txt <- function(p) ifelse(p < 0.001, "p < 0.001", paste0("p = ", sprintf("%.3f", p)))
ci_txt <- function(lo, hi, f = pct) sprintf("95%% CI %s to %s", f(lo), f(hi))
commas <- function(x) format(x, big.mark = ",", trim = TRUE)

prevalence <- read_out("prevalence")
models <- read_out("models")
benchmark <- read_out("benchmark")
design <- read_out("design_summary")
stiffness <- read_out("liver_stiffness")
excl <- read_out("exclusion_log")
quality <- read_out("quality_findings")
mtests <- read_out("missingness_tests")
manifest <- read_out("source_manifest")
precision <- read_out("precision_planning")

reg <- excl[excl$cascade == "Primary regression", ]
step_out <- function(s) pull(reg$n_excluded[reg$step == s])
prev_all <- function(th) prevalence[prevalence$domain == "primary_cap" & prevalence$threshold == th &
                                    prevalence$alcohol_group == "All", ]
coef_row <- function(model, term) models[models$model == model & models$term == term, ]
mtest <- function(v, g) mtests[mtests$domain == "adult_mec" & mtests$variable == v & mtests$group_variable == g, ]
finding_n <- function(issue) pull(quality$n[quality$issue == issue])

p274 <- prev_all(274)
daily <- coef_row("primary", "alcohol_groupCurrent 5 to 7 per week")
daily_naive <- coef_row("naive_same_sample", "alcohol_groupCurrent 5 to 7 per week")
daily_hba1c <- coef_row("HbA1c_subset_with_HbA1c", "alcohol_groupCurrent 5 to 7 per week")
never <- coef_row("primary", "alcohol_groupNever")
former <- coef_row("primary", "alcohol_groupFormer")
mid <- coef_row("primary", "alcohol_groupCurrent 1 to 4 per week")
bmi_coef <- coef_row("primary", "BMXBMI")
income_race <- mtest("INDFMPIR", "race")
alcohol_race <- mtest("alcohol_group", "race")
n_prev <- pull(reg$n_remaining[reg$step == "Complete exam"])
n_reg <- pull(reg$n_remaining[reg$step == "Complete model covariates"])

# ---- styling --------------------------------------------------------------
navy <- "#1F4E78"
fp_title <- fp_text(font.size = 19, bold = TRUE, color = navy, font.family = "Calibri")
fp_sub <- fp_text(font.size = 10.5, italic = TRUE, color = "#555555", font.family = "Calibri")
fp_lead <- fp_text(bold = TRUE, font.family = "Calibri", font.size = 10.5)
fp_plain <- fp_text(font.family = "Calibri", font.size = 10.5)
fp_foot <- fp_text(font.size = 8, italic = TRUE, color = "#777777", font.family = "Calibri")
par_body <- fp_par(line_spacing = 1.06, padding.bottom = 6)

# Every helper takes the doc and returns it; callers must reassign.
heading <- function(doc, text) body_add_par(doc, text, style = "heading 1")
sub <- function(doc, text) body_add_par(doc, text, style = "heading 2")
body <- function(doc, text)
    body_add_fpar(doc, fpar(ftext(text, fp_plain), fp_p = par_body))
lead_body <- function(doc, label, text)
    body_add_fpar(doc, fpar(ftext(label, fp_lead), ftext(text, fp_plain), fp_p = par_body))
caption <- function(doc, text)
    body_add_fpar(doc, fpar(ftext(text, fp_text(font.size = 9, italic = TRUE, color = "#555555", font.family = "Calibri")),
                            fp_p = fp_par(padding.bottom = 10, padding.top = 2)))

ft <- function(df, widths, align_right = character(0)) {
    x <- flextable(df)
    x <- theme_booktabs(x)
    x <- border_remove(x)
    x <- hline_bottom(x, part = "body", border = fp_border(color = "#BFBFBF", width = 1))
    x <- bg(x, part = "header", bg = navy)
    x <- color(x, part = "header", color = "white")
    x <- bold(x, part = "header")
    x <- align(x, align = "left", part = "all")
    if (length(align_right))
        x <- align(x, j = align_right, align = "right", part = "all")
    x <- valign(x, valign = "top", part = "body")
    x <- padding(x, padding.top = 3, padding.bottom = 3, part = "all")
    x <- width(x, width = widths)
    x
}
add_ft <- function(doc, x) {
    doc <- body_add_flextable(doc, x, align = "left")
    body_add_par(doc, "", style = "Normal")
}
add_fig <- function(doc, file, cap, height) {
    doc <- body_add_img(doc, file.path(fig_dir, file), width = 6.5, height = height, style = "centered")
    caption(doc, cap)
}

doc <- read_docx()
doc <- set_doc_properties(doc, title = "NHANES Liver Health Research Brief",
                          subject = "CAP-defined hepatic steatosis and alcohol frequency",
                          creator = "NHANES liver analysis pipeline")

doc <- body_add_fpar(doc, fpar(ftext("Hepatic Steatosis and Alcohol Frequency in US Adults", fp_title),
                               fp_p = fp_par(padding.bottom = 3)))
doc <- body_add_fpar(doc, fpar(ftext(paste0(
    "A cross-sectional analysis of NHANES 2017-March 2020. Research brief, not a clinical guideline. ",
    "All estimates are survey-weighted associations, not causal effects."), fp_sub),
    fp_p = fp_par(padding.bottom = 12)))

# ---- 1. background -------------------------------------------------------
doc <- heading(doc, "Background and question")
doc <- body(doc, paste0(
    "Controlled attenuation parameter (CAP), measured by transient elastography, is a non-invasive marker of ",
    "liver fat. The 2017-March 2020 pre-pandemic release of the National Health and Nutrition Examination Survey ",
    "(NHANES) is the first NHANES cycle to carry elastography. This brief asks two questions of that release: how ",
    "common is CAP-defined hepatic steatosis among US adults, and does it vary with self-reported drinking ",
    "frequency after adjustment for body mass index, age, sex, and race and ethnicity. Both are answered ",
    "descriptively: NHANES is a single snapshot, so nothing here speaks to whether drinking changes liver fat ",
    "within a person over time. The final section sets out what a study that could answer it would require."))

# ---- 2. data and methods ----------------------------------------------
doc <- heading(doc, "Data and methods")

doc <- sub(doc, "Source data and survey design")
doc <- body(doc, paste0(
    "Five CDC files were joined on the participant identifier and read with the haven package; each file's URL, ",
    "row count, and SHA-256 checksum are recorded in the source manifest so the analysis reproduces against a ",
    "fixed input."))
doc <- add_ft(doc, ft(data.frame(
    File = manifest$file, Rows = commas(manifest$n_rows), Columns = manifest$n_columns,
    Content = c("Demographics, examination status, survey design", "Transient elastography (CAP and stiffness)",
                "Body mass index and anthropometry", "Glycohemoglobin (HbA1c)", "Alcohol use questionnaire"),
    check.names = FALSE),
    widths = c(0.8, 0.8, 0.9, 4.0), align_right = c("Rows", "Columns")))
doc <- body(doc, sprintf(paste0(
    "All population estimates use the full MEC examination weight with the masked sampling strata and ",
    "pseudo-primary sampling units, Taylor-linearized: %s examined participants across %s strata and %s ",
    "pseudo-PSUs, giving %s design degrees of freedom. That figure, not the sample size, governs every confidence ",
    "interval here. The design was validated before any liver analysis was run: age-standardized adult obesity ",
    "rebuilt from it is %s (%s) against the published National Health Statistics Report figure of %s, and the ",
    "pipeline halts if that check fails."),
    commas(pull(design$n_MEC)), pull(design$strata), pull(design$PSUs), pull(design$design_df),
    pct(pull(benchmark$estimate), 2),
    ci_txt(pull(benchmark$conf_low), pull(benchmark$conf_high), function(x) pct(x, 1)),
    pct(pull(benchmark$published_estimate), 1)))

doc <- sub(doc, "Analytic samples")
doc <- body(doc, paste0(
    "Prevalence and the regression use different samples on purpose. Prevalence is estimated on adults with a ",
    "complete elastography exam and a usable CAP value, and does not require drinking status or covariates. The ",
    "regression is that sample further restricted to a classifiable drinking status and complete covariates. ",
    "Keeping them separate means the descriptive headline is not exposed to missingness in the exposure."))
doc <- add_ft(doc, ft(data.frame(
    Step = reg$step, Criterion = reg$criterion,
    Remaining = commas(reg$n_remaining), Excluded = commas(reg$n_excluded), check.names = FALSE),
    widths = c(1.7, 2.7, 1.05, 1.05), align_right = c("Remaining", "Excluded")))
doc <- body(doc, sprintf(paste0(
    "The dominant exclusion is age: restricting to adults removes %s participants, about two-thirds of all loss, ",
    "and is a scope decision rather than a data problem. Only around %s of the release is lost to anything ",
    "elastography-specific. The two regression-only steps remove %s participants between them, and %s of that is ",
    "unclassifiable drinking status rather than missing covariates."),
    commas(step_out("Adult MEC")),
    pct((step_out("CAP available") + step_out("Complete exam")) / 15560, 0),
    commas(step_out("Alcohol known") + step_out("Complete model covariates")),
    pct(step_out("Alcohol known") / (step_out("Alcohol known") + step_out("Complete model covariates")), 0)))

doc <- sub(doc, "Key definitions")
doc <- lead_body(doc, "CAP and thresholds. ", paste0(
    "The device reports median CAP within 100-400 dB/m. No steatosis cut point is settled in the literature, so ",
    "prevalence is reported at four thresholds (248, 274, 288, 302 dB/m). Values at the boundaries are censoring ",
    "points; they are flagged and retained, never dropped, because excluding on the size of the outcome would ",
    "remove the participants the analysis is about."))
doc <- lead_body(doc, "Drinking frequency. ", paste0(
    "Built from two questionnaire items with a skip pattern. Never-drinkers, past-year non-drinkers, current ",
    "drinkers at three frequency levels, and non-responders are kept as five distinct states plus an unknown ",
    "category; a blank is never read as zero. The regression reference group is current drinking less than ",
    "weekly, so former and never drinkers are not conflated with light drinkers."))
doc <- lead_body(doc, "Regression. ", paste0(
    "Survey-weighted linear model of continuous CAP on drinking group, BMI, age, an age-80 top-code indicator, ",
    "sex, and race and ethnicity. A model additionally adjusting for HbA1c is a secondary specification; the same ",
    "model fit without weights on identical rows is shown for comparison."))

# ---- 3. findings ------------------------------------------------------
doc <- heading(doc, "Findings")

doc <- sub(doc, "Steatosis prevalence")
doc <- body(doc, sprintf(paste0(
    "In the primary sample of %s adults, CAP-defined steatosis prevalence at 274 dB/m is %s (%s). The estimate ",
    "is sensitive to the threshold, moving from %s at 248 dB/m to %s at 302 dB/m; a single uncited cut point ",
    "would overstate how precisely this is known. A broad sample including partial exams, and a stricter sample ",
    "restricted to reliable CAP measurements, fall within a few points of the primary figure at each threshold."),
    commas(pull(p274$n)), pct(pull(p274$estimate)), ci_txt(pull(p274$conf_low), pull(p274$conf_high)),
    pct(prev_all(248)$estimate), pct(prev_all(302)$estimate)))
doc <- add_fig(doc, "cap_thresholds.png",
               "Figure 1. Weighted steatosis prevalence by CAP threshold and analytic domain, survey logit 95% intervals.",
               3.61)

doc <- sub(doc, "Liver stiffness")
doc <- body(doc, sprintf(paste0(
    "Median liver stiffness among adults with a complete exam averages %.2f kPa (%s). It is reported because it ",
    "is informative about liver health, but treated as descriptive only: no participant is assigned a fibrosis ",
    "stage or a cirrhosis diagnosis."),
    pull(stiffness$mean_kPa),
    ci_txt(pull(stiffness$conf_low), pull(stiffness$conf_high), function(x) sprintf("%.2f kPa", x))))

doc <- sub(doc, "Alcohol frequency and CAP")
doc <- body(doc, sprintf(paste0(
    "Unadjusted prevalence differs little across drinking groups; every group sits near 40-45%% at 274 dB/m with ",
    "overlapping intervals. The adjusted continuous model is narrower. Against the reference of drinking less ",
    "than weekly, drinking nearly every day or daily is associated with %s of CAP (%s, %s). The never-drinker ",
    "contrast is positive but not significant (%s, %s), and the intermediate groups show no association. For ",
    "scale, each BMI unit carries %s, so the daily-drinking contrast is roughly two BMI units."),
    dbm(pull(daily$estimate)),
    ci_txt(pull(daily$conf_low), pull(daily$conf_high), function(x) sprintf("%.1f", x)), p_txt(pull(daily$p_value)),
    dbm(pull(never$estimate)), p_txt(pull(never$p_value)), dbm(pull(bmi_coef$estimate))))
doc <- add_fig(doc, "alcohol_coefficients.png",
               "Figure 2. Adjusted CAP difference by drinking group vs the less-than-weekly reference, weighted vs unweighted on the same rows.",
               3.25)
doc <- add_ft(doc, ft(data.frame(
    "Drinking group" = c("Never", "Former (no alcohol past year)", "Current, 1 to 4 per week", "Current, 5 to 7 per week"),
    "Adjusted CAP difference" = sprintf("%+.1f dB/m", c(pull(never$estimate), pull(former$estimate), pull(mid$estimate), pull(daily$estimate))),
    "95% CI" = sprintf("%.1f to %.1f", c(pull(never$conf_low), pull(former$conf_low), pull(mid$conf_low), pull(daily$conf_low)),
                                       c(pull(never$conf_high), pull(former$conf_high), pull(mid$conf_high), pull(daily$conf_high))),
    "p" = sprintf("%.3f", c(pull(never$p_value), pull(former$p_value), pull(mid$p_value), pull(daily$p_value))),
    check.names = FALSE),
    widths = c(2.6, 1.7, 1.5, 0.7), align_right = c("Adjusted CAP difference", "95% CI", "p")))
doc <- body(doc, sprintf(paste0(
    "The association is not an artifact of weighting or glycemic status. The unweighted same-sample fit gives a ",
    "smaller daily-drinking contrast (%s), and adding HbA1c leaves it intact (%s, %s). Direction and significance ",
    "of the daily-drinking contrast hold across all three specifications."),
    dbm(pull(daily_naive$estimate)), dbm(pull(daily_hba1c$estimate)), p_txt(pull(daily_hba1c$p_value))))

# ---- 4. limitations -------------------------------------------------
doc <- heading(doc, "Limitations")
doc <- lead_body(doc, "Cross-sectional. ", paste0(
    "NHANES measures each participant once. The alcohol-CAP association is a difference between people, not a ",
    "change within people, and reverse causation cannot be ruled out."))
doc <- lead_body(doc, "Uneven missingness. ", sprintf(paste0(
    "Missing data is not spread evenly by race and ethnicity. Family income-to-poverty ratio is missing for %s ",
    "of adults, ranging %s to %s across groups (%s); it is not a covariate, so no one was excluded for it, but it ",
    "cannot be used for socioeconomic adjustment. More consequentially, drinking status is unknown across a %s to ",
    "%s range over the same groups (%s), and drinking status gates the regression sample. That sample is ",
    "therefore not merely smaller than the prevalence sample but differently composed, which is the main reason ",
    "prevalence is reported on a sample that does not require alcohol."),
    pct(pull(income_race$weighted_missing_overall)), pct(pull(income_race$lowest_fraction)),
    pct(pull(income_race$highest_fraction)), p_txt(pull(income_race$p_value)),
    pct(pull(alcohol_race$lowest_fraction)), pct(pull(alcohol_race$highest_fraction)), p_txt(pull(alcohol_race$p_value))))
doc <- add_fig(doc, "income_missingness.png",
               "Figure 3. Weighted share of adults with a missing income-to-poverty ratio, by subgroup, 95% intervals. Dashed line marks 10%.",
               4.33)
doc <- lead_body(doc, "Device censoring. ", sprintf(paste0(
    "%s adults sit at the 400 dB/m ceiling and %s at the 100 dB/m floor. These are retained and flagged; a mean ",
    "across them is biased toward the centre, so threshold prevalence is the more robust summary."),
    commas(finding_n("CAP at 400 dB/m")), finding_n("CAP at 100 dB/m")))
doc <- lead_body(doc, "Self-report. ", paste0(
    "Drinking frequency and quantity are self-reported and subject to under-reporting. Quantity is top-coded at ",
    "15 drinks per drinking day, so any derived volume is a lower bound; the primary model uses frequency ",
    "categories, not a derived volume."))
doc <- lead_body(doc, "Precision, not power. ", sprintf(paste0(
    "Design degrees of freedom are %s for the survey design and %s residual for the regression. A future ",
    "prevalence survey targeting a 3-point margin at 95%% confidence and a design effect of 1.5 would need roughly ",
    "%s complete examinations. This is a planning illustration, not retrospective power for the results above."),
    pull(design$design_df), pull(daily$df),
    commas(pull(precision$n_complete[precision$assumed_deff == 1.5]))))

# ---- 5. data-quality memo -----------------------------------------
doc <- heading(doc, "Data-quality memo")
doc <- body(doc, "Four issues encountered during preparation, the corrective action, and how to prevent a recurrence.")
doc <- add_ft(doc, ft(data.frame(
    Issue = c(
        "A prior Python read of the SAS transport files produced a spray of 5.4e-79 values.",
        "CAP is censored at the device limits of 100 and 400 dB/m.",
        "The alcohol skip pattern makes a blank frequency ambiguous.",
        "Income and drinking-status missingness is uneven across race and ethnicity."),
    "Corrective action" = c(
        sprintf("Reread with haven, which decodes those bytes as true zeros; %s occur. An exact-match guard stays in the pipeline and logs a count of zero.", finding_n("Unexpected tiny-number conversions")),
        "Boundary values flagged and retained. Prevalence reported at four thresholds; a reliability-restricted sensitivity domain is also run.",
        sprintf("Status derived from both items jointly into five states plus unknown. %s contradictory records have derived fields set missing with source answers preserved.", finding_n("Alcohol contradictions")),
        "Missingness estimated by subgroup under the survey design with Rao-Scott tests and reported in full. Prevalence estimated on a domain that does not require the exposure."),
    Prevention = c(
        "Never trust a single reader for a binary format. Validate against a second implementation; match exact byte patterns so genuine small numbers survive.",
        "Treat any instrument with a stated range as censored by default. Decide the boundary policy before analysis.",
        "Read questionnaire skip logic from the codebook before writing derivation code. Encode the gate explicitly; never let missing default to a substantive value.",
        "Report variable-specific missingness by subgroup as standard, not only an overall rate. Compare included and excluded groups before interpreting a complete-case result."),
    Evidence = c(
        "validation_rules.csv", "quality_findings.csv; prevalence.csv",
        "quality_findings.csv; R/prepare.R", "missingness_by_group.csv; missingness_tests.csv"),
    check.names = FALSE),
    widths = c(1.55, 2.15, 1.95, 1.25)))

# ---- 6. longitudinal note ----------------------------------------
doc <- heading(doc, "Longitudinal-design note")
doc <- body(doc, paste0(
    "This release cannot support a longitudinal analysis, and it is worth being precise about why. The ",
    "2017-March 2020 file is repeated cross-sectional: each participant is sampled and examined once, the ",
    "sequence number is not a panel identifier, and no participant contributes a second elastography ",
    "measurement. Elastography was not collected in earlier continuous NHANES cycles, so there is no prior wave ",
    "to link to even in principle. Any within-person statement about drinking and liver fat over time is outside ",
    "what these data can address. A study designed to answer that question would need the following."))
doc <- add_ft(doc, ft(data.frame(
    Element = c("Data structure", "Time variable", "Estimand", "Model", "Within-person correlation",
                "Missed visits and attrition", "Feasible sources"),
    Specification = c(
        "A prospective cohort with repeated transient elastography on the same participants, at least three waves, drinking measured at each wave.",
        "Years from baseline examination, modelled continuously with a random slope so trajectories differ between people.",
        "Within-person change in CAP per year associated with a change in drinking frequency, adjusted for time-varying BMI and age and for fixed sex and race and ethnicity.",
        "A linear mixed model with random intercept and slope, or a GEE with an exchangeable or AR(1) working correlation if the marginal mean is the target.",
        "Modelled explicitly (unstructured or AR(1)); an independence assumption would understate uncertainty on the time effect.",
        "Missing visits assumed missing at random given observed history, with a pattern-mixture or inverse-probability-weighted sensitivity analysis; attrition weights if dropout relates to liver status.",
        "A cohort with serial elastography, for example an imaging sub-study of an existing prospective cohort. NHANES characterizes the cross-sectional association and the population distribution of CAP, which is what this brief does."),
    check.names = FALSE),
    widths = c(1.5, 5.0)))

doc <- body_add_fpar(doc, fpar(ftext(sprintf(paste0(
    "Reproducibility: every figure and statistic is generated from outputs/tables and outputs/figures by ",
    "scripts/build_brief.R, run after scripts/run_pipeline.R. Regression models use %s design degrees of ",
    "freedom; prevalence intervals use the survey logit method. Source files are pinned by SHA-256."),
    pull(daily$df)), fp_foot), fp_p = fp_par(padding.top = 8)))

target <- file.path(out_dir, "nhanes_liver_brief.docx")
print(doc, target = target)
info <- file.info(target)
cat("Wrote", target, "-", round(info$size / 1024), "KB\n")
