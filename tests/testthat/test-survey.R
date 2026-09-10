source(if (file.exists('R/survey_analysis.R')) 'R/survey_analysis.R' else '../../R/survey_analysis.R')
testthat::test_that('planning formula and recruitment allowance are explicit', {
 x <- planning_n(); testthat::expect_equal(x$n_complete[1],1068)
 testthat::expect_equal(x$n_recruit,ceiling(x$n_complete/.8))
})
testthat::test_that('MEC design excludes nonpositive and missing weights and rejects bad identifiers', {
 d <- data.frame(RIDSTATR=2,WTMECPRP=c(1,1,1,1,0,NA),SDMVSTRA=c(1,1,2,2,NA,NA),SDMVPSU=c(1,2,1,2,NA,NA))
 testthat::expect_equal(nrow(make_mec_design(d)$variables),4L)
 d$SDMVPSU[1] <- NA
 testthat::expect_error(make_mec_design(d),'identifiers')
})
testthat::test_that('obesity benchmark domain is independent of liver eligibility', {
 d <- data.frame(RIDAGEYR=c(19,20,50,70,30),BMXBMI=c(32,32,28,35,31),RIDEXPRG=c(NA,NA,NA,NA,1),primary_cap=FALSE)
 testthat::expect_equal(obesity_domain(d),c(FALSE,TRUE,TRUE,TRUE,FALSE))
})
