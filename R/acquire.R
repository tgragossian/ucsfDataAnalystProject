validate_xpt <- function(path) {
  if (!file.exists(path)) stop("Missing source: ", path)
  con <- file(path, "rb"); on.exit(close(con))
  header <- rawToChar(readBin(con, "raw", n = 80))
  if (!startsWith(header, "HEADER RECORD*******LIBRARY HEADER RECORD"))
    stop("Not a SAS transport file: ", path)
  invisible(TRUE)
}

acquire_sources <- function(manifest = "config/sources.csv", raw_dir = "data/raw") {
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  spec <- read.csv(manifest, stringsAsFactors = FALSE)
  tables <- list(); rows <- list()
  for (i in seq_len(nrow(spec))) {
    id <- spec$file[i]
    path <- file.path(raw_dir, paste0(id, ".xpt"))
    book <- file.path(raw_dir, paste0(id, ".htm"))
    for (pair in list(c(path, spec$data_url[i]), c(book, spec$codebook_url[i]))) {
      if (!file.exists(pair[1])) {
        tmp <- paste0(pair[1], ".part")
        status <- system2("curl", c("-fL", "--retry", "2", "--connect-timeout", "20", "--max-time", "120", "-sS", shQuote(pair[2]), "-o", shQuote(tmp)))
        if (status != 0L) stop("Download failed: ", pair[2], "; rerun with network access.")
        if (grepl("xpt$", pair[1])) validate_xpt(tmp)
        if (!file.rename(tmp, pair[1])) stop("Cannot save downloaded file: ", pair[1])
      }
    }
    validate_xpt(path)
    x <- as.data.frame(haven::read_xpt(path))
    if (nrow(x) != spec$expected_rows[i]) stop("Unexpected row count for ", id, ": ", nrow(x))
    if (id == "P_DEMO" && !all(x$SDDSRVYR == 66)) stop("Wrong NHANES release")
    tables[[id]] <- x
    rows[[i]] <- data.frame(file = id, n_rows = nrow(x), n_columns = ncol(x),
      data_url = spec$data_url[i], codebook_url = spec$codebook_url[i],
      sha256 = digest::digest(file = path, algo = "sha256"),
      codebook_sha256 = digest::digest(file = book, algo = "sha256"),
      downloaded_utc = format(file.info(path)$mtime, tz = "UTC", usetz = TRUE),
      reader = paste("haven", packageVersion("haven")))
  }
  list(tables = tables, manifest = do.call(rbind, rows))
}
