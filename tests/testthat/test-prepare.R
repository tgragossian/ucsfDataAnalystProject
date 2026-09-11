source(if (file.exists('R/prepare.R')) 'R/prepare.R' else '../../R/prepare.R')
fixture_tables <- function() {
 d <- data.frame(SEQN=1:8, SDDSRVYR=66, RIDSTATR=2, RIAGENDR=1, RIDAGEYR=c(80,40,40,40,40,40,40,40), RIDRETH3=7, RIDEXPRG=NA_real_, WTMECPRP=1, SDMVSTRA=1, SDMVPSU=1, INDFMPIR=1)
 l <- data.frame(SEQN=1:8, LUAXSTAT=1, LUARXNC=NA_real_, LUANMVGP=10, LUANMTGP=10, LUXCAPM=c(400,200,200,200,200,200,200,200), LUXCPIQR=20, LUXSMED=5, LUXSIQR=1, LUXSIQRM=.2)
 a <- data.frame(SEQN=1:8, ALQ111=c(2,1,1,1,1,2,NA,1), ALQ121=c(NA,0,7,4,1,4,NA,10), ALQ130=c(NA,NA,NA,7,15,2,NA,1))
 list(P_DEMO=d,P_LUX=l,P_BMX=data.frame(SEQN=1:8,BMXBMI=25),P_GHB=data.frame(SEQN=1:8,LBXGH=5),P_ALQ=a)
}
testthat::test_that('categories, legitimate values, and incomplete quantity are handled', {
 r <- prepare_data(fixture_tables()); m <- r$master
 testthat::expect_equal(nrow(m),8L)
 testthat::expect_equal(m$alcohol_group[c(1:5,8)], c('Never','Former','Current under 1 per week','Current 1 to 4 per week','Current 5 to 7 per week','Current under 1 per week'))
 testthat::expect_true(all(is.na(m$alcohol_group[6:7])))
 testthat::expect_true(m$alcohol_contradiction[6])
 testthat::expect_true(m$regression_primary[3]); testthat::expect_true(is.na(m$alcohol_g_day[3]))
 testthat::expect_true(m$age80[1]); testthat::expect_equal(m$RIDRETH3[1],7)
 testthat::expect_equal(m$ALQ130[4],7); testthat::expect_true(m$alcohol_topcoded[5])
 testthat::expect_equal(m$LUXCAPM[1],400); testthat::expect_true(m$primary_cap[1])
 testthat::expect_false(m$bmi_outside_plausible_range[1])
 testthat::expect_setequal(r$dictionary$variable,names(m))
})
testthat::test_that('zero artifact normalization is exact and counted', {
 t <- fixture_tables(); t$P_DEMO$INDFMPIR[1:3] <- c(0,5.397605346934028e-79,1e-70)
 m <- prepare_data(t)
 testthat::expect_equal(m$master$INDFMPIR[1:2],c(0,0))
 testthat::expect_equal(m$master$INDFMPIR[3],1e-70,tolerance=0)
 testthat::expect_equal(m$qc$artifact_conversions[m$qc$variable=='INDFMPIR'],1)
})
testthat::test_that('implausible BMI is retained and flagged', {
 t <- fixture_tables(); t$P_BMX$BMXBMI[1] <- 150
 r <- prepare_data(t); m <- r$master
 testthat::expect_equal(m$BMXBMI[1],150)
 testthat::expect_true(m$bmi_outside_plausible_range[1])
 testthat::expect_equal(r$qc$n_invalid_to_missing[r$qc$variable=='BMXBMI'],0)
})
testthat::test_that('duplicates and orphans cannot multiply or add rows', {
 t <- fixture_tables(); t$P_BMX <- rbind(t$P_BMX,t$P_BMX[1,]); testthat::expect_error(prepare_data(t),'duplicate')
 t <- fixture_tables(); t$P_BMX$SEQN[1] <- 99; testthat::expect_error(prepare_data(t),'orphan')
 t <- fixture_tables(); t$P_LUX <- t$P_LUX[-1,]; r <- prepare_data(t)
 testthat::expect_equal(nrow(r$master),8); testthat::expect_false(r$master$has_lux[1])
 testthat::expect_equal(r$exclusions$n_remaining[r$exclusions$step=='Full DEMO'],c(8,8))
 testthat::expect_false(anyNA(r$master$primary_cap))
})
testthat::test_that('PSU 3 and published grouped counts survive while impossible codes fail', {
 t <- fixture_tables(); t$P_DEMO$SDMVPSU[1:3] <- c(3,2.5,4)
 t$P_LUX$LUANMVGP[1:5] <- c(20,30,19.5,21,19)
 t$P_LUX$LUXSMED[1:4] <- c(1.6,75,1.5,75.1)
 t$P_ALQ$ALQ121[4] <- 3.5
 m <- prepare_data(t)$master
 testthat::expect_equal(m$SDMVPSU[1],3)
 testthat::expect_true(all(is.na(m$SDMVPSU[2:3])))
 testthat::expect_equal(m$LUANMVGP[c(1,2,5)],c(20,30,19))
 testthat::expect_true(all(is.na(m$LUANMVGP[3:4])))
 testthat::expect_equal(m$LUXSMED[1:2],c(1.6,75))
 testthat::expect_true(all(is.na(m$LUXSMED[3:4])))
 testthat::expect_true(is.na(m$ALQ121[4]))
})
