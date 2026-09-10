-- Each view has a different estimand. Do not substitute regression rows for prevalence.
CREATE VIEW primary_cap_sample AS SELECT * FROM analytic_data WHERE primary_cap=1;
CREATE VIEW primary_regression_sample AS SELECT * FROM analytic_data WHERE regression_primary=1;
CREATE VIEW broad_cap_sample AS SELECT * FROM analytic_data WHERE broad_cap=1;
CREATE VIEW alcohol_counts AS
 SELECT COALESCE(alcohol_group,'Unknown') AS alcohol_group,COUNT(*) AS n
 FROM primary_cap_sample GROUP BY COALESCE(alcohol_group,'Unknown');
CREATE VIEW exclusion_cascade AS
 SELECT 1 AS stage,'Full demographic sample' AS criterion,COUNT(*) AS n FROM analytic_data
 UNION ALL SELECT 2,'MEC with positive weight',COUNT(*) FROM analytic_data WHERE RIDSTATR=2 AND WTMECPRP>0
 UNION ALL SELECT 3,'Adult MEC',COUNT(*) FROM analytic_data WHERE adult_mec=1
 UNION ALL SELECT 4,'LUX record',COUNT(*) FROM analytic_data WHERE adult_mec=1 AND has_lux=1
 UNION ALL SELECT 5,'CAP available',COUNT(*) FROM analytic_data WHERE broad_cap=1
 UNION ALL SELECT 6,'Complete exam',COUNT(*) FROM primary_cap_sample
 UNION ALL SELECT 7,'Alcohol known',COUNT(*) FROM primary_cap_sample WHERE alcohol_group IS NOT NULL
 UNION ALL SELECT 8,'Complete model covariates',COUNT(*) FROM primary_regression_sample;
