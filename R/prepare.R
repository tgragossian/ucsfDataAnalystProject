# Codebooks: https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles/P_ALQ.htm
# and P_DEMO.htm, P_LUX.htm, P_BMX.htm, P_GHB.htm at the same location.

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

prepare_data <- function(tables) {

    keep <- list(
      P_DEMO = c("SEQN","SDDSRVYR","RIDSTATR","RIAGENDR","RIDAGEYR","RIDRETH3",
                 "RIDEXPRG","WTMECPRP","SDMVPSU","SDMVSTRA","INDFMPIR"),
      P_LUX  = names(tables$P_LUX),                       # keep all
      P_BMX  = c("SEQN","BMXBMI","BMXWT","BMXHT","BMXWAIST"),
      P_GHB  = c("SEQN","LBXGH"),
      P_ALQ  = c("SEQN","ALQ111","ALQ121","ALQ130")
    )

    main <- tables[["P_DEMO"]][keep$P_DEMO]               # base, already trimmed

    for (tbl in c("P_LUX","P_BMX","P_GHB","P_ALQ")) {
      prev <- nrow(main)
      y <- tables[[tbl]][keep[[tbl]]]                     # trim before merging
      main <- merge(main, y, by = "SEQN", all.x = TRUE)
      stopifnot(nrow(main) == prev)
    }

    #Demographics filtering
    stopifnot(
        all(main[["SDDSRVYR"]] == 66, na.rm = TRUE) #only contains 66
    )
    main[["mec_examined_bool"]] <- main[["RIDSTATR"]] == 2
    main[["min_partial_bool"]] <- main[["LUAXSTAT"]] %in% c(1, 2) #bool flag for at least partial exam for liver

    #body measures filtering, NA

    #glycohemoglobin filtering, NA

    #alch filtering, keep all removing any of the NAs
    bool_alq <- c("ALQ151", "ALQ111")
    alq_non_bool <- c("ALQ121", "ALQ130")

    illegal_codes <- c(77, 99, 777, 999)
    illegal_bools <- c(7, 9)

    for (col in names(main)) {
        if (col %in% bool_alq) {
            main[[col]][main[[col]] %in% illegal_bools] <- NA
        } else if (col %in% alq_non_bool) {
            main[[col]][main[[col]] %in% illegal_codes] <- NA
        }
    }

    # Alcohol-use status. ALQ121 is legitimately missing for participants who
    # report never drinking, so classify them using ALQ111 first.
    main[["alcohol_status"]] <- NA_character_

    main[
        which(main[["ALQ111"]] == 2),
        "alcohol_status"
    ] <- "Never drank"

    main[
        which(main[["ALQ111"]] == 1 & main[["ALQ121"]] == 0),
        "alcohol_status"
    ] <- "No alcohol in past year"

    main[
        which(main[["ALQ111"]] == 1 & main[["ALQ121"]] %in% 1:10),
        "alcohol_status"
    ] <- "Current drinker"

    main[["alcohol_status"]] <- factor(
        main[["alcohol_status"]],
        levels = c(
            "Never drank",
            "No alcohol in past year",
            "Current drinker"
        )
    )

    main[["alcohol_frequency"]] <- classify_alcohol_frequency(
        main[["ALQ111"]],
        main[["ALQ121"]]
    )

    main[["stiff_iqr_ratio_lt_30"]] <-
    main[["LUXSIQRM"]] < 30

    main[["cap_iqr_ratio_pct"]] <-
    100 * (main[["LUXCPIQR"]] / main[["LUXCAPM"]])

    main[["cap_iqr_ratio_lt_30"]] <-
    main[["cap_iqr_ratio_pct"]] < 30

    main #returns filtered main
    #RESULTS OF BOOLS:     examined_bool   min_partial_bool 
    #proportion of trues:  0.9190231       0.6279563
    #the number examined was 14300, the number of people seen that at least got a partial exam for the liver was 9771

  }
