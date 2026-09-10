source("R/acquire.R")
source("R/prepare.R")
source("R/database.R")
source("R/survey_analysis.R")
for (d in c("data/processed", "outputs/tables", "outputs/figures", "outputs/reports"))
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
csv <- function(x, name) write.csv(x, file.path("outputs/tables", paste0(name, ".csv")), row.names = FALSE, na = "")

sources <- acquire_sources()
prepared <- prepare_data(sources$tables)
master <- prepared$master
write.csv(master, "data/processed/nhanes_master.csv", row.names = FALSE, na = "")
write.csv(master[master$primary_cap, ], "data/processed/liver_analytic.csv", row.names = FALSE, na = "")
saveRDS(prepared, "data/processed/prepared.rds")
csv(sources$manifest, "source_manifest")
csv(prepared$qc, "validation_rules")
csv(prepared$dictionary, "data_dictionary")
csv(prepared$exclusions, "exclusion_log")
csv(build_database(sources$tables, master, "data/processed/nhanes.sqlite"), "sql_cascade")

findings <- data.frame(
 issue = c("Zero examination weights", "Unexpected tiny-number conversions", "CAP at 400 dB/m", "CAP at 100 dB/m", "Partial exams with CAP", "Alcohol contradictions", "Top-coded drinking quantity"),
 n = c(sum(master$WTMECPRP == 0, na.rm = TRUE), sum(prepared$qc$artifact_conversions),
       sum(master$cap_ceiling & master$broad_cap), sum(master$cap_floor & master$broad_cap),
       sum(master$broad_cap & master$LUAXSTAT == 2, na.rm = TRUE),
       sum(master$alcohol_contradiction), sum(master$alcohol_topcoded)),
 action = c("Exclude from MEC survey design; preserve demographic records", "Haven decoded true zeros; exact fallback normalization logged", "Retain; report possible measurement saturation", "Retain; report boundary limitation", "Exclude primary; include broad sensitivity", "Set derived alcohol classification missing; preserve source answers", "Retain category; volume is lower-bound approximation"))
csv(findings, "quality_findings")
partial <- as.data.frame(table(master$LUARXNC[master$broad_cap & master$LUAXSTAT == 2], useNA = "ifany"))
names(partial) <- c("partial_reason_code", "n_adults_with_cap")
csv(partial, "partial_exam_reasons")
results <- analyze_survey(master)
saveRDS(results, "outputs/results.rds")
capture.output(sessionInfo(), file = "outputs/sessionInfo.txt")
packages <- as.data.frame(installed.packages()[, c("Package", "Version")], stringsAsFactors = FALSE)
write.csv(packages, "outputs/package_versions.csv", row.names = FALSE)
cat("Pipeline completed. Master:", nrow(master), "Primary CAP:", sum(master$primary_cap),
    "Primary regression:", sum(master$regression_primary), "\n")
