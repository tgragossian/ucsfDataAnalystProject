# Source variable reference

NHANES 2017–March 2020 pre-pandemic release (`SDDSRVYR == 66`). Five files, joined on
`SEQN`. Codebooks: `https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles/<FILE>.htm`.

This is the working note behind `config/variables.csv` — what each file holds, which
columns we keep, and why. "Keep" means the column enters the analytic table and
therefore needs a row in `validation_rules.csv` and the data dictionary.

`config/variables.csv` is the machine-readable form of everything below, and it is the
only place `R/prepare.R` learns about a variable. One row per column of the master
table, source and derived alike:

| Field | Meaning |
|---|---|
| `variable` | column name |
| `file` | source file, or `derived` for a column prepare.R constructs |
| `required` | 1 if the pipeline should fail when the source file lacks this column |
| `units` | flows into the data dictionary and `validation_rules.csv` |
| `allowed` | valid values, space separated, `a:b` for an inclusive range (`0:19 20 30`) |
| `min` / `max` | inclusive bounds, for continuous measures |
| `integer` | 1 if a fractional value is impossible |
| `missing_codes` | documented refusal / don't-know codes, counted separately from other invalid values |
| `description` | the data dictionary text |

A value failing its rule becomes `NA` and is counted in `validation_rules.csv`. It never
removes a row, and the untouched source value still reaches the SQLite domain tables.
**Add a variable by adding a row there, not by editing `R/prepare.R`.**

## Columns kept (summary)

| File | Columns |
|---|---|
| P_DEMO | `SEQN`, `SDDSRVYR`, `RIDSTATR`, `RIAGENDR`, `RIDAGEYR`, `RIDRETH3`, `RIDEXPRG`, `WTMECPRP`, `SDMVPSU`, `SDMVSTRA`, `INDFMPIR` |
| P_LUX | all 12 data columns (see below) |
| P_BMX | `SEQN`, `BMXBMI`, `BMXWT`, `BMXHT`, `BMXWAIST` |
| P_GHB | `SEQN`, `LBXGH` |
| P_ALQ | `SEQN`, `ALQ111`, `ALQ121`, `ALQ130` (core) — optionally `ALQ142`, `ALQ270` for a binge-drinking extension |

---

## P_DEMO — demographics and survey design

| Column | Meaning | Role |
|---|---|---|
| `SEQN` | respondent sequence number | join key |
| `SDDSRVYR` | data release cycle | guard: must be 66 |
| `RIDSTATR` | interview / examination status | 2 = examined (MEC); required for any exam-based estimate |
| `RIAGENDR` | sex (1 M, 2 F) | model covariate |
| `RIDAGEYR` | age in years at screening | eligibility (18+) and model covariate; **top-coded at 80** |
| `RIDRETH3` | race / Hispanic origin incl. NH Asian | model covariate; 6 levels (1,2,3,4,6,7), **7 = "other/multi" is real, not missing**; no level 5 |
| `RIDEXPRG` | pregnancy status at exam | exclusion for the obesity benchmark; only asked of women ~20–44 |
| `WTMECPRP` | full-sample MEC exam weight | survey design weight — the correct one for CAP/exam data |
| `SDMVPSU` | masked variance pseudo-PSU | survey design cluster; only meaningful within its stratum; **this release has 3 PSUs in some strata** |
| `SDMVSTRA` | masked variance pseudo-stratum | survey design stratum (~24 values, ≈149–172) |
| `INDFMPIR` | family income-to-poverty ratio, top-coded at 5 | **not in the model** (11.6% missing among adults, and unevenly so: 8.9% to 18.3% across race/ethnicity); kept for the missingness comparisons |

**Not kept:** `WTINTPRP` (interview weight — wrong weight for exam data), `RIDAGEMN`
(infants), `RIDRETH1` (superseded by `RIDRETH3`), `RIDEXMON`, all language / proxy /
interpreter fields, `AIALANGA`.

**Optional descriptive additions** (not required by any current analysis; each brings its
own missing codes): `DMDBORN4` country of birth, `DMDYRUSZ` time in US, `DMDEDUC2`
education (adults 20+), `DMDMARTZ` marital status.

---

## P_LUX — liver elastography (FibroScan). Keep all 12.

The outcome file; every column is about the liver exam, so keep the lot.

| Column | Meaning | Notes |
|---|---|---|
| `LUAXSTAT` | elastography exam status | 1 complete / 2 partial / 3 ineligible / 4 not done |
| `LUARXNC` | reason for partial exam | 1 fasting <3 hrs / 2 fewer than 10 valid measures / 3 IQR/M >30% — for the partial-exam accounting |
| `LUARXND` | reason exam not done | completes the "why is CAP missing" story |
| `LUARXIN` | reason ineligible | ditto |
| `LUAPNME` | exam wand / probe type — **character `M`/`XL`, not numeric** | XL probe used for larger body habitus → **correlates with BMI**; CAP/stiffness readings differ by probe. Relevant covariate/QC variable. |
| `LUANMVGP` | count of complete stiffness measures, final wand | recorded individually 0–19, then grouped: **20 = "20–29", 30 = "30+"** — nothing between, nothing above 30 |
| `LUANMTGP` | count of attempted measures, final wand | same grouping |
| `LUXSMED` | median stiffness E (kPa) | device range **1.6–75.0 kPa** |
| `LUXSIQR` | stiffness IQR (kPa) | quality |
| `LUXSIQRM` | stiffness IQR ÷ median, **as a percent** | NHANES completeness rule is `< 30` (not `< 0.30`); can exceed 100% when median is low |
| `LUXCAPM` | median CAP (dB/m) — the steatosis measure | device range **100–400 dB/m**; both bounds are censoring points |
| `LUXCPIQR` | CAP IQR (dB/m) — **absolute**, not a ratio | CAP-specific quality; ratio is constructed as `LUXCPIQR / LUXCAPM` (there is no `LUXCPIQRM`) |

---

## P_BMX — body measures

| Column | Meaning | Role |
|---|---|---|
| `SEQN` | key | |
| `BMXBMI` | body mass index (kg/m²) | primary metabolic covariate; retained as recorded, with values outside 10–100 flagged as implausible |
| `BMXWT` | weight (kg) | sanity-check `BMXBMI` |
| `BMXHT` | standing height (cm) | sanity-check `BMXBMI` |
| `BMXWAIST` | waist circumference (cm) | central adiposity — arguably a better correlate of liver fat than BMI |

**Not kept:** `BMDBMIC` (BMI category — **children/youth 2–19 only**, ~entirely `NA` in an
adults-18+ sample), recumbent length / head circumference (infants), leg / arm / hip
measures, the `BMI*` comment fields (NHANES QC flags — could add if we want exam-quality
detail). `BMDSTATS` (component status) is a candidate if we want an explicit "valid body
exam" gate.

---

## P_GHB — glycohemoglobin

| Column | Meaning | Role |
|---|---|---|
| `SEQN` | key | |
| `LBXGH` | glycohemoglobin / HbA1c (%) | secondary model covariate; partial mediator of BMI → steatosis |

---

## P_ALQ — alcohol use questionnaire

**Core (the frequency model):**

| Column | Meaning | Role |
|---|---|---|
| `ALQ111` | ever had a drink of any kind of alcohol (lifetime ≥ threshold) | **the gate.** Separates never-drinkers from former/current. `alcohol_group` logic depends on it. |
| `ALQ121` | past-12-month drinking frequency | 0–10 ordinal scale; 0 = did not drink in past year; 77/99 = refused/don't know |
| `ALQ130` | average drinks per drinking day, past 12 months | **1–13, then 15 = "15 or more"; 14 is not a valid answer**; 777/999 refused/don't know |

**Skip structure** (why never / former / missing are three different things):
`ALQ111 == 2` (never) → `ALQ121`, `ALQ130` not asked. `ALQ121 == 0` (no drinking in past
year) → `ALQ130` not asked. So a missing `ALQ130` for a lifetime drinker who didn't drink
this year is *structural*, not nonresponse. `alcohol_g_day` therefore records 0 for
never and former drinkers rather than `NA`.

**Optional binge-drinking extension** — a "heavy episodic drinking and CAP" angle on top of
frequency. Adds real work: each has its own conditional skip logic and 777/999 codes.

| Column | Meaning |
|---|---|
| `ALQ142` | # days with 4/5+ drinks, past 12 months |
| `ALQ270` | # times 4–5 drinks within 2 hours, past 12 months |

**Not used:** `ALQ151` (ever drank 4/5+ every day), `ALQ170` / `ALQ170CK` (past-30-day
episodes), `ALQ280` (8+ in a day), `ALQ290` (12+ in a day).
