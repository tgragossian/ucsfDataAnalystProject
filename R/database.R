execute_sql_file <- function(con, path) {
  sql <- paste(readLines(path, warn = FALSE), collapse = "\n")
  for (statement in strsplit(sql, ";", fixed = TRUE)[[1]])
    if (nzchar(trimws(statement))) DBI::dbExecute(con, statement)
}

build_database <- function(tables, master, path, sql_dir = "sql") {
  # Stage the new database; only replace a prior generated database after validation.
  temp <- paste0(path, ".building")
  if (file.exists(temp)) unlink(temp)
  con <- DBI::dbConnect(RSQLite::SQLite(), temp)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "PRAGMA foreign_keys=ON")
  DBI::dbWithTransaction(con, {
    execute_sql_file(con, file.path(sql_dir, "schema.sql"))
    mapping <- c(P_DEMO="demographics", P_LUX="liver_exam", P_BMX="anthropometry",
                 P_GHB="glycohemoglobin", P_ALQ="alcohol")
    for (id in names(mapping)) {
      target <- unname(mapping[id])
      fields <- DBI::dbListFields(con, target)
      DBI::dbAppendTable(con, target, as.data.frame(tables[[id]][fields]))
    }
    # Types follow the documented clean snapshot; domain keys are hand constrained.
    types <- vapply(master, function(x) if (is.character(x)) "TEXT" else if(is.logical(x)) "INTEGER" else "REAL", character(1))
    types["SEQN"] <- "INTEGER PRIMARY KEY REFERENCES demographics(SEQN)"
    DBI::dbWriteTable(con, "analytic_data", master, field.types = types)
    execute_sql_file(con, file.path(sql_dir, "analysis_views.sql"))
    stopifnot(nrow(DBI::dbGetQuery(con, "PRAGMA foreign_key_check")) == 0)
    stopifnot(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM source_join")$n == nrow(master))
    ids <- DBI::dbGetQuery(con, "SELECT SEQN FROM primary_regression_sample")$SEQN
    stopifnot(setequal(ids, master$SEQN[master$regression_primary]))
  })
  checks <- DBI::dbGetQuery(con, "SELECT * FROM exclusion_cascade ORDER BY stage")
  if (!file.rename(temp, path)) stop("Cannot replace generated database: ", path)
  checks
}
