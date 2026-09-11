# All population inference uses the full MEC Taylor-linearized survey design.
make_mec_design <- function(master) {
 keep <- !is.na(master$RIDSTATR) & master$RIDSTATR==2 & !is.na(master$WTMECPRP) & master$WTMECPRP>0
 d <- master[keep,,drop=FALSE]
 if (!nrow(d) || any(!is.finite(d$WTMECPRP)) || anyNA(d[c('SDMVSTRA','SDMVPSU')]) || any(!is.finite(d$SDMVSTRA) | d$SDMVSTRA<1 | d$SDMVSTRA!=trunc(d$SDMVSTRA)) || any(!is.finite(d$SDMVPSU) | d$SDMVPSU<1 | d$SDMVPSU!=trunc(d$SDMVPSU))) stop('Invalid positive-weight MEC design identifiers or weights')
 survey::svydesign(ids=~SDMVPSU,strata=~SDMVSTRA,weights=~WTMECPRP,nest=TRUE,data=d)
}
obesity_domain <- function(d) !is.na(d$RIDAGEYR) & d$RIDAGEYR>=20 & !is.na(d$BMXBMI) & (is.na(d$RIDEXPRG) | d$RIDEXPRG!=1)
planning_n <- function(p=.5,margin=.03,confidence=.95,deff=c(1,1.5,2),response=.8) {
 n <- ceiling(qnorm(1-(1-confidence)/2)^2*p*(1-p)*deff/margin^2)
 data.frame(p=p,margin=margin,confidence=confidence,assumed_deff=deff,response=response,n_complete=n,n_recruit=ceiling(n/response),interpretation='Hypothetical planning assumptions; not a retrospective power calculation')
}
benchmark_obesity <- function(design) {
 d <- design[obesity_domain(design$variables),]
 d <- update(d,obese=as.numeric(BMXBMI>=30),age_group=factor(ifelse(RIDAGEYR<40,'20-39',ifelse(RIDAGEYR<60,'40-59','60+')),levels=c('20-39','40-59','60+')))
 by <- survey::svyby(~obese,~age_group,d,survey::svymean,covmat=TRUE)
 std <- survey::svycontrast(by,setNames(c(.3966,.3718,.2316),names(coef(by))))
 ci <- confint(std,df=survey::degf(d)); est <- as.numeric(coef(std))
 data.frame(benchmark='Age-standardized obesity, age 20+, known BMI, reported pregnancy excluded',n=nrow(d$variables),estimate=est,conf_low=ci[1],conf_high=ci[2],published_estimate=.419,absolute_difference=abs(est-.419),rounding_tolerance=.0005,pass=abs(est-.419)<=.0005,design_df=survey::degf(d))
}
prevalence_row <- function(design,domain,threshold,group='All') {
 d <- design[design$variables[[domain]],]
 if(group!='All') d <- d[d$variables$alcohol_descriptive==group,]
 d <- update(d,positive=as.numeric(LUXCAPM>=threshold))
 n <- nrow(d$variables); cases <- sum(d$variables$positive); df <- survey::degf(d)
 m <- survey::svymean(~positive,d,deff='replace'); deff <- as.numeric(survey::deff(m))
 ci <- if(cases>0 && cases<n) as.numeric(confint(survey::svyciprop(~positive,d,method='logit',df=df))) else c(NA_real_,NA_real_)
 data.frame(domain=domain,threshold=threshold,alcohol_group=group,n=n,cases=cases,estimate=as.numeric(coef(m)),std_error=as.numeric(survey::SE(m)),conf_low=ci[1],conf_high=ci[2],design_df=df,deff_replace=deff,effective_n=n/deff,reliability_flag=n<30 || df<8 || anyNA(ci) || diff(ci)>.30,reliability_rule='Heuristic: n<30, df<8, unavailable CI, or CI width>0.30; not full NCHS presentation standard')
}
model_rows <- function(fit,label,n,survey_fit=TRUE) {
 df <- if(survey_fit) fit$df.residual else df.residual(fit)
 b <- coef(fit); se <- sqrt(diag(vcov(fit))); q <- qt(.975,df)
 data.frame(model=label,term=names(b),estimate=as.numeric(b),std_error=as.numeric(se),conf_low=b-q*se,conf_high=b+q*se,p_value=2*pt(-abs(b/se),df),n=n,df=df,row.names=NULL)
}
fit_cap_models <- function(design) {
 f <- LUXCAPM~alcohol_group+BMXBMI+RIDAGEYR+age80+sex+race
 defs <- list(primary=design$variables$regression_primary,broad_available_CAP=design$variables$regression_broad,CAP_IQR_ratio_sensitivity=design$variables$regression_primary & design$variables$cap_reliable_sensitivity,HbA1c_subset_without_HbA1c=design$variables$regression_primary & !is.na(design$variables$LBXGH),HbA1c_subset_with_HbA1c=design$variables$regression_primary & !is.na(design$variables$LBXGH))
 out <- list()
 for(nm in names(defs)) {
  d <- design[defs[[nm]],]; formula <- if(nm=='HbA1c_subset_with_HbA1c') update(f,.~.+LBXGH) else f
  fit <- survey::svyglm(formula,design=d)
  out[[nm]] <- model_rows(fit,nm,nrow(d$variables))
  if(nm=='primary') out$naive_same_sample <- model_rows(lm(formula,data=d$variables),'naive_same_sample',nrow(d$variables),FALSE)
 }
 do.call(rbind,out)
}
missingness_comparison <- function(design) {
 d <- design[design$variables$adult_mec,]; out <- list(); k <- 0
 for(domain in c('primary_cap','regression_primary')) for(included in c(FALSE,TRUE)) {
   s <- d[d$variables[[domain]]==included,]
   for(v in c('RIDAGEYR','BMXBMI','INDFMPIR','sex','race')) {
    available <- !is.na(s$variables[[v]]); sub <- s[available,]
    s$variables$missing_indicator <- as.numeric(!available)
    missing_est <- survey::svymean(~missing_indicator,s)
    missing_ci <- confint(missing_est,df=survey::degf(s))
    if(!nrow(sub$variables)) next
    f <- reformulate(v); m <- survey::svymean(f,sub,na.rm=TRUE); ci <- confint(m,df=survey::degf(sub))
    k <- k+1; out[[k]] <- data.frame(domain=domain,included=included,variable=v,category=names(coef(m)),n_group=nrow(s$variables),n_observed=sum(available),n_missing=sum(!available),weighted_missing_fraction=as.numeric(coef(missing_est)),missing_conf_low=missing_ci[1],missing_conf_high=missing_ci[2],weighted_missing_ge_10pct=as.numeric(coef(missing_est))>=.10,estimate=as.numeric(coef(m)),std_error=as.numeric(survey::SE(m)),conf_low=ci[,1],conf_high=ci[,2],row.names=NULL)
   }
 }
 do.call(rbind,out)
}
# Missingness by demography, not only by inclusion status. A smaller analytic sample is
# tolerable; a differently composed one is a bias. Tests are Rao-Scott second-order F,
# never chisq.test(), so the weights, strata and PSUs carry into the test itself.
# SDMVSTRA is deliberately not a grouping variable: it is a variance-estimation device,
# not a population subgroup anyone would want a missingness rate for.
missingness_subgroups <- function(design) {
 race_label <- c('1'='Mexican American','2'='Other Hispanic','3'='Non-Hispanic White','4'='Non-Hispanic Black','6'='Non-Hispanic Asian','7'='Other or multiracial')
 d <- design[design$variables$adult_mec,]
 d$variables$age_group <- cut(d$variables$RIDAGEYR,c(18,40,60,Inf),right=FALSE,labels=c('18-39','40-59','60+'))
 rows <- list(); tests <- list(); k <- 0
 for(domain in c('adult_mec','primary_cap','regression_primary')) {
  s <- if(domain=='adult_mec') d else d[d$variables[[domain]],]
  df <- survey::degf(s)
  for(v in c('INDFMPIR','BMXBMI','alcohol_group','LBXGH')) {
   s$variables$missing_indicator <- as.numeric(is.na(s$variables[[v]]))
   overall <- as.numeric(coef(survey::svymean(~missing_indicator,s)))
   # A variable the sample rule already requires has no missingness left to explain.
   varies <- any(s$variables$missing_indicator==1) && any(s$variables$missing_indicator==0)
   for(g in c('sex','race','age_group')) {
    est <- survey::svyby(~missing_indicator,reformulate(g),s,survey::svymean); ci <- confint(est,df=df)
    group <- as.character(est[[g]]); fraction <- as.numeric(est$missing_indicator)
    label <- unname(if(g=='race') race_label[group] else group)
    n_group <- as.numeric(table(s$variables[[g]])[group])
    n_missing <- as.numeric(tapply(s$variables$missing_indicator,s$variables[[g]],sum)[group])
    x <- if(varies) survey::svychisq(reformulate(c('missing_indicator',g)),s,statistic='F') else NULL
    k <- k+1
    rows[[k]] <- data.frame(domain=domain,variable=v,group_variable=g,group=group,group_label=label,n_group=n_group,n_missing=n_missing,weighted_missing_fraction=fraction,conf_low=ci[,1],conf_high=ci[,2],weighted_missing_ge_10pct=fraction>=.10,design_df=df,row.names=NULL)
    tests[[k]] <- data.frame(domain=domain,variable=v,group_variable=g,n=nrow(s$variables),weighted_missing_overall=overall,lowest_group=label[which.min(fraction)],lowest_fraction=min(fraction),highest_group=label[which.max(fraction)],highest_fraction=max(fraction),difference_pp=(max(fraction)-min(fraction))*100,statistic=if(varies) as.numeric(x$statistic) else NA_real_,ndf=if(varies) as.numeric(x$parameter[1]) else NA_real_,ddf=if(varies) as.numeric(x$parameter[2]) else NA_real_,p_value=if(varies) as.numeric(x$p.value) else NA_real_,test=if(varies) 'Rao-Scott second-order F' else 'Not applicable',interpretation=if(varies) 'Read the percentage-point difference and the intervals first; the p-value only says the difference is not noise' else 'This variable is required by the sample rule, so nothing is missing here by construction',row.names=NULL)
   }
  }
 }
 list(by_group=do.call(rbind,rows),tests=do.call(rbind,tests))
}
analyze_survey <- function(master,out_dir='outputs') {
 old_options <- options(survey.lonely.psu='fail',survey.adjust.domain.lonely=FALSE)
 on.exit(options(old_options),add=TRUE)
 dir.create(file.path(out_dir,'tables'),recursive=TRUE,showWarnings=FALSE)
 dir.create(file.path(out_dir,'figures'),recursive=TRUE,showWarnings=FALSE)
 master$alcohol_group <- factor(master$alcohol_group,levels=c('Current under 1 per week','Never','Former','Current 1 to 4 per week','Current 5 to 7 per week'))
 master$alcohol_descriptive <- ifelse(is.na(master$alcohol_group),'Unknown',as.character(master$alcohol_group))
 master$sex <- factor(master$RIAGENDR,levels=c(1,2),labels=c('Male','Female'))
 master$race <- factor(master$RIDRETH3,levels=c(3,1,2,4,6,7))
 design <- make_mec_design(master)
 benchmark <- benchmark_obesity(design)
 prev <- list(); k <- 0
 for(domain in c('primary_cap','broad_cap','cap_reliable_sensitivity')) for(threshold in c(274,248,288,302)) {
  k <- k+1; prev[[k]] <- prevalence_row(design,domain,threshold)
 }
 for(g in c(levels(master$alcohol_group),'Unknown')) {
  k <- k+1; prev[[k]] <- prevalence_row(design,'primary_cap',274,g)
 }
 prevalence <- do.call(rbind,prev); models <- fit_cap_models(design)
 stiffness_d <- design[design$variables$adult_mec & !is.na(design$variables$LUAXSTAT) & design$variables$LUAXSTAT==1 & !is.na(design$variables$LUXSMED),]
 stiffness <- survey::svymean(~LUXSMED,stiffness_d); ci <- confint(stiffness,df=survey::degf(stiffness_d))
 subgroups <- missingness_subgroups(design)
 result <- list(benchmark=benchmark,prevalence=prevalence,models=models,missingness=missingness_comparison(design),missingness_by_group=subgroups$by_group,missingness_tests=subgroups$tests,precision_planning=planning_n(),design_summary=data.frame(n_MEC=nrow(design$variables),strata=length(unique(design$variables$SDMVSTRA)),PSUs=nrow(unique(design$variables[c('SDMVSTRA','SDMVPSU')])),design_df=survey::degf(design)),liver_stiffness=data.frame(n=nrow(stiffness_d$variables),mean_kPa=as.numeric(coef(stiffness)),std_error=as.numeric(survey::SE(stiffness)),conf_low=ci[1],conf_high=ci[2],interpretation='Descriptive liver stiffness; not a fibrosis diagnosis'))
 for(nm in names(result)) write.csv(result[[nm]],file.path(out_dir,'tables',paste0(nm,'.csv')),row.names=FALSE)
 p <- ggplot2::ggplot(subset(prevalence,alcohol_group=='All'),ggplot2::aes(x=factor(threshold),y=estimate,ymin=conf_low,ymax=conf_high,color=domain))+ggplot2::geom_pointrange(position=ggplot2::position_dodge(width=.45))+ggplot2::labs(x='CAP threshold (dB/m)',y='Weighted proportion above threshold',color='Exam domain',title='CAP threshold sensitivity',subtitle='Survey logit 95% intervals; threshold positivity is not a diagnosis')+ggplot2::theme_minimal()
 ggplot2::ggsave(file.path(out_dir,'figures','cap_thresholds.png'),p,width=9,height=5,dpi=160)
 p <- ggplot2::ggplot(subset(models,model %in% c('primary','naive_same_sample') & grepl('^alcohol_group',term)),ggplot2::aes(x=estimate,y=sub('alcohol_group','',term),xmin=conf_low,xmax=conf_high,color=model))+ggplot2::geom_vline(xintercept=0,linetype=2)+ggplot2::geom_pointrange(position=ggplot2::position_dodge(width=.4),orientation='y')+ggplot2::labs(x='Adjusted CAP difference (dB/m), 95% CI',y=NULL,color='Analysis',title='Alcohol frequency and CAP',subtitle='Reference: current under 1 per week; identical complete-case samples')+ggplot2::theme_minimal()
 ggplot2::ggsave(file.path(out_dir,'figures','alcohol_coefficients.png'),p,width=10,height=5,dpi=160)
 p <- ggplot2::ggplot(transform(subset(subgroups$by_group,domain=='adult_mec' & variable=='INDFMPIR'),group_variable=factor(group_variable,levels=c('sex','race','age_group'))),ggplot2::aes(x=weighted_missing_fraction,y=stats::reorder(group_label,weighted_missing_fraction),xmin=conf_low,xmax=conf_high))+ggplot2::geom_vline(xintercept=.10,linetype=2)+ggplot2::geom_pointrange(orientation='y')+ggplot2::facet_grid(group_variable~.,scales='free_y',space='free_y',labeller=ggplot2::as_labeller(c(sex='Sex',race='Race and Hispanic origin',age_group='Age group')))+ggplot2::scale_x_continuous(labels=scales::percent)+ggplot2::labs(x='Weighted share with income-to-poverty ratio missing, 95% CI',y=NULL,title='Income missingness is not spread evenly across the adult MEC sample',subtitle='Dashed line marks the 10% reporting threshold; income is not a model covariate, so no one was excluded for it')+ggplot2::theme_minimal()
 ggplot2::ggsave(file.path(out_dir,'figures','income_missingness.png'),p,width=9,height=6,dpi=160)
 result
}
