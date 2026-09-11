# Codebooks: https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles/P_ALQ.htm
# and P_DEMO.htm, P_LUX.htm, P_BMX.htm, P_GHB.htm at the same location.
# Every variable's allowed values, bounds and missing codes live in
# config/variables.csv, which docs/reference-documentation.md explains.

classify_alcohol_frequency <- function(alq111, alq121) {
    frequency <- rep(NA_character_, length(alq111))

    frequency[which(alq111 == 2 & is.na(alq121))] <- "Never drank"
    frequency[which(alq111 == 1 & alq121 == 0)] <- "No alcohol in past year"
    frequency[which(alq111 == 1 & alq121 %in% 6:10)] <- "Current, less than weekly"
    frequency[which(alq111 == 1 & alq121 %in% 3:5)] <- "Current, 1-4 times per week"
    frequency[which(alq111 == 1 & alq121 %in% 1:2)] <- "Current, nearly every day or daily"

    factor(
        frequency,
        levels = c(
            "Never drank",
            "No alcohol in past year",
            "Current, less than weekly",
            "Current, 1-4 times per week",
            "Current, nearly every day or daily"
        )
    )
}

# The tests run from tests/testthat, the pipeline runs from the project root.
rules_file <- function() {
    for (path in c("config/variables.csv", "../../config/variables.csv"))
        if (file.exists(path)) return(path)
    stop("Cannot find config/variables.csv")
}

# "0:19 20 30" becomes c(0:19, 20, 30)
read_codes <- function(text) {
    if (is.na(text)) return(NULL)

    codes <- c()
    for (part in strsplit(trimws(text), " +")[[1]]) {
        ends <- as.numeric(strsplit(part, ":")[[1]])
        codes <- c(codes, if (length(ends) == 2) seq(ends[1], ends[2]) else ends)
    }
    codes
}

prepare_data <- function(tables) {

    rules <- read.csv(rules_file(), stringsAsFactors = FALSE, na.strings = "")
    keep <- split(rules[["variable"]], rules[["file"]])   # columns to keep, per file

    artifact_zero <- 5.397605346934028e-79  # eight zero bytes read back as a double

    # Cleaning happens per file, before the joins, so nothing downstream ever reads a
    # refusal code or an artifact value.
    qc <- list()
    clean <- list()

    for (file in c("P_DEMO", "P_LUX", "P_BMX", "P_GHB", "P_ALQ")) {

        required <- rules[["variable"]][rules[["file"]] == file & rules[["required"]] == 1]
        if (!all(required %in% names(tables[[file]])))
            stop("Missing required columns in ", file, ": ",
                 paste(setdiff(required, names(tables[[file]])), collapse = ", "))

        x <- tables[[file]][union("SEQN", intersect(keep[[file]], names(tables[[file]])))]

        for (col in names(x)) {

            rule <- rules[match(col, rules[["variable"]]), ]
            values <- x[[col]]
            if (inherits(values, "haven_labelled")) values <- unclass(values)
            if (is.numeric(values)) attributes(values) <- NULL

            missing_before <- sum(is.na(values))
            artifact <- refused <- illegal <- rep(FALSE, length(values))

            if (is.numeric(values)) {

                # The reader can turn eight zero bytes into a tiny number. Match it
                # exactly, so a genuinely small value is never rounded away.
                artifact <- !is.na(values) & values == artifact_zero
                values[artifact] <- 0

                answered <- !is.na(values)
                allowed <- read_codes(rule[["allowed"]])

                # 7/9, 77/99 and 777/999 are refusals and don't-knows. They end up
                # missing like anything else out of range, but they are counted apart,
                # because a refusal and an impossible value are different problems.
                refused <- answered & values %in% read_codes(rule[["missing_codes"]])
                illegal <- answered & !refused & (
                    (!is.null(allowed) & !(values %in% allowed)) |
                    (!is.na(rule[["min"]]) & values < rule[["min"]]) |
                    (!is.na(rule[["max"]]) & values > rule[["max"]]) |
                    (isTRUE(rule[["integer"]] == 1) & values != trunc(values)))

                values[refused | illegal] <- NA
            }

            x[[col]] <- values
            valid <- values[!is.na(values)]

            # One rule row per variable, so SEQN is only logged from its home file.
            if (col != "SEQN" || file == "P_DEMO")
                qc[[col]] <- data.frame(
                    variable = col,
                    source_file = file,
                    units = rule[["units"]],
                    allowed = rule[["allowed"]],
                    min = rule[["min"]],
                    max = rule[["max"]],
                    integer = rule[["integer"]],
                    missing_codes = rule[["missing_codes"]],
                    n_rows = length(values),
                    n_missing_source = missing_before,
                    artifact_conversions = sum(artifact),
                    n_refused_dk = sum(refused),
                    n_invalid_to_missing = sum(illegal),
                    n_missing_final = sum(is.na(values)),
                    min_valid = if (is.numeric(valid) && length(valid)) min(valid) else NA_real_,
                    max_valid = if (is.numeric(valid) && length(valid)) max(valid) else NA_real_,
                    row.names = NULL
                )
        }

        if (anyDuplicated(x[["SEQN"]]))
            stop("Join integrity: duplicate SEQN values in ", file)

        clean[[file]] <- x
    }

    main <- clean[["P_DEMO"]]                            # base, already trimmed

    for (file in c("P_LUX", "P_BMX", "P_GHB", "P_ALQ")) {
        prev <- nrow(main)
        y <- clean[[file]]
        if (!all(y[["SEQN"]] %in% main[["SEQN"]]))       # a record with no participant
            stop("Join integrity: orphan SEQN values in ", file)
        main <- merge(main, y, by = "SEQN", all.x = TRUE)
        stopifnot(nrow(main) == prev)
    }

    main <- main[order(main[["SEQN"]]), ]
    rownames(main) <- NULL

    #Demographics filtering
    stopifnot(
        all(main[["SDDSRVYR"]] == 66, na.rm = TRUE) #only contains 66
    )

    #Eligibility: was the person examined, and are they in scope for a liver estimate?
    main[["mec_examined"]] <- !is.na(main[["RIDSTATR"]]) & main[["RIDSTATR"]] == 2 &
                              !is.na(main[["WTMECPRP"]]) & main[["WTMECPRP"]] > 0
    main[["has_lux"]] <- main[["SEQN"]] %in% clean[["P_LUX"]][["SEQN"]]
    main[["age80"]] <- !is.na(main[["RIDAGEYR"]]) & main[["RIDAGEYR"]] >= 80
    main[["adult_mec"]] <- main[["mec_examined"]] &
                           !is.na(main[["RIDAGEYR"]]) & main[["RIDAGEYR"]] >= 18

    #Available measurement: is there a CAP reading, and what exam did it come from?
    main[["cap_available"]] <- !is.na(main[["LUXCAPM"]])
    main[["broad_cap"]] <- main[["adult_mec"]] & main[["has_lux"]] & main[["cap_available"]]
    main[["primary_cap"]] <- main[["broad_cap"]] &
                             !is.na(main[["LUAXSTAT"]]) & main[["LUAXSTAT"]] == 1

    #Quality. The device floor and ceiling are censoring points, so they get flagged and
    #kept: excluding on the size of the outcome would delete the disease.
    main[["cap_ceiling"]] <- main[["cap_available"]] & main[["LUXCAPM"]] >= 400
    main[["cap_floor"]] <- main[["cap_available"]] & main[["LUXCAPM"]] <= 100
    main[["cap_iqr_ratio"]] <- main[["LUXCPIQR"]] / main[["LUXCAPM"]]
    #A sensitivity domain, not a measurement flag: an unknown ratio is not reliable.
    main[["cap_reliable_sensitivity"]] <- main[["primary_cap"]] &
                                          !is.na(main[["cap_iqr_ratio"]]) &
                                          main[["cap_iqr_ratio"]] < 0.30
    main[["stiffness_iqr_ratio_ok"]] <- ifelse(
        is.na(main[["LUXSIQRM"]]), NA, main[["LUXSIQRM"]] < 30
    )

    # BMI is retained as recorded; 10-100 kg/m2 is a plausibility range, not a
    # hard measurement limit. Flag unusual values for reporting and sensitivity
    # analysis instead of converting them to missing during source validation.
    main[["bmi_outside_plausible_range"]] <- !is.na(main[["BMXBMI"]]) &
        (main[["BMXBMI"]] < 10 | main[["BMXBMI"]] > 100)

    #alch filtering. Never drank, nothing in the past year, and no answer are three
    #different things, so ALQ111 gates the classification before ALQ121 is read.
    frequency <- classify_alcohol_frequency(main[["ALQ111"]], main[["ALQ121"]])

    main[["alcohol_group"]] <- NA_character_
    main[which(frequency == "Never drank"), "alcohol_group"] <- "Never"
    main[which(frequency == "No alcohol in past year"), "alcohol_group"] <- "Former"
    main[which(frequency == "Current, less than weekly"), "alcohol_group"] <- "Current under 1 per week"
    main[which(frequency == "Current, 1-4 times per week"), "alcohol_group"] <- "Current 1 to 4 per week"
    main[which(frequency == "Current, nearly every day or daily"), "alcohol_group"] <- "Current 5 to 7 per week"

    #Said they never drank, then answered the frequency question. The source answers are
    #kept, the derived ones are not.
    main[["alcohol_contradiction"]] <- !is.na(main[["ALQ111"]]) & main[["ALQ111"]] == 2 &
                                       !is.na(main[["ALQ121"]])
    main[["alcohol_topcoded"]] <- !is.na(main[["ALQ130"]]) & main[["ALQ130"]] >= 15

    #Rough volume: drinking days per year at the midpoint of each ALQ121 category, times
    #drinks per day, times 14 g of ethanol per US standard drink, spread over the year.
    days_per_year <- c("0" = 0, "1" = 365, "2" = 330, "3" = 182, "4" = 104, "5" = 52,
                       "6" = 30, "7" = 12, "8" = 9, "9" = 4.5, "10" = 1.5)

    main[["alcohol_g_day"]] <- unname(days_per_year[as.character(main[["ALQ121"]])]) *
                               main[["ALQ130"]] * 14 / 365

    #ALQ130 is never asked of someone who did not drink this year, so their blank is a
    #real zero rather than a non-answer.
    main[which(main[["alcohol_group"]] %in% c("Never", "Former")), "alcohol_g_day"] <- 0
    main[which(main[["alcohol_contradiction"]]), "alcohol_g_day"] <- NA

    #Prevalence and the model answer different questions, so they get different samples.
    #Requiring model covariates for a prevalence estimate would shrink it for no reason.
    main[["covariates_complete"]] <- !is.na(main[["BMXBMI"]]) & !is.na(main[["RIDAGEYR"]]) &
                                     !is.na(main[["RIAGENDR"]]) & !is.na(main[["RIDRETH3"]])
    main[["regression_primary"]] <- main[["primary_cap"]] &
        !is.na(main[["alcohol_group"]]) & main[["covariates_complete"]]
    main[["regression_broad"]] <- main[["broad_cap"]] &
        !is.na(main[["alcohol_group"]]) & main[["covariates_complete"]]

    #Data dictionary: one row per column of main, described by the manifest.
    row <- match(names(main), rules[["variable"]])
    stopifnot(!anyNA(row))                               # every column is documented

    dictionary <- data.frame(
        variable = names(main),
        source = rules[["file"]][row],
        type = unname(vapply(main, function(col) class(col)[1], character(1))),
        units = rules[["units"]][row],
        description = rules[["description"]][row]
    )

    #Two exclusion cascades, because prevalence and the model are different estimands
    #and must not share one count.
    remaining <- list(
        "Full DEMO"                 = rep(TRUE, nrow(main)),
        "MEC examined"              = main[["mec_examined"]],
        "Adult MEC"                 = main[["adult_mec"]],
        "LUX record"                = main[["adult_mec"]] & main[["has_lux"]],
        "CAP available"             = main[["broad_cap"]],
        "Complete exam"             = main[["primary_cap"]],
        "Alcohol known"             = main[["primary_cap"]] & !is.na(main[["alcohol_group"]]),
        "Complete model covariates" = main[["regression_primary"]]
    )

    criteria <- c(
        "Full DEMO"                 = "All released participants",
        "MEC examined"              = "RIDSTATR 2 with a positive MEC weight",
        "Adult MEC"                 = "Age 18 or older",
        "LUX record"                = "Elastography record present",
        "CAP available"             = "Median CAP present, any exam status",
        "Complete exam"             = "LUAXSTAT 1",
        "Alcohol known"             = "Drinking frequency classifiable",
        "Complete model covariates" = "BMI, age, sex and race/ethnicity observed"
    )

    exclusions <- data.frame()
    for (cascade in c("Descriptive CAP prevalence", "Primary regression")) {

        #Prevalence stops at the exam; the model keeps going into alcohol and covariates.
        steps <- if (cascade == "Primary regression") names(remaining)
                 else names(remaining)[1:6]
        left <- vapply(remaining[steps], sum, integer(1))

        exclusions <- rbind(exclusions, data.frame(
            cascade = cascade,
            step = steps,
            criterion = unname(criteria[steps]),
            n_remaining = unname(left),
            n_excluded = c(0, -diff(left)),
            row.names = NULL
        ))
    }

    list(
        master = main,
        qc = do.call(rbind, qc),
        dictionary = dictionary,
        exclusions = exclusions
    )
}
