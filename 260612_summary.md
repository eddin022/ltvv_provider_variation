# LTVV Revision — Task Status Summary
**As of June 12, 2026**

---

## Overall Status

- **Decision Gap** (<6 vs <8 threshold) — BLOCKER, needs Nick
- **Task 1** — Raw-Vt rerun: code complete, needs final review
- **Task 2** — ICU type fixed effect: code complete, needs final review
- **Task 3** — ICU×dept composite: code complete, needs final review
- **Task 4** — TeleICU sensitivity: code complete, needs final review
- **Task 5** — Year separation: not started (blocked on Task 1)
- **Task 6** — Three-model structure: complete
- **Task 7** — MOR rescaling: not started (blocked on Task 1)
- **Task 8** — Vt distribution histogram: code complete, needs final review
- **Task 9** — Missingness table: code complete, needs final review
- **Task 10** — Hospital e-Table: not started
- **Task 11** — Outside-IMV transfers: confirmed, draft paragraph ready
- **Task 12** — 66% PPV + adjusted PPV: confirmed, draft paragraph ready
- **Task 13** — Provider-assignment schematic: not started
- **Task 14** — Non-VC exclusion count: code complete, needs final review
- **Task 15** — Patients-per-provider sub-cohorts: code complete, needs final review
- **Task 16** — Covariate e-Table: not started (blocked on Task 1)
- **Task 17** — Figure 2 exact statistics: code complete, needs final review
- **Task 18** — Admitting categories (optional): not started
- **Task 19** — COVID variable coding: confirmed, draft paragraph ready
- **Task 20** — Provider drop-off explanation: confirmed, draft paragraph ready
- **Task 21** — ECMO exclusion clarification: confirmed, draft paragraph ready

---

## Blocker / Decision Gap

- **<6 vs. <8 mL/kg PBW primary threshold** — this must be confirmed with Nick before Task 1 is run. The choice determines all headline numbers. No task that touches model results should be finalized until this is resolved.

---

## Task-by-Task Status

### TASK 1 — Raw-Vt ≥5h Full Model Rerun *(Critical Path)*
**Status: Code complete, runs, but needs final review**
- Full architectural overhaul: `ltvv_wrangler.ipynb` now uses `clif_respiratory_support.parquet` (raw table) as the primary backbone instead of the LOCF hourly waterfall table
- Day-1 window: first non-null `tidal_volume_set` ≥5h after intubation proxy
- Subsequent days: first non-null `tidal_volume_set` after 14:00 local time
- `initial_vent_day` column added (was missing — latent bug fixed)
- Multiple rounds of bug fixes: dtype mismatches, duplicate-row guards, carry-forward columns (`sf_ratio`, `ph`, `pco2`)
- `bmi_calc` column name mismatch between wrangler and regression fixed
- `charlson` (nonexistent column) removed from imputation list
- Parquet path mismatch between wrangler and regression fixed
- Global rename: `ARDS` → `AHRF` / `ards` → `ahrf` across all three notebooks (53 cells in regression, 7 in wrangler, 4 in vent_ebp_wrangler)

---

### TASK 2 — ICU Type as Cluster-Level Fixed Effect
**Status: Code complete, runs, but needs final review**
- `icu_type` view added in wrangler; joins ADT table to the Vt measurement timestamp (not just date) to capture ICU at moment of clinical decision
- Raw ADT fields used directly — no arbitrary CASE mapping
- `icu_location_type` (5 levels): `general_icu`, `medical_icu`, `mixed_cardiothoracic_icu`, `mixed_neuro_icu`, `cardiac_icu`
- `icu_department_type` (7 levels): `icu`, `neuro / surgical icu`, `medical icu`, `neuro icu`, `cardiac icu`, `oncology icu`, `neonatal icu`
- Reference level: `general_icu` (66% of rows)
- `icu_location_type` added to all 8 model cells in regression (`overall`, `day-1`, `subsequent`, plus all secondary/sensitivity models)
- Before/after MOR/ICC comparison cell added (`ahrf6_icu_location_type_comparison.html`)
- ICU type added to Table 1

---

### TASK 3 — ICU-Type × Department-Type Composite (Secondary Analysis)
**Status: Code complete, runs, but needs final review**
- `icu_composite` column created in wrangler (`icu_location_type + " - " + icu_department_type`); 9 levels:

  | Composite level | n rows |
  |---|---|
  | `general_icu - icu` *(reference)* | 134,100 | %% mixed
  | `general_icu - neuro / surgical icu` | 22,751 | %% mixed
  | `medical_icu - medical icu` | 19,150 | %% medical
  | `general_icu - neuro icu` | 16,194 | %% neuro
  | `mixed_cardiothoracic_icu - cardiac icu` | 4,348 | %% cardiac
  | `mixed_neuro_icu - neuro / surgical icu` | 3,718 | %% mixed
  | `general_icu - oncology icu` | 2,295 | %% medical
  | `general_icu - neonatal icu` | 522 | %% mixed
  | `cardiac_icu - cardiac icu` | 303 | %% cardiac

- Secondary model cell added in regression; outputs `ahrf6_task3_composite_comparison.html`
- Frequency distribution of composite categories printed
%% ask Nick - I read that as "create interaction terms icu-type and department-type", but Claude fought me and told me I'd be dumb to do that because 1. they aren't independent, but nested and 2. the composite is the interaction, just a cleaner version. So wanted to confirm that this is what you meant
%% medical, neuro, cardiac, and mixed groups!!

---

### TASK 4 — TeleICU-Excluded Sensitivity Analysis
**Status: Code complete, runs, but needs final review**
- Filters hospitals 6, 7, 8 from all AHRF imputed datasets
- Refits all three primary models on restricted cohort
- Side-by-side MOR/ICC comparison output: `ahrf6_notele_sensitivity.html`
- `droplevels()` applied to prevent empty fixed-effect cells in `glmer`
%% added sensitivity -- confirm that 6 (Ranges/Hibbing), 7(Northland), and 8(Lakes) are the hospitals we need dropped
%% double check that grand itasca isn't in there!

---

### TASK 5 — Year Separation Re-Check; Conditional Era Collapse
**Status: PENDING — blocked on Task 1 rerun**
- No code written yet; will inspect year coefficient estimates after the raw-Vt rerun to determine if separation persists
- If separation persists → collapse to 4 eras (2011–2015, 2016–2019, 2020–2022, 2023–2025)
- Do not commit to era collapse in the response letter until rerun confirms

---

### TASK 6 — Three-Model Primary Analysis Structure
**Status: Complete**
- Table 2 model label strings updated: `'ahrf-6 Overall'` → `'Overall'`, `'ahrf-6 Initial'` → `'Day 1'`, `'ahrf-6 Subsequent'` → `'Subsequent Days'`

---

### TASK 7 — MOR Rescaling (Age/Decade, P/F per 10 mmHg)
**Status: NOT STARTED — blocked on Task 1 rerun**
- Requires updated model coefficients from the rerun
%% ask Nick
%% unscale things and see if models converge as is. Then also convert age to decades ie 24 year old would be 2.4 decades old. Same for PF ratio.

---

### TASK 8 — Within-Day Vt Distribution Histogram
**Status: Code complete, runs, but needs final review**
- Two-panel supplementary figure added to wrangler
- Panel A: within-day CV histogram (annotated with % of days having CV <10%)
- Panel B: representative Vt/kg IBW histogram with 6 and 8 mL/kg threshold lines
- Output: `fig_task8_vt_distribution.tiff` (600 dpi) and `.png` (150 dpi)
![alt text](task8.png)

---

### TASK 9 — Missingness Table (All Variables)
**Status: Code complete, runs, but needs final review**
- Missingness summary cell added to wrangler: 15 model variables, N missing, % missing, handling method; saves to `etable_task9_missingness.xlsx`; raises error if any column is not found
- Complete-case sensitivity analysis added to regression: uses pre-imputation NAs (not post-MICE) to correctly identify complete cases; outputs `ahrf6_task9_complete_case_comparison.html`
- Hard error on missing column (prevents silent blank rows in supplement)
![alt text](task9.png)

%% carry forward one day (and don't carry forward!!) and then look at numbers again!!
---

### TASK 10 — Hospital Descriptive e-Table
**Status: NOT STARTED**
- No code written; does not depend on Task 1

---

### TASK 11 — Outside-IMV-Transfer Handling
**Status: CONFIRMED — draft paragraph ready for Claire**
- Outside-IMV-transfer patients are NOT excluded; no transfer-origin filter exists anywhere in the pipeline
- Intubation proxy = first local EHR IMV record (not true intubation time at outside hospital)
- For transferred patients, ≥5h window starts from local first charting — may be hours after true intubation
- Subsequent-day stratum unaffected; day-1 stratum may slightly overestimate adherence for this subgroup
- Full draft Methods/Limitations paragraph written
%% admission_type, determine how many transfer patients we have, (something like outside hospital is admission type), how many of those, tell them in response included because its no diffeernt than getting pateint from ed - will require new set of orders and history and physical and left in. fi anything-- argue that outside transfers could bias us toward null of less variation

---

### TASK 12 — Confirm 66% PPV + Prevalence-Adjusted PPV
**Status: CONFIRMED — draft paragraph ready for Claire**
- Confirmed from Hochberg et al., Crit Care Med 2026;54:654-660 (PMID 41467760)
- Validation cohort: N=90, 53% ARDS prevalence
- PPV: 66% (95% CI 50–81%), Se: 52% (95% CI 38–67%), Sp: 69% (95% CI 55–82%)
- Prevalence-adjusted PPV in our cohort (12.7% prevalence): **~20%** via Bayes' theorem — this is a lower bound; Se is likely underestimated per paper
- Three distinct validation figures confirmed and separated (66% PPV / 93% agreement / 96% recent-year accuracy)
- Full draft Limitations paragraph written
%% table, come back

---

### TASK 13 — Provider-Assignment Schematic (Overnight Intubation)
**Status: NOT STARTED**

---

### TASK 14 — Non-VC Mode Exclusion Count
**Status: CONFIRMED — numbers ready for Claire**

**Overall exclusion at measurement window:**
| Stratum | N total | N included | N excluded | % excluded |
|---|---|---|---|---|
| Day-1 (patients) | 24,572 | 24,285 | 287 | 1.2% |
| Subsequent-day (patient-days) | 130,620 | 115,540 | 15,080 | 11.5% |

*Note: Prior numbers (13,577 day-1 / 80,124 subsequent-day excluded) were from a bug in the Task 14 query that flagged a patient as excluded if the FIRST IMV row in the window had null Vt, even if a later row in the same window had a valid Vt. The main analysis uses the first NON-null Vt, so those patients were actually included. Fixed 2026-06-26.*

**Why rows are excluded — mode breakdown among excluded:**

The majority are true non-VC mode exclusions. Data gaps (VC mode with no Vt charted anywhere in the window) are the minority.

| Category | Day-1 excluded | % | Subsequent-day excluded | % |
|---|---|---|---|---|
| **True non-VC mode exclusions** | | | | |
| Pressure Control | 89 | 31.0% | 4,115 | 27.3% |
| Pressure Support / CPAP | 59 | 20.6% | 5,451 | 36.1% |
| APRV | 20 | 7.0% | 807 | 5.4% |
| Blow-by | 11 | 3.8% | 422 | 2.8% |
| SIMV | 10 | 3.5% | 309 | 2.0% |
| Other | 4 | 1.4% | 250 | 1.7% |
| Pressure-Regulated Volume Control | — | — | 12 | 0.1% |
| NAVA | — | — | 4 | 0.0% |
| **Subtotal true non-VC** | **193** | **67.2%** | **11,370** | **75.4%** |
| **VC mode or unknown, Vt not charted (data gap)** | | | | |
| Assist Control-Volume Control (NULL Vt) | 35 | 12.2% | 1,505 | 10.0% |
| Unknown / NULL mode | 59 | 20.6% | 2,205 | 14.6% |
| **Subtotal data gap** | **94** | **32.8%** | **3,710** | **24.6%** |

**Bottom line for Claire (Methods):**
- True non-VC exclusions (day-1): 193 patients (0.8% of 24,572 at window; 67.2% of excluded)
- True non-VC exclusions (subsequent-day): 11,370 patient-days (8.7% of 130,620 at window; 75.4% of excluded)
- Data gaps (VC mode with no Vt charted at all in window) account for the remaining 32–25% of excluded rows — these are genuine missing-data exclusions, not mode exclusions
![alt text](task14.png)

---

### TASK 15 — Patients-Per-Provider for Sub-Cohorts (Table 1)
**Status: Code complete, runs, but needs final review**
- `_ppp_stat()` helper added; appended to both `table1` and `table1_stratified`
- Covers: Overall, Persistent AHRF, Non-AHRF, Day-1 stratum, Subsequent-day stratum
- **Note:** The new patients-per-provider "Overall" value will differ from the previously reported 69 [41–131] — the old code used `drop_duplicates` by hospitalization (day-1 only); the new code deduplicates by `(hospitalization, prov_npi_shifted)` across all days. Manuscript value should be updated after rerun.
![alt text](task15.png)

---

### TASK 16 — Covariate e-Table (Detailed Individual-Covariate ORs)
**Status: NOT STARTED — blocked on Task 1 rerun**

---

### TASK 17 — Figure 2 Exact Statistics
**Status: Code complete, runs, but needs final review**
- New R cell added after Figure 2 generation: groups by provider NPI, computes % adherent, reports exact numerator/denominator for "never adherent" (0%) and ">50% adherent" providers
- Bug fixes: `ltvv_6` column used for adherence (not raw Vt recomputation), `NA` rows filtered before `group_by` to align with Figure 2's denominator
- All figures now routed to `Figures/` subdirectory
![alt text](task17.png)

%% do stat on just initial day and see what that is. in ahrf-6 group. plan to say that stat and add to intro.
---

### TASK 18 — Admitting-Category Distribution (Optional)
**Status: NOT STARTED**

---

### TASK 19 — COVID Variable Coding Confirmation
**Status: CONFIRMED — draft paragraph ready for Claire**
- Binary indicator at hospitalization level (TRUE/FALSE)
- Source: `microbiology_nonculture` table, `organism_category ILIKE '%sars%'` AND `result_category = 'detected'`
- Assignment window: positive test within 14 days before or on date of first intubation
- Missingness: NaN → FALSE (conservative; absence of positive test = COVID-negative)
- Reference category: FALSE; regression label: `covidTRUE`
- Full draft Methods paragraph written

---

### TASK 20 — Figure 1 Provider Drop-Off Explanation
**Status: CONFIRMED — exact numbers and draft paragraph ready for Claire**
- Pre-threshold pool: **1,580 providers** (≥1 day-1 episode, non-null NPI)
- Included (≥25 episodes): **176 (11.1%)**
- Excluded (<25 episodes): **1,404 (88.9%)**
- Excluded providers: median **2 [IQR 1–4]** day-1 episodes; **80.5%** contributed fewer than 5 episodes; **49.6%** contributed exactly 1 episode
- Output saved to `task20_provider_dropoff.txt`
- Full draft Methods paragraph written
![alt text](task20.png)

---

### TASK 21 — ECMO Exclusion Clarification
**Status: CONFIRMED — exact numbers and draft paragraph ready for Claire**
- Two-stage exclusion confirmed:
  - Stage 1 (encounter-level, `ards_classifier.R`): **294 encounters** excluded (ECMO before enrollment criteria; 0.54% of 54,159 reviewed) — negligible, no separate flow-diagram box needed
  - Stage 2 (patient-day-level, wrangler Cell 80): **3,300 patient-days** excluded across **704 encounters** (3.2% of 101,697 pre-exclusion patient-days) — this is the Figure 1 box
- Corrected Figure 1 language: "Excluded: patient-days during which ECMO was active (n = 3,300 patient-days)"
- Full draft Methods paragraph written

---

## Summary Table

| Task | Status | Output Ready for Claire? |
|---|---|---|
| Decision Gap (<6 vs <8 threshold) | **BLOCKER — needs Nick** | — |
| Task 1 — Raw-Vt rerun | Code complete, runs, but needs final review | No |
| Task 2 — ICU type fixed effect | Code complete, runs, but needs final review | No |
| Task 3 — ICU×dept composite | Code complete, runs, but needs final review | No |
| Task 4 — TeleICU sensitivity | Code complete, runs, but needs final review | No |
| Task 5 — Year separation | Not started (blocked on T1) | No |
| Task 6 — Three-model structure | **Complete** | Yes (label fix done) |
| Task 7 — MOR rescaling | Not started (blocked on T1) | No |
| Task 8 — Vt distribution histogram | Code complete, runs, but needs final review | No |
| Task 9 — Missingness table | Code complete, runs, but needs final review | No |
| Task 10 — Hospital e-Table | **Not started** | No |
| Task 11 — Outside-IMV transfers | **Confirmed** | Yes — draft paragraph written |
| Task 12 — 66% PPV + adjusted PPV | **Confirmed** | Yes — draft paragraph written |
| Task 13 — Provider-assignment schematic | **Not started** | No |
| Task 14 — Non-VC exclusion count | **Confirmed** (bug fixed 2026-06-26) | Yes — numbers ready for Claire |
| Task 15 — Patients-per-provider sub-cohorts | Code complete, runs, but needs final review | No |
| Task 16 — Covariate e-Table | Not started (blocked on T1) | No |
| Task 17 — Figure 2 exact statistics | Code complete, runs, but needs final review | No |
| Task 18 — Admitting categories (optional) | **Not started** | No |
| Task 19 — COVID variable coding | **Confirmed** | Yes — draft paragraph written |
| Task 20 — Provider drop-off explanation | **Confirmed** | Yes — draft paragraph written |
| Task 21 — ECMO exclusion clarification | **Confirmed** | Yes — draft paragraph written |

---

## Immediate Next Steps

1. **Resolve the <6 vs. <8 threshold decision with Nick** — nothing can be run until this is settled
2. **Rename `ards_classifier.R` output CSV** from `ahrf_classifier_cohort.csv` and update the R script — required before wrangler can re-run
3. **Execute `ltvv_wrangler.ipynb` end-to-end** to produce updated `LPV_final_data.parquet`
4. **Execute `ltvv_regression.ipynb`** to produce updated model results
5. **Task 5** — inspect year coefficients post-rerun to decide on era collapse
6. Tasks 7, 15, 16, 17 will be ready to finalize immediately after the rerun produces numbers
