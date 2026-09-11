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
testthat::test_that('subgroup missingness is weighted, and a required variable draws no test', {
 n <- 64
 d <- data.frame(RIDSTATR=2,WTMECPRP=rep(c(1,1,3,3),length.out=n),SDMVSTRA=rep(1:4,each=16),SDMVPSU=rep(rep(1:2,each=8),4),
  RIDAGEYR=rep(c(25,45,65,35),length.out=n),adult_mec=TRUE,primary_cap=TRUE,regression_primary=TRUE,
  sex=factor(rep(c('Male','Female'),length.out=n),levels=c('Male','Female')),race=factor(rep(c(3,4),length.out=n),levels=c(3,4)),
  BMXBMI=28,LBXGH=5.4,alcohol_group=factor('Never'),INDFMPIR=2)
 # Missing income falls only on men, and only on the men carrying the heavier weight,
 # so a weighted rate and a headcount rate cannot agree: 0.75 against 0.50.
 d$INDFMPIR[d$sex=='Male' & d$WTMECPRP==3] <- NA
 r <- missingness_subgroups(make_mec_design(d))
 male <- subset(r$by_group,domain=='adult_mec' & variable=='INDFMPIR' & group_variable=='sex' & group=='Male')
 testthat::expect_equal(male$n_missing,16)
 testthat::expect_equal(male$weighted_missing_fraction,.75)
 testthat::expect_true(male$weighted_missing_ge_10pct)
 by_sex <- subset(r$tests,domain=='adult_mec' & variable=='INDFMPIR' & group_variable=='sex')
 testthat::expect_equal(by_sex$highest_group,'Male')
 testthat::expect_equal(by_sex$difference_pp,75)
 testthat::expect_equal(by_sex$test,'Rao-Scott second-order F')
 testthat::expect_true('Non-Hispanic White' %in% r$by_group$group_label)
 # BMI is complete here, as it is inside the regression sample: nothing left to explain.
 complete <- subset(r$tests,variable=='BMXBMI')
 testthat::expect_true(all(complete$test=='Not applicable'))
 testthat::expect_true(all(is.na(complete$p_value)))
})
