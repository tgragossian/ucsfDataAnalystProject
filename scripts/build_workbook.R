# Builds the Excel handoff workbook from the pipeline outputs.
#
# Everything in this file is presentation. No estimate is calculated here: every
# number, including the ones written into the notes, is read back out of
# outputs/tables, so the prose cannot drift away from the tables it describes.
# The workbook carries the raw tables in full rather than a curated selection,
# because the person using it decides what matters clinically, not this pipeline.
#
# Run after scripts/run_pipeline.R:  Rscript scripts/build_workbook.R
suppressPackageStartupMessages(library(openxlsx))

table_dir <- "outputs/tables"
out_dir <- "outputs/excel_handoff"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

read_table <- function(name)
    read.csv(file.path(table_dir, paste0(name, ".csv")), stringsAsFactors = FALSE)

# Quote the pipeline rather than a memory of it: one value, or a loud failure.
pull <- function(values) {
    stopifnot(length(values) == 1)
    values
}
count <- function(x) formatC(x, format = "d", big.mark = ",")
pct <- function(x, digits = 1) sprintf(paste0("%.", digits, "f%%"), 100 * x)
p_display <- function(p)
    ifelse(is.na(p), "not applicable",
           ifelse(p < 0.001, formatC(p, format = "e", digits = 1), sprintf("%.3f", p)))

ink <- "#222222"; navy <- "#1F4E78"; deep <- "#17365D"
style_title <- createStyle(fontName = "Aptos", fontSize = 15, textDecoration = "bold", fontColour = deep, valign = "center")
style_note  <- createStyle(fontName = "Aptos", fontSize = 10, textDecoration = "italic", fontColour = "#666666", wrapText = TRUE, valign = "center")
style_head  <- createStyle(fgFill = navy, fontColour = "#FFFFFF", textDecoration = "bold", fontName = "Aptos", fontSize = 10, halign = "center", valign = "center", wrapText = TRUE)
style_body  <- createStyle(fontName = "Aptos", fontSize = 10, fontColour = ink, valign = "center")
style_label <- createStyle(fontName = "Aptos", fontSize = 10, textDecoration = "bold", fontColour = deep, valign = "top", wrapText = TRUE)
style_text  <- createStyle(fontName = "Aptos", fontSize = 10, fontColour = ink, valign = "top", wrapText = TRUE)
style_block <- createStyle(fontName = "Aptos", fontSize = 11, textDecoration = "bold", fontColour = deep, valign = "center")

# A sheet holds one set of column widths no matter how many tables are stacked on
# it, so prose is merged across the sheet instead of trusting one column to be wide.
# nchar(NA) is NA, and an NA row height writes ht="NA" into the sheet, which is
# the kind of thing Excel offers to repair. A blank cell is zero characters tall.
lines_high <- function(text, chars) {
    text[is.na(text)] <- ""
    pmax(17, 13.5 * ceiling(nchar(text) / chars))
}

start_sheet <- function(wb, sheet, title, note, colour, span = 2, chars = 116) {
    addWorksheet(wb, sheet, tabColour = colour)
    showGridLines(wb, sheet, showGridLines = FALSE)
    writeData(wb, sheet, title, startCol = 1, startRow = 1)
    writeData(wb, sheet, note, startCol = 1, startRow = 2)
    if (span > 1) {
        mergeCells(wb, sheet, cols = 1:span, rows = 1)
        mergeCells(wb, sheet, cols = 1:span, rows = 2)
    }
    addStyle(wb, sheet, style_title, rows = 1, cols = 1)
    addStyle(wb, sheet, style_note, rows = 2, cols = 1)
    setRowHeights(wb, sheet, rows = 1:2, heights = c(26, lines_high(note, chars + 30)))
}

block <- function(wb, sheet, text, row) {
    writeData(wb, sheet, text, startCol = 1, startRow = row)
    addStyle(wb, sheet, style_block, rows = row, cols = 1)
    invisible(row + 1)
}

add_table <- function(wb, sheet, data, row, formats = character(0), width = NULL, freeze = TRUE,
                      tag = NULL, wrap = NULL, wrap_chars = 100) {
    tag <- if (is.null(tag)) gsub("[^A-Za-z0-9]", "", sheet) else tag
    writeDataTable(wb, sheet, data, startRow = row, tableStyle = "TableStyleMedium2",
                   withFilter = TRUE, headerStyle = style_head, tableName = tag, bandedRows = TRUE)
    body <- seq(row + 1, row + nrow(data))
    addStyle(wb, sheet, style_body, rows = body, cols = seq_along(data), gridExpand = TRUE, stack = TRUE)
    for (column in names(formats)) {
        at <- match(column, names(data))
        if (!is.na(at))
            addStyle(wb, sheet, createStyle(numFmt = formats[[column]]), rows = body, cols = at, gridExpand = TRUE, stack = TRUE)
    }
    if (!is.null(wrap)) {
        at <- match(wrap, names(data))
        addStyle(wb, sheet, createStyle(wrapText = TRUE, valign = "top"), rows = body, cols = at,
                 gridExpand = TRUE, stack = TRUE)
        setRowHeights(wb, sheet, rows = body, heights = lines_high(data[[at]], wrap_chars))
    }
    if (!is.null(width)) setColWidths(wb, sheet, cols = seq_along(data), widths = width)
    setRowHeights(wb, sheet, rows = row, heights = 34)
    if (freeze) freezePane(wb, sheet, firstActiveRow = row + 1)
    invisible(row + nrow(data) + 3)
}

# Written guidance: a label column, and prose merged across the rest of the sheet.
add_notes <- function(wb, sheet, notes, row, span = 2, chars = 116) {
    writeData(wb, sheet, notes, startRow = row, headerStyle = style_head)
    body <- seq(row + 1, row + nrow(notes))
    if (span > 2) for (at in c(row, body)) mergeCells(wb, sheet, cols = 2:span, rows = at)
    addStyle(wb, sheet, style_label, rows = body, cols = 1, gridExpand = TRUE)
    addStyle(wb, sheet, style_text, rows = body, cols = 2, gridExpand = TRUE)
    setRowHeights(wb, sheet, rows = row, heights = 22)
    setRowHeights(wb, sheet, rows = body, heights = lines_high(notes[[2]], chars))
    invisible(row + nrow(notes) + 2)
}

# openxlsx declares a drawing and a VML relationship on every worksheet but never
# writes those parts. Excel ignores them, because no sheet element points at them,
# but the package is not valid and a strict reader refuses to open it. Drop any
# relationship whose target part is not actually in the file.
prune_dangling_relationships <- function(path) {
    parts <- utils::unzip(path, list = TRUE)$Name
    parts <- c("[Content_Types].xml", setdiff(parts, "[Content_Types].xml"))
    staging <- file.path(tempdir(), "workbook_parts")
    unlink(staging, recursive = TRUE)
    utils::unzip(path, exdir = staging)
    dropped <- 0
    for (rel in grep("\\.rels$", parts, value = TRUE)) {
        file <- file.path(staging, rel)
        text <- paste(readLines(file, warn = FALSE), collapse = "")
        base <- dirname(dirname(rel))
        for (entry in regmatches(text, gregexpr("<Relationship [^>]*/>", text))[[1]]) {
            if (grepl('TargetMode="External"', entry, fixed = TRUE)) next
            target <- sub('.*Target="([^"]*)".*', "\\1", entry)
            resolved <- sub("^\\./", "", gsub("[^/]+/\\.\\./", "", file.path(base, target)))
            if (!(resolved %in% parts)) {
                text <- sub(entry, "", text, fixed = TRUE)
                dropped <- dropped + 1
            }
        }
        writeLines(text, file)
    }
    if (dropped > 0) zip::zip(normalizePath(path, winslash = "/", mustWork = FALSE), files = parts, root = staging)
    dropped
}

excl <- read_table("exclusion_log")
cascade_sql <- read_table("sql_cascade")
validation <- read_table("validation_rules")
quality <- read_table("quality_findings")
prevalence <- read_table("prevalence")
models <- read_table("models")
stiffness <- read_table("liver_stiffness")
partial <- read_table("partial_exam_reasons")
missing_inout <- read_table("missingness")
missing_group <- read_table("missingness_by_group")
missing_tests <- read_table("missingness_tests")
benchmark <- read_table("benchmark")
design <- read_table("design_summary")
precision <- read_table("precision_planning")
dictionary <- read_table("data_dictionary")
manifest <- read_table("source_manifest")
master <- read.csv("data/processed/nhanes_master.csv", stringsAsFactors = FALSE)

regression <- excl[excl$cascade == "Primary regression", ]
step_n <- function(name) pull(regression$n_remaining[regression$step == name])
step_out <- function(name) pull(regression$n_excluded[regression$step == name])
released <- step_n("Full DEMO")
finding <- function(issue) pull(quality$n[quality$issue == issue])

test_at <- function(variable, group_variable)
    missing_tests[missing_tests$domain == "adult_mec" & missing_tests$variable == variable &
                  missing_tests$group_variable == group_variable, ]
prevalence_all <- function(threshold)
    pull(prevalence$estimate[prevalence$domain == "primary_cap" &
                             prevalence$threshold == threshold & prevalence$alcohol_group == "All"])

income <- test_at("INDFMPIR", "race")
alcohol_missing <- test_at("alcohol_group", "race")
hba1c_missing <- test_at("LBXGH", "race")
bmi_missing <- test_at("BMXBMI", "race")
prevalence_274 <- prevalence[prevalence$domain == "primary_cap" & prevalence$threshold == 274 &
                             prevalence$alcohol_group == "All", ]
daily <- models[models$model == "primary" & models$term == "alcohol_groupCurrent 5 to 7 per week", ]

sheet_guide <- data.frame(
    Sheet = c("Read Me", "Summary", "Data Loss", "Validation QC", "Quality Findings",
              "Alcohol Notes", "Liver CAP Notes", "Bias Notes",
              "Missingness In vs Out", "Missingness By Group", "Missingness Tests",
              "Prevalence", "Models", "Liver Stiffness", "Partial Exam Reasons",
              "Benchmark", "Design and Precision", "Data Dictionary", "Source Manifest", "Master Data"),
    Purpose = c(
        "This page. What the workbook is, how it was built, and what each sheet holds.",
        "The headline numbers, on one screen.",
        "Every participant who leaves the analysis: at which step, on what criterion, and how many remain. Both cascades, plus the independent SQL rebuild of the same counts.",
        "Every source variable checked against its published codebook domain, with counts of what was refused, what was invalid, and what range survived.",
        "Data-quality issues found and the action taken for each, including the ones deliberately not fixed by deletion.",
        "How drinking status was derived from two questions with a skip pattern, why never-drinkers and non-responders are not the same thing, and what the grams-per-day figure does and does not mean.",
        "What CAP measures, why the device floor and ceiling are kept rather than dropped, how exam quality was judged, and why liver stiffness is descriptive only.",
        "Who is missing from the data, and whether they are missing evenly. Read this before drawing any conclusion about a subgroup.",
        "Weighted missingness and covariate profile, comparing participants who stayed in each analytic sample against those who left it.",
        "Weighted missingness by sex, race/ethnicity, and age group, inside each analytic sample. This is the socioeconomic bias evidence.",
        "Rao-Scott survey-adjusted tests of whether those subgroup differences in missingness are larger than sampling noise.",
        "Survey-weighted prevalence of CAP above each threshold, by analytic domain and by drinking group.",
        "Survey-weighted regression of CAP on drinking group and covariates, with an unweighted same-sample comparison.",
        "Descriptive survey-weighted liver stiffness. Not a fibrosis diagnosis.",
        "Why elastography exams were recorded as partial, among adults who still produced a usable CAP value.",
        "Independent validation of the survey design against a published national obesity estimate.",
        "Survey design size and degrees of freedom, plus an assumption-based precision illustration for planning.",
        "Definition, source file, type, and units for every column in the master dataset.",
        "Source URLs, row counts, SHA256 checksums, and retrieval times for the five CDC files.",
        "The full cleaned dataset, one row per released participant, with every cleaning and eligibility flag so any sample in this workbook can be rebuilt by filtering."),
    stringsAsFactors = FALSE)

wb <- createWorkbook()

# ---- Read Me ------------------------------------------------------------
start_sheet(wb, "Read Me", "NHANES Liver Health - Analyst Handoff",
            "NHANES 2017-March 2020 pre-pandemic release. Built from the pipeline outputs by scripts/build_workbook.R; rerun that after any change, so this file cannot disagree with the analysis.", navy)
row <- add_notes(wb, "Read Me", data.frame(
    Item = c("What this is", "What it is not", "Every population number is weighted",
             "Raw counts are kept beside them", "Where the numbers come from",
             "How to rebuild it", "Start here", "The caveat that changes conclusions"),
    Detail = c(
        sprintf("A cleaned, documented extract of five NHANES files joined on participant ID, covering %s released participants, with the cleaning decisions and the analysis outputs sitting beside the data.", count(released)),
        "Not a clinical dataset and not a diagnosis. CAP above a threshold is a measurement, not a diagnosis of fatty liver disease, and every association here is cross-sectional.",
        sprintf("NHANES is a complex probability sample, so a raw row count is not a population. Every percentage and every interval in this workbook uses the MEC examination weight (WTMECPRP) with the sampling strata (SDMVSTRA) and pseudo-PSUs (SDMVPSU), Taylor linearized, on %s design degrees of freedom. Nothing here is a simple headcount percentage.", pull(design$design_df)),
        "Wherever a weighted percentage appears, the unweighted n it came from is in a nearby column. They will not match, and they are not supposed to: the weighted figure describes the country, the count describes the sample.",
        "Every sheet names the CSV it was written from. Those CSVs are the pipeline output in outputs/tables, and the row-level data behind all of them is on Master Data.",
        "Rscript scripts/run_pipeline.R, then Rscript scripts/build_workbook.R.",
        "Data Loss if you want to know who is not here. Bias Notes if you want to know whether that matters. Summary if you just want the answer.",
        "Missing data is not spread evenly across race and ethnicity, and one of the affected variables is drinking status, which gates the regression sample. See Bias Notes before reporting any subgroup result."),
    stringsAsFactors = FALSE), 4)
row <- block(wb, "Read Me", "Sheet guide", row)
add_table(wb, "Read Me", sheet_guide, row, tag = "SheetGuide", freeze = FALSE, wrap = "Purpose", wrap_chars = 116)
setColWidths(wb, "Read Me", cols = 1:2, widths = c(32, 116))

# ---- Summary ------------------------------------------------------------
start_sheet(wb, "Summary", "Summary",
            "Headline results. Every percentage is survey weighted. Source: outputs/tables.", navy)
add_notes(wb, "Summary", data.frame(
    Item = c("Question", "Primary outcome", "Primary exposure", "Analysis samples",
             "Steatosis prevalence", "Alcohol and CAP", "Design validation",
             "Data loss", "Socioeconomic bias", "Interpretation limit"),
    Detail = c(
        "How common is CAP-defined hepatic steatosis among US adults, and does it track self-reported drinking frequency?",
        "Controlled attenuation parameter (CAP), median value in dB/m, from transient elastography. Continuous in the model, and above a threshold for prevalence.",
        "A five-level drinking frequency group built from two questionnaire items, keeping never-drinkers, past-year non-drinkers, and non-responders separate from one another.",
        sprintf("%s adults with a complete elastography exam and a usable CAP value for prevalence; %s of those also had drinking status and every model covariate, and that is the regression sample.",
                count(step_n("Complete exam")), count(step_n("Complete model covariates"))),
        sprintf("%s of adults at CAP >= 274 dB/m (95%% CI %s to %s). The threshold is reported four ways, 248 to 302 dB/m, because the answer moves from %s to %s across that range and no single cut point is settled.",
                pct(pull(prevalence_274$estimate)), pct(pull(prevalence_274$conf_low)), pct(pull(prevalence_274$conf_high)),
                pct(prevalence_all(248)), pct(prevalence_all(302))),
        sprintf("Drinking nearly every day is associated with %+.1f dB/m of CAP against drinking less than weekly (95%% CI %.1f to %.1f, p = %s), adjusting for BMI, age, sex, and race/ethnicity. An association in a single snapshot, not an effect.",
                pull(daily$estimate), pull(daily$conf_low), pull(daily$conf_high), p_display(pull(daily$p_value))),
        sprintf("Age-standardized adult obesity rebuilt from this design lands at %s against the published %s, inside the published rounding precision. The pipeline stops if it does not.",
                pct(pull(benchmark$estimate), 2), pct(pull(benchmark$published_estimate), 1)),
        sprintf("%s of %s released participants reach the regression sample. The largest single loss is age: %s participants are under 18 and this is an adult analysis. See Data Loss.",
                count(step_n("Complete model covariates")), count(released), count(step_out("Adult MEC"))),
        sprintf("Income-to-poverty ratio is missing for %s of adults, ranging %s to %s across race and ethnicity. Drinking status is unknown across a %s to %s range over the same groups, and that variable gates the regression sample. See Bias Notes.",
                pct(pull(income$weighted_missing_overall)), pct(pull(income$lowest_fraction)), pct(pull(income$highest_fraction)),
                pct(pull(alcohol_missing$lowest_fraction)), pct(pull(alcohol_missing$highest_fraction))),
        "Cross-sectional associations only. No causal claim, no clinical diagnosis, no individual-level risk statement."),
    stringsAsFactors = FALSE), 4)
setColWidths(wb, "Summary", cols = 1:2, widths = c(32, 116))

# ---- Data Loss ----------------------------------------------------------
loss <- do.call(rbind, lapply(split(excl, excl$cascade), function(part) {
    start <- part$n_remaining[1]
    part$cumulative_excluded <- start - part$n_remaining
    part$share_lost_at_step <- part$n_excluded / (part$n_remaining + part$n_excluded)
    part$share_of_release_remaining <- part$n_remaining / start
    part
}))
rownames(loss) <- NULL

start_sheet(wb, "Data Loss", "Data Loss and Exclusions",
            "Where participants leave the analysis and why. The first five columns are exactly as the pipeline wrote them; the last three are arithmetic on those. Source: outputs/tables/exclusion_log.csv and sql_cascade.csv.",
            "#ED7D31", span = 8, chars = 150)
row <- add_notes(wb, "Data Loss", data.frame(
    Item = c("Two cascades, on purpose", "Nothing is dropped on the outcome",
             "The order matters", "Independent check"),
    Detail = c(
        "Prevalence and regression answer different questions, so they exclude on different rules. Prevalence does not require drinking status or covariates, because requiring them would shrink and reshape the sample for no descriptive gain. Only the regression needs a complete case.",
        "No participant is excluded for having a high or a low CAP value. Excluding on the size of the outcome would delete the disease. Device boundary values are flagged and kept: see Liver CAP Notes.",
        sprintf("The steps are nested, so a participant is counted once, at the first rule that removes them. Age removes the most (%s), then the %s adults with no usable CAP value, then the %s whose exam was only partial.",
                count(step_out("Adult MEC")), count(step_out("CAP available")), count(step_out("Complete exam"))),
        "The SQL block below rebuilds the same counts from the database with its own queries, not from the R objects. If the two ever disagree, one of them is wrong, and the pipeline should not be trusted until they agree again."),
    stringsAsFactors = FALSE), 4, span = 8, chars = 150)
row <- block(wb, "Data Loss", "Exclusion cascade (R)", row)
row <- add_table(wb, "Data Loss", loss, row,
                 formats = c(n_remaining = "#,##0", n_excluded = "#,##0", cumulative_excluded = "#,##0",
                             share_lost_at_step = "0.0%", share_of_release_remaining = "0.0%"),
                 tag = "DataLoss")
row <- block(wb, "Data Loss", "Same cascade, rebuilt independently in SQL", row)
add_table(wb, "Data Loss", cascade_sql, row, formats = c(n = "#,##0"), tag = "SqlCascade", freeze = FALSE)
setColWidths(wb, "Data Loss", cols = 1:8, widths = c(30, 26, 46, 14, 14, 16, 16, 18))

# ---- Validation QC ------------------------------------------------------
start_sheet(wb, "Validation QC", "Cleaning and Validation",
            "Every source variable against its published codebook domain. A value outside its domain becomes missing and is counted here; no row is ever deleted, and the original value stays readable in the SQLite domain tables. Source: outputs/tables/validation_rules.csv.",
            "#ED7D31", span = 16, chars = 191)
row <- add_notes(wb, "Validation QC", data.frame(
    Item = c("Where the rules live", "Refusals are counted separately",
             "What actually changed", "Real categories that look like codes"),
    Detail = c(
        "The allowed values, bounds, and missing codes for every variable are in config/variables.csv, not buried in the analysis code, so adding a variable means adding a row there. docs/reference-documentation.md explains each one against the CDC codebook.",
        "Refused and do-not-know answers (7/9, 77/99, 777/999) are counted in n_refused_dk, apart from n_invalid_to_missing. They mean different things: one is a person declining to answer, the other is a value that should not exist.",
        sprintf("n_invalid_to_missing is zero for every variable in this release, which is the evidence that the rules are not quietly culling real data. The only conversions were %s refusal codes turned into missing.",
                count(sum(validation$n_refused_dk))),
        "Race code 7 (other or multiracial) and age 80 are genuine categories, not missing codes, and are kept. Age 80 is a top-code covering everyone aged 80 and over, and is flagged as age80 in the master data so it can be modelled or excluded deliberately."),
    stringsAsFactors = FALSE), 4, span = 16, chars = 191)
add_table(wb, "Validation QC", validation, row,
          formats = c(n_rows = "#,##0", n_missing_source = "#,##0", artifact_conversions = "#,##0",
                      n_refused_dk = "#,##0", n_invalid_to_missing = "#,##0", n_missing_final = "#,##0"),
          tag = "ValidationQC")
setColWidths(wb, "Validation QC", cols = 1:16,
             widths = c(26, 12, 12, 18, 8, 8, 9, 14, 10, 16, 16, 14, 18, 14, 11, 11))

# ---- Quality Findings ---------------------------------------------------
start_sheet(wb, "Quality Findings", "Quality Findings",
            "Issues found during cleaning and what was done about each. Source: outputs/tables/quality_findings.csv.",
            "#ED7D31", span = 3, chars = 102)
row <- add_notes(wb, "Quality Findings", data.frame(
    Item = c("Flag, do not delete", "The tiny-number artifact"),
    Detail = c(
        "Every issue below is recorded and flagged in the master data rather than removed from it. A reader who disagrees with one of these calls can filter on the flag and redo the analysis their way, which is not possible once rows have been deleted.",
        sprintf("An earlier Python read of these files produced a spray of 5.397605e-79 values, which is what eight zero bytes look like when decoded as a floating point number. Reading the same files with haven produced %s of them: they were true zeros all along, and it was a reader problem, not a data problem. The exact-match normalization stays in the pipeline as a guard, and logs its count of zero as the evidence.",
                count(finding("Unexpected tiny-number conversions")))),
    stringsAsFactors = FALSE), 4, span = 3, chars = 102)
add_table(wb, "Quality Findings", quality, row, formats = c(n = "#,##0"), tag = "QualityFindings", wrap = "action", wrap_chars = 92)
setColWidths(wb, "Quality Findings", cols = 1:3, widths = c(30, 10, 92))

# ---- Alcohol Notes ------------------------------------------------------
alcohol_counts <- prevalence[prevalence$domain == "primary_cap" & prevalence$threshold == 274 &
                             prevalence$alcohol_group != "All",
                             c("alcohol_group", "n", "estimate", "conf_low", "conf_high")]
names(alcohol_counts) <- c("Drinking group", "Adults in primary CAP sample",
                           "Weighted share at CAP >= 274", "CI low", "CI high")
rownames(alcohol_counts) <- NULL

skip_logic <- data.frame(
    "ALQ111 - ever had a drink" = c("2 = no", "1 = yes", "1 = yes", "1 = yes", "1 = yes",
                                    "7, 9, or missing", "1 = yes"),
    "ALQ121 - past year frequency" = c("not asked, skipped", "0 = none in the past year",
                                       "6 to 10 = monthly or less often", "3 to 5 = one to four times a week",
                                       "1 to 2 = daily or nearly daily", "any answer", "77, 99, or missing"),
    "Derived alcohol_group" = c("Never", "Former", "Current under 1 per week",
                                "Current 1 to 4 per week", "Current 5 to 7 per week",
                                "blank, treated as Unknown", "blank, treated as Unknown"),
    "Why" = c("The skip is the answer. They were never asked the frequency question because they said they had never had a drink.",
              "A lifetime drinker who did not drink in the past year. Collapsing this into Never would misclassify people who may have stopped for health reasons.",
              "Reference group in the regression, chosen because it is the largest and because it is a drinking group rather than an abstaining one.",
              NA, NA,
              "The gate question was refused or unknown, so the frequency answer cannot be placed on the scale. Not folded into Never.",
              "The frequency was refused or unknown. No group is assigned and the participant leaves the regression sample, but stays in prevalence."),
    check.names = FALSE, stringsAsFactors = FALSE)

grams_assumptions <- data.frame(
    "ALQ121 code" = 0:10,
    "Meaning" = c("Never in the last year", "Every day", "Nearly every day", "3 to 4 times a week",
                  "2 times a week", "Once a week", "2 to 3 times a month", "Once a month",
                  "7 to 11 times in the last year", "3 to 6 times in the last year",
                  "1 to 2 times in the last year"),
    "Drinking days per year assumed" = c(0, 365, 330, 182, 104, 52, 30, 12, 9, 4.5, 1.5),
    check.names = FALSE, stringsAsFactors = FALSE)

start_sheet(wb, "Alcohol Notes", "Alcohol Documentation",
            "How the exposure was built, and the assumptions inside it. Counts from outputs/tables/prevalence.csv and quality_findings.csv.",
            "#7030A0", span = 5, chars = 138)
row <- add_notes(wb, "Alcohol Notes", data.frame(
    Item = c("Two questions, one variable", "Four states, not two",
             "Contradictions", "Top-coded quantity", "The grams per day column",
             "What the groups can support", "The bias that matters here"),
    Detail = c(
        "Drinking status comes from ALQ111 (ever had a drink) and ALQ121 (frequency in the past year). ALQ121 is only asked of people who answered yes to ALQ111, so a blank ALQ121 means two completely different things depending on ALQ111, and reading it alone would be wrong.",
        "Never drank, drank but not in the past year, currently drinks at some frequency, and did not answer are four distinct states. Software that treats a blank as a zero silently merges the first, second, and fourth into the abstainer group, which is exactly the group a liver analysis is most sensitive to.",
        sprintf("A participant who says they never drank but then answers the frequency question is a contradiction. There are %s such records in this release. The rule is written anyway: the derived group and the grams per day both go missing, while the original answers stay untouched in the source columns and in the SQLite tables.",
                count(finding("Alcohol contradictions"))),
        sprintf("ALQ130, drinks per drinking day, is top-coded: 15 means 15 or more. %s participants sit at that code. Any volume computed for them is a lower bound, not a measurement, and the alcohol_topcoded flag marks them in the master data.",
                count(finding("Top-coded drinking quantity"))),
        "alcohol_g_day is supplemental and approximate, not a measured intake. It multiplies the midpoint drinking days per year in the table below by the reported drinks per drinking day by 14 grams of ethanol per US standard drink, divided by 365. Never-drinkers and past-year non-drinkers are recorded as 0. Treat it as an ordering device, not a dose.",
        "The regression uses the five frequency groups, not the grams figure, because the frequency categories are what the participant actually reported. Frequency is not quantity: someone drinking once a week may drink far more per occasion than someone drinking daily.",
        sprintf("Drinking status is unknown for %s of %s adults and %s of %s adults. Because a known drinking status is required to enter the regression, that sample is not simply smaller than the prevalence sample, it is differently composed. See Bias Notes.",
                pct(pull(alcohol_missing$lowest_fraction)), pull(alcohol_missing$lowest_group),
                pct(pull(alcohol_missing$highest_fraction)), pull(alcohol_missing$highest_group))),
    stringsAsFactors = FALSE), 4, span = 5, chars = 138)
row <- block(wb, "Alcohol Notes", "Skip-pattern logic, as implemented", row)
row <- add_table(wb, "Alcohol Notes", skip_logic, row, tag = "AlcoholSkip", freeze = FALSE, wrap = "Why", wrap_chars = 62)
row <- block(wb, "Alcohol Notes", "Drinking groups in the primary CAP sample", row)
row <- add_table(wb, "Alcohol Notes", alcohol_counts, row,
                 formats = c("Adults in primary CAP sample" = "#,##0", "Weighted share at CAP >= 274" = "0.0%",
                             "CI low" = "0.0%", "CI high" = "0.0%"),
                 tag = "AlcoholGroups", freeze = FALSE)
row <- block(wb, "Alcohol Notes", "Midpoint assumptions behind alcohol_g_day", row)
add_table(wb, "Alcohol Notes", grams_assumptions, row, tag = "AlcoholGrams", freeze = FALSE)
setColWidths(wb, "Alcohol Notes", cols = 1:5, widths = c(30, 34, 28, 62, 14))

# ---- Liver CAP Notes ----------------------------------------------------
exam_status <- data.frame(
    "LUAXSTAT" = 1:4,
    "Meaning" = c("Complete exam", "Partial exam", "Not eligible", "Not done"),
    "How it was treated" = c("The primary prevalence and regression samples.",
                             "The broad sensitivity domain only. A partial exam can still produce a usable CAP value, so these are kept as a sensitivity check rather than discarded.",
                             "Excluded. Ineligibility is recorded in LUARXIN, most often pregnancy.",
                             "Excluded. The reason is recorded in LUARXND."),
    check.names = FALSE, stringsAsFactors = FALSE)

partial_named <- partial
partial_named$meaning <- c("Fasting under 3 hours", "Fewer than 10 valid stiffness measures",
                           "Stiffness IQR over median above 30 percent")[match(partial_named$partial_reason_code, c(1, 2, 3))]

start_sheet(wb, "Liver CAP Notes", "Liver and CAP Documentation",
            "What the liver measurements are, how exam quality was judged, and which boundary decisions were made. Counts from outputs/tables/quality_findings.csv and partial_exam_reasons.csv.",
            "#7030A0", span = 3, chars = 110)
row <- add_notes(wb, "Liver CAP Notes", data.frame(
    Item = c("What CAP is", "The device censors at both ends", "Why boundary values are kept",
             "Exam quality", "The threshold is a choice, not a fact",
             "Liver stiffness is descriptive", "A one-participant difference"),
    Detail = c(
        "Controlled attenuation parameter measures how much an ultrasound signal weakens passing through the liver, which tracks fat content. It is reported as a median in dB/m over the valid measurements in a single exam. It is a measurement of the liver, not a diagnosis of a disease.",
        sprintf("The device reports CAP only within 100 to 400 dB/m. %s adults with a usable CAP sit exactly at the 400 ceiling and %s sit exactly at the 100 floor. Those are censoring points: the true value could lie beyond them, and a mean computed over them is biased toward the middle.",
                count(finding("CAP at 400 dB/m")), count(finding("CAP at 100 dB/m"))),
        "They are flagged (cap_ceiling, cap_floor) and kept. Dropping the highest CAP readings because they are extreme would remove exactly the participants the analysis is about. Anyone who wants them out can filter on the flag.",
        sprintf("The NHANES completeness rule is an interquartile range over median below 30 percent. That ratio is computed for CAP as cap_iqr_ratio and for stiffness as stiffness_iqr_ratio_ok, and the stricter CAP version is run as a sensitivity domain of %s adults rather than being imposed on the primary sample.",
                count(pull(prevalence$n[prevalence$domain == "cap_reliable_sensitivity" & prevalence$threshold == 274]))),
        sprintf("No CAP cut point for steatosis is settled in the literature, so four are reported: 248, 274, 288, and 302 dB/m. Prevalence moves from %s to %s across them. Quoting one number without the others would overstate how precisely this is known.",
                pct(prevalence_all(248)), pct(prevalence_all(302))),
        sprintf("Median liver stiffness averages %.2f kPa (95%% CI %.2f to %.2f) across adults with a complete exam. It is reported because it is informative about liver health, but it is not a fibrosis stage, and no participant here is classified as cirrhotic.",
                pull(stiffness$mean_kPa), pull(stiffness$conf_low), pull(stiffness$conf_high)),
        sprintf("The stiffness sample is %s and the primary CAP sample is %s. One participant produced a usable stiffness reading without a usable CAP reading. Each domain is defined on its own measurement, not on the other one.",
                count(pull(stiffness$n)), count(step_n("Complete exam")))),
    stringsAsFactors = FALSE), 4, span = 3, chars = 110)
row <- block(wb, "Liver CAP Notes", "Exam status codes and how each was treated", row)
row <- add_table(wb, "Liver CAP Notes", exam_status, row, tag = "ExamStatus", freeze = FALSE, wrap = "How it was treated", wrap_chars = 80)
row <- block(wb, "Liver CAP Notes", "Why exams were partial, among adults who still had a usable CAP", row)
add_table(wb, "Liver CAP Notes", partial_named, row, formats = c(n_adults_with_cap = "#,##0"),
          tag = "PartialReasons", freeze = FALSE)
setColWidths(wb, "Liver CAP Notes", cols = 1:3, widths = c(30, 30, 80))

# ---- Bias Notes ---------------------------------------------------------
bias_headline <- data.frame(
    Variable = c("Income-to-poverty ratio", "Drinking status unknown", "HbA1c", "BMI"),
    "Weighted missing, all adults" = c(pull(income$weighted_missing_overall), pull(alcohol_missing$weighted_missing_overall),
                                       pull(hba1c_missing$weighted_missing_overall), pull(bmi_missing$weighted_missing_overall)),
    "Lowest group" = c(pull(income$lowest_group), pull(alcohol_missing$lowest_group),
                       pull(hba1c_missing$lowest_group), pull(bmi_missing$lowest_group)),
    "Lowest rate" = c(pull(income$lowest_fraction), pull(alcohol_missing$lowest_fraction),
                      pull(hba1c_missing$lowest_fraction), pull(bmi_missing$lowest_fraction)),
    "Highest group" = c(pull(income$highest_group), pull(alcohol_missing$highest_group),
                        pull(hba1c_missing$highest_group), pull(bmi_missing$highest_group)),
    "Highest rate" = c(pull(income$highest_fraction), pull(alcohol_missing$highest_fraction),
                       pull(hba1c_missing$highest_fraction), pull(bmi_missing$highest_fraction)),
    "Spread, percentage points" = c(pull(income$difference_pp), pull(alcohol_missing$difference_pp),
                                    pull(hba1c_missing$difference_pp), pull(bmi_missing$difference_pp)),
    "Rao-Scott p" = c(pull(income$p_value), pull(alcohol_missing$p_value),
                      pull(hba1c_missing$p_value), pull(bmi_missing$p_value)),
    check.names = FALSE, stringsAsFactors = FALSE)

start_sheet(wb, "Bias Notes", "Missingness and Socioeconomic Bias",
            "Whether the people missing from this dataset are missing evenly. All rates are survey weighted. Source: outputs/tables/missingness_by_group.csv and missingness_tests.csv.",
            "#C00000", span = 8, chars = 118)
row <- add_notes(wb, "Bias Notes", data.frame(
    Item = c("Why this sheet exists", "How the rates were computed",
             "Why not an ordinary chi-square", "Why the sampling strata are not a group here",
             "Income", "Drinking status, which matters more", "What was done about it",
             "What to do with this"),
    Detail = c(
        "A sample that is smaller than the population is normal and correctable. A sample that is differently composed is a bias, and it does not announce itself in any headline number. This sheet is the check for the second thing.",
        sprintf("For each variable, a 0/1 missing indicator was built and its mean estimated under the full survey design: MEC weights, sampling strata, and pseudo-PSUs, Taylor linearized, on %s design degrees of freedom. These are weighted population rates with proper intervals, not headcount percentages.", pull(design$design_df)),
        "An ordinary chi-square test ignores the weights, the strata, and the clustering, and would report a far smaller p-value than the design supports. Every test here is a Rao-Scott second-order F, which corrects for the design.",
        "SDMVSTRA is a variance-estimation device, not a population subgroup anyone would want a missingness rate for. It is already carrying the uncertainty in every interval on this sheet, so grouping by it would be double-counting the design rather than describing people.",
        sprintf("Income-to-poverty ratio is missing for %s of adults overall, from %s among %s adults to %s among %s adults, a %.1f point spread (p = %s). This is the clearest socioeconomic signal in the dataset, and it exists in the source data: nothing in this pipeline dropped it.",
                pct(pull(income$weighted_missing_overall)), pct(pull(income$lowest_fraction)), pull(income$lowest_group),
                pct(pull(income$highest_fraction)), pull(income$highest_group), pull(income$difference_pp), p_display(pull(income$p_value))),
        sprintf("The same gradient appears in drinking status, and it is larger: unknown for %s of %s adults against %s of %s adults, a %.1f point spread (p = %s). Income is not a model covariate, so nobody was excluded for it. Drinking status is the exposure, so anyone whose status is unknown leaves the regression sample. That is why the regression sample is differently composed and not merely smaller.",
                pct(pull(alcohol_missing$lowest_fraction)), pull(alcohol_missing$lowest_group),
                pct(pull(alcohol_missing$highest_fraction)), pull(alcohol_missing$highest_group),
                pull(alcohol_missing$difference_pp), p_display(pull(alcohol_missing$p_value))),
        "Nothing was imputed and nothing was reweighted to correct it. Two things were done: prevalence is estimated on a domain that does not require drinking status at all, so the descriptive result is not exposed to this; and the missingness is reported here rather than left implicit.",
        "Read the percentage-point spread and the intervals first. The p-value only says the spread is larger than sampling noise; it does not say the spread is large enough to change a decision. Sex and age group are flat throughout, so the pattern is specific to race and ethnicity."),
    stringsAsFactors = FALSE), 4, span = 8, chars = 118)
row <- block(wb, "Bias Notes", "Weighted missingness across race and ethnicity, all adults examined in the MEC", row)
add_table(wb, "Bias Notes", bias_headline, row,
          formats = c("Weighted missing, all adults" = "0.0%", "Lowest rate" = "0.0%",
                      "Highest rate" = "0.0%", "Spread, percentage points" = "0.0",
                      "Rao-Scott p" = "0.0E+00"),
          tag = "BiasHeadline", freeze = FALSE)
setColWidths(wb, "Bias Notes", cols = 1:8, widths = c(28, 16, 24, 12, 24, 12, 16, 14))

# ---- Missingness tables -------------------------------------------------
start_sheet(wb, "Missingness In vs Out", "Missingness: Included vs Excluded",
            "Weighted missingness and covariate profile for participants who stayed in each analytic sample against those who left it. Note that estimate is a weighted mean for continuous variables and a weighted proportion for categories. Source: outputs/tables/missingness.csv.",
            "#C00000", span = 10, chars = 130)
add_table(wb, "Missingness In vs Out", missing_inout, 4,
          formats = c(n_group = "#,##0", n_observed = "#,##0", n_missing = "#,##0",
                      weighted_missing_fraction = "0.0%", missing_conf_low = "0.0%", missing_conf_high = "0.0%",
                      estimate = "0.000", std_error = "0.000", conf_low = "0.000", conf_high = "0.000"),
          width = c(18, 10, 12, 14, 10, 12, 10, 16, 12, 12, 16, 12, 10, 10, 10),
          tag = "MissingnessInOut")

start_sheet(wb, "Missingness By Group", "Missingness by Sex, Race, and Age Group",
            "The socioeconomic bias evidence. Weighted missing rate with 95 percent intervals, for each variable, inside each analytic sample. Source: outputs/tables/missingness_by_group.csv.",
            "#C00000", span = 10, chars = 130)
add_table(wb, "Missingness By Group", missing_group, 4,
          formats = c(n_group = "#,##0", n_missing = "#,##0", weighted_missing_fraction = "0.0%",
                      conf_low = "0.0%", conf_high = "0.0%", design_df = "0"),
          width = c(18, 14, 14, 8, 22, 10, 10, 16, 10, 10, 16, 10),
          tag = "MissingnessByGroup")

start_sheet(wb, "Missingness Tests", "Missingness: Survey-Adjusted Tests",
            "Rao-Scott second-order F tests of the subgroup differences. Read difference_pp and the intervals before the p-value. Rows marked Not applicable are variables the sample rule already requires, so nothing is missing there by construction. Source: outputs/tables/missingness_tests.csv.",
            "#C00000", span = 10, chars = 130)
add_table(wb, "Missingness Tests", missing_tests, 4,
          formats = c(n = "#,##0", weighted_missing_overall = "0.0%", lowest_fraction = "0.0%",
                      highest_fraction = "0.0%", difference_pp = "0.0", statistic = "0.00",
                      ndf = "0.00", ddf = "0.00", p_value = "0.0E+00"),
          width = c(18, 14, 14, 8, 16, 22, 12, 22, 12, 12, 10, 8, 8, 12, 22, 70),
          tag = "MissingnessTests", wrap = "interpretation", wrap_chars = 70)

# ---- Results ------------------------------------------------------------
start_sheet(wb, "Prevalence", "Prevalence",
            "Survey-weighted share of adults above each CAP threshold, by analytic domain and drinking group. Intervals are logit intervals on the survey design. Source: outputs/tables/prevalence.csv.",
            "#5B9BD5", span = 8, chars = 110)
add_table(wb, "Prevalence", prevalence, 4,
          formats = c(n = "#,##0", cases = "#,##0", estimate = "0.0%", std_error = "0.000",
                      conf_low = "0.0%", conf_high = "0.0%", design_df = "0",
                      deff_replace = "0.00", effective_n = "#,##0"),
          width = c(24, 10, 26, 8, 8, 10, 10, 10, 10, 10, 12, 12, 12, 72),
          tag = "Prevalence", wrap = "reliability_rule", wrap_chars = 72)

start_sheet(wb, "Models", "Regression Models",
            "Survey-weighted regression of CAP in dB/m on drinking group and covariates. The reference drinking group is Current under 1 per week. naive_same_sample is the same rows fitted without weights, shown so the design effect is visible rather than assumed. Source: outputs/tables/models.csv.",
            "#5B9BD5", span = 8, chars = 110)
add_table(wb, "Models", models, 4,
          formats = c(estimate = "0.000", std_error = "0.000", conf_low = "0.000",
                      conf_high = "0.000", p_value = "0.0E+00", n = "#,##0", df = "0"),
          width = c(26, 34, 10, 10, 10, 10, 12, 8, 8),
          tag = "Models")

start_sheet(wb, "Liver Stiffness", "Liver Stiffness",
            "Descriptive survey-weighted liver stiffness among adults with a complete exam. Not a fibrosis stage and not a diagnosis. Source: outputs/tables/liver_stiffness.csv.",
            "#5B9BD5", span = 6, chars = 110)
add_table(wb, "Liver Stiffness", stiffness, 4,
          formats = c(n = "#,##0", mean_kPa = "0.00", std_error = "0.000",
                      conf_low = "0.00", conf_high = "0.00"),
          width = c(10, 12, 12, 12, 12, 58), tag = "LiverStiffness", wrap = "interpretation", wrap_chars = 58)

start_sheet(wb, "Partial Exam Reasons", "Partial Exam Reasons",
            "Recorded reason an elastography exam was partial, among adults who still produced a usable CAP value. Source: outputs/tables/partial_exam_reasons.csv.",
            "#5B9BD5", span = 3, chars = 86)
add_table(wb, "Partial Exam Reasons", partial_named, 4, formats = c(n_adults_with_cap = "#,##0"),
          width = c(20, 20, 46), tag = "PartialExamReasons")

# ---- Design and validation ---------------------------------------------
start_sheet(wb, "Benchmark", "Design Benchmark",
            "An independent test of the survey design: age-standardized adult obesity rebuilt from this pipeline against the published national estimate. The pipeline stops if this fails. Source: outputs/tables/benchmark.csv.",
            "#70AD47", span = 8, chars = 110)
add_table(wb, "Benchmark", benchmark, 4,
          formats = c(n = "#,##0", estimate = "0.00%", conf_low = "0.00%", conf_high = "0.00%",
                      published_estimate = "0.00%", absolute_difference = "0.00000",
                      rounding_tolerance = "0.00000", design_df = "0"),
          width = c(60, 8, 10, 10, 10, 16, 16, 16, 8, 10), tag = "Benchmark")

start_sheet(wb, "Design and Precision", "Survey Design and Precision Planning",
            "The design behind every weighted number in this workbook, and a forward-looking precision illustration. Source: outputs/tables/design_summary.csv and precision_planning.csv.",
            "#70AD47", span = 8, chars = 142)
row <- add_notes(wb, "Design and Precision", data.frame(
    Item = c("Reading the design", "The precision table is not a power calculation"),
    Detail = c(
        sprintf("%s MEC-examined participants sit in %s sampling strata across %s pseudo-PSUs, giving %s design degrees of freedom. That last number, not the sample size, is what limits the width of every interval here: %s clustered observations do not buy the precision that the same number of independent observations would.",
                count(pull(design$n_MEC)), pull(design$strata), pull(design$PSUs), pull(design$design_df),
                count(pull(design$n_MEC))),
        "It is an assumption-based illustration of what a future sample would need, at stated design effects and response rates. It is not retrospective power for the results in this workbook, which would only restate the intervals already shown."),
    stringsAsFactors = FALSE), 4, span = 8, chars = 142)
row <- block(wb, "Design and Precision", "Survey design", row)
row <- add_table(wb, "Design and Precision", design, row,
                 formats = c(n_MEC = "#,##0", strata = "0", PSUs = "0", design_df = "0"),
                 tag = "DesignSummary", freeze = FALSE)
row <- block(wb, "Design and Precision", "Precision planning illustration", row)
add_table(wb, "Design and Precision", precision, row,
          formats = c(p = "0.00", margin = "0.00", confidence = "0.00", assumed_deff = "0.0",
                      response = "0.00", n_complete = "#,##0", n_recruit = "#,##0"),
          tag = "PrecisionPlanning", freeze = FALSE, wrap = "interpretation", wrap_chars = 64)
setColWidths(wb, "Design and Precision", cols = 1:8, widths = c(28, 14, 12, 14, 12, 14, 14, 64))

# ---- Reference ----------------------------------------------------------
start_sheet(wb, "Data Dictionary", "Data Dictionary",
            "Every column in the master dataset. Rows sourced from derived are computed by the pipeline; the rest come straight from the named CDC file. Source: outputs/tables/data_dictionary.csv.",
            "#A5A5A5", span = 5, chars = 136)
add_table(wb, "Data Dictionary", dictionary, 4, width = c(28, 12, 10, 14, 100), tag = "DataDictionary", wrap = "description", wrap_chars = 100)

start_sheet(wb, "Source Manifest", "Source Manifest",
            "Provenance for the five CDC files. The SHA256 values are what makes this reproducible: rerunning against a changed file will not silently produce different numbers. Source: outputs/tables/source_manifest.csv.",
            "#A5A5A5", span = 6, chars = 150)
add_table(wb, "Source Manifest", manifest, 4, formats = c(n_rows = "#,##0", n_columns = "#,##0"),
          width = c(12, 10, 10, 58, 58, 68, 68, 22, 12), tag = "SourceManifest")

start_sheet(wb, "Master Data", "Master Dataset",
            sprintf("The full cleaned dataset: %s rows, one per released participant, and %s columns. Filter on primary_cap, regression_primary, broad_cap, or any quality flag to rebuild any sample used in this workbook. Column meanings are on Data Dictionary. Source: data/processed/nhanes_master.csv.",
                    count(nrow(master)), ncol(master)),
            "#A5A5A5", span = 8, chars = 110)
add_table(wb, "Master Data", master, 4, formats = c(SEQN = "0", WTMECPRP = "#,##0.000"),
          width = 15, tag = "MasterData")

# The guide is the table of contents, so it has to name every sheet and no others.
stopifnot(setequal(sheet_guide$Sheet, names(wb)))
target <- file.path(out_dir, "nhanes_liver_handoff.xlsx")
saveWorkbook(wb, target, overwrite = TRUE)
dropped <- prune_dangling_relationships(target)
cat("Wrote", target, "-", length(names(wb)), "sheets,", count(nrow(master)),
    "master rows,", dropped, "dangling relationships pruned\n")
