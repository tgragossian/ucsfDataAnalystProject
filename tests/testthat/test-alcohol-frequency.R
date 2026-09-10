source(if (file.exists("R/prepare.R")) "R/prepare.R" else "../../R/prepare.R")

testthat::test_that("alcohol frequency respects questionnaire routing and frequency codes", {
  alq111 <- c(2, 1, 1, 1, 1, 1, NA, 2)
  alq121 <- c(NA, 0, 10, 6, 5, 2, NA, 4)

  result <- classify_alcohol_frequency(alq111, alq121)

  testthat::expect_equal(
    as.character(result),
    c(
      "Never drank",
      "No alcohol in past year",
      "Current, less than weekly",
      "Current, less than weekly",
      "Current, 1-4 times per week",
      "Current, nearly every day or daily",
      NA,
      NA
    )
  )
})
