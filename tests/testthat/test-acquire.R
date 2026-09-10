source(file.path("..", "..", "R", "acquire.R"))
testthat::test_that("HTML masquerading as SAS is rejected before parsing", {
  f <- tempfile(); writeLines("<!doctype html><h1>error</h1>", f)
  testthat::expect_error(validate_xpt(f), "SAS transport")
})
testthat::test_that("missing files have an actionable error", {
  testthat::expect_error(validate_xpt(tempfile()), "Missing source")
})
