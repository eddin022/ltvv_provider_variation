# Notebook Changelog

Append-only log of all changes to `.ipynb` files in this project.
Format: date · notebook · cells · task · what · why.

---

## 2026-06-03

**Notebook:** `ltvv_wrangler.ipynb`
**Task:** TASK 1 — Raw-Vt ≥5h Full Model Rerun
**Reviewer source:** R1 Minor #6 (LOCF/waterfall artifact)

### Cell 11 — modified
**What:** Added `TRUE AS initial_vent_day` to the `firstTime` branch of the `initial_data` UNION ALL, and `FALSE AS initial_vent_day` to the `data_2pm` branch.
**Why:** The column `initial_vent_day` was referenced in `ltvv_regression.ipynb` (`filter(initial_vent_day == TRUE/FALSE)`) but was never created in the wrangler — a latent bug. This fix also enables the raw Vt query (new cell below) to correctly restrict subsequent-day raw Vt lookups to non-day-1 cohort dates.

### New cell after Cell 11 — inserted
**What:** Added a new DuckDB query (`raw_vt_query` → `raw_vt_df`) that reads from the raw `clif_respiratory_support.parquet` table (`resp_supp_path`) to derive tidal volume at the correct clinical timepoint:
- **Day 1:** first non-null `tidal_volume_set` where `recorded_dttm ≥ first IMV record + 5 hours` (first IMV record = intubation proxy)
- **Subsequent days:** first non-null `tidal_volume_set` where local time (America/Chicago) ≥ 14:00, on each cohort calendar date

Output: `raw_vt_df` with columns `hospitalizations_joined_id`, `date`, `tidal_volume_set`, `tidal_volume_obs`.
**Why:** The previous approach read `tidal_volume_set` from `clif_hourly_resp_support.parquet`, a last-observation-carried-forward (LOCF) table. A Vt charted at hour 2 post-intubation would be LOCF'd to hour 5, making the "≥5h" measurement reflect the earlier charting event rather than the actual value at that time. R1 Minor #6 caught this.

### Cell 44 — modified (comment added)
**What:** Added a note that the `tidal_volume_obs` DuckDB view is retained for reference but is superseded by the raw Vt query above.
**Why:** Documentation only; the view is no longer used in the merge step.

### Cell 63 (markdown) — modified
**What:** Updated section header from "Merging in nearest prior observed tidal volume" to "Merge raw tidal volume into data (Task 1)".
**Why:** The merge_asof approach is replaced; updated header for clarity.

### Cell 64 — replaced
**What:** Replaced the `merge_asof` approach (which merged the nearest prior `tidal_volume_obs` within 3h backward) with a direct left-merge of `raw_vt_df` on `(hospitalizations_joined_id, date)`. Also drops the waterfall-derived `tidal_volume_set` column from `data` before merging, so `tidal_volume_set` in the output is the raw value.
**Why:** The `merge_asof` approach found the nearest prior observed Vt within 3h of an LOCF-constructed timestamp — itself derived from an LOCF table. Both the reference time and the lookup value were waterfall-derived. The new merge uses the raw timepoint-correct values from `raw_vt_df`.

### Cell 66 — modified
**What:** Removed `tidal_obs_dttm` from the display column list (it was an artifact of the old merge_asof timestamp construction and no longer exists).
**Why:** Prevents a KeyError when re-running.

### Cell 75 — replaced
**What:** Rewrote LTVV outcome computation to use the raw `tidal_volume_set` (now in `data` via `raw_vt_df` merge). `ltvv_6`, `ltvv_8`, `ltvv_tidal_volume_set_or_obs_6`, `ltvv_tidal_volume_set_or_obs_8` are all now raw-derived. `tidal_volume_obs` fallback is the raw value from the same measurement event.
**Why:** Completes the Task 1 change — outcomes now reflect the first actual raw Vt charting at the correct timepoint, not a carried-forward value.

**Net column changes in `LPV_final_data.parquet`:**

| Column | Before | After |
|---|---|---|
| `tidal_volume_set` | hourly waterfall LOCF | raw first non-null at ≥5h / ≥14:00 |
| `tidal_volume_obs` | LOCF-table merge_asof within 3h | raw obs at same measurement event |
| `tidal_volume_set_ibw` | waterfall / ibw | raw / ibw |
| `ltvv_6` | waterfall-derived | raw-derived |
| `ltvv_8` | waterfall-derived | raw-derived |
| `ltvv_tidal_volume_set_or_obs_6` | waterfall fallback | raw fallback |
| `ltvv_tidal_volume_set_or_obs_8` | waterfall fallback | raw fallback |
| `initial_vent_day` | did not exist | added (True = day-1, False = subsequent) |
| `tidal_obs_dttm` | existed | removed (merge_asof artifact) |

---

## 2026-06-03 (review fixes, same session)

**Notebook:** `ltvv_wrangler.ipynb`
**Task:** TASK 1 — Bug fixes found during double-check review

### Cell 8d691c43 — raw_subseq CTE, duplicate-prevention fix
**What:** Added `INNER JOIN day1_dates d1 ON cd.hospitalizations_joined_id = d1.hospitalizations_joined_id` and `AND cd.date != d1.day1_date` to `raw_subseq`. Added `raise ValueError` duplicate guard after `con.execute(raw_vt_query).df()`.
**Why:** For hospitalizations where the day-1 provider had <25 cases, their day-1 row is excluded from `initial_data` entirely. `day1_dates = MIN(date) FROM data` therefore points to what is effectively the first *available* date (physiological day 2+). Without the exclusion, both `raw_day1` (which assigns to `day1_date`) and `raw_subseq` (which picks up all `NOT initial_vent_day` rows including that first available date) would produce a row for the same `(hospitalization_id, date)`. UNION ALL creates a duplicate, and Cell 64's left merge would produce duplicate rows in `data`. The `AND cd.date != d1.day1_date` filter closes this gap.

### Cell 64 — remove pd.to_datetime() calls, add assertion
**What:** Removed two `pd.to_datetime()` conversion lines. Added `assert not data.duplicated(...)` after the merge.
**Why:** `data['date']` and `raw_vt_df['date']` both originate from the same DuckDB DATE column (`datetime64[us]`). Calling `pd.to_datetime()` converts to `datetime64[ns]`. Cell 68's `merge_asof` uses `df['date']` loaded fresh from DuckDB (`datetime64[us]`) — mixed `[us]`/`[ns]` precision causes a pandas 2.x TypeError on the tolerance comparison. Removing the conversion avoids this. The assertion catches any residual duplicate rows from CTE logic errors.

---

## 2026-06-05 (code review fixes)

**Notebooks:** `ltvv_wrangler.ipynb`, `ltvv_regression.ipynb`
**Task:** TASK 1 — Code review bug fixes (pre-rerun)

### ltvv_wrangler.ipynb — Cell 62 — modified
**What:** Renamed `data['bmi']` to `data['bmi_calc']`.
**Why:** `ltvv_regression.ipynb` Cell 9 `scale_vars` and Cell 10 `vars_for_impute` both reference `bmi_calc`. The column was named `bmi` in the wrangler, causing `prepare_data()` to stop with "Missing scale vars: bmi_calc" and `data[, vars_for_impute]` to error in R.

### ltvv_wrangler.ipynb — Cell 77 — modified
**What:** Fixed `ffill` cell to reference `ph` and `pco2` (the actual column names after the SQL alias in Cell 59) instead of `ph_min_arterial_or_venous` and `pco2_min_arterial_or_venous`.
**Why:** Cell 59 aliases `ph.ph_min_arterial_or_venous AS ph` and `pco2.pco2_min_arterial_or_venous AS pco2`. The pandas DataFrame therefore has columns `ph` and `pco2`. The old code raised KeyError on the groupby column access, meaning the 3-day carry-forward was never applied to pH or pCO2.

### ltvv_wrangler.ipynb — Cell 93 — modified
**What:** Updated `table1_data` aggregation to use correct column names: `bmi_calc`, `ph`, `pco2` (matching the actual column names in `data`).
**Why:** References to `bmi`, `ph_min_arterial_or_venous`, `pco2_min_arterial_or_venous` were wrong; the aggregation would silently return NaN for BMI and raise KeyError for pH/pCO2.

### ltvv_wrangler.ipynb — Cell 94 — modified
**What:** Updated `continuous_vars` dict keys and `var_order` list to use `bmi_calc`, `ph`, `pco2`. Changed cohort labels from `'ARDS cohort'`/`'Non-ARDS cohort'` to `'Persistent AHRF cohort'`/`'Non-AHRF cohort'`.
**Why:** Column name fixes match Cell 93. Cohort label renamed per locked decision in CLAUDE.md ("persistent AHRF cohort" everywhere).

### ltvv_regression.ipynb — Cell 10 — modified
**What:** Removed `"charlson"` from `vars_for_impute`.
**Why:** The wrangler never creates a `charlson` column (only `elix_vw` is produced). `data[, vars_for_impute]` in R would error with column not found.

---

## 2026-06-05 (Task 2 — ICU type as cluster-level fixed effect)

**Notebooks:** `ltvv_wrangler.ipynb`, `ltvv_regression.ipynb`
**Task:** TASK 2 — Add ICU Type as Cluster-Level Fixed Effect to All Models
**Reviewer source:** Editor #1, R1 Major #1

### ltvv_wrangler.ipynb — Cell id=7 — modified
**What:** Added `adt_path = f'{clif_path}/clif_adt.parquet'`.
**Why:** ADT table is the source for ICU type; path needed for downstream views.

### ltvv_wrangler.ipynb — New cell (icu_disc_md + icu_disc) — inserted after Cell id=7
**What:** Added a markdown header and a discovery query: `SELECT location_type, department_type, COUNT(*) FROM adt_path WHERE location_category = 'icu' GROUP BY ... ORDER BY n DESC`. Must be run before the icu_type view to confirm CASE ILIKE patterns match actual data values.
**Why:** The CASE mapping in the icu_type view depends on the actual strings in `department_type`/`location_type`. The discovery query lets you validate and adjust those patterns before committing to the mapping.

### ltvv_wrangler.ipynb — New cell (icu_type_md + icu_type_view) — inserted after Cell id=20 (hospitalization view)
**What:** Added `icu_type` temp view. Joins the ADT table against the `data` temp table on `recorded_dttm` (exact Vt measurement timestamp) to assign the ICU type at the moment of the clinical decision. Uses `DISTINCT ON (hospitalizations_joined_id, recorded_dttm) ORDER BY in_dttm DESC` to handle the edge case where two ADT intervals overlap the same `recorded_dttm`. CASE maps `COALESCE(department_type, location_type)` to Medical / Surgical / Neurologic / Cardiac / Mixed; unmapped → 'Unknown'.
**Why:** Joining on `recorded_dttm` (not date) ensures that if a patient moves between ICU types mid-day, each Vt measurement is attributed to the ICU they were actually in at that moment. This is the most defensible approach for the reviewers' ICU-type confounding concern.

### ltvv_wrangler.ipynb — Cell id=58 (final_df) — modified
**What:** Added `icu_type.icu_type` to the SELECT list and `LEFT JOIN icu_type USING (hospitalizations_joined_id, recorded_dttm)` to the FROM clause.
**Why:** Propagates ICU type into the final dataset for regression modeling.

### ltvv_wrangler.ipynb — Cell index 94 (table1_data) — modified
**What:** Added `icu_type=('icu_type', lambda x: x.mode()[0] if not x.mode().empty else None)` to the aggregation. Uses modal ICU type across vent days per hospitalization for Table 1 display.
**Why:** Task 2 requires ICU type distribution (patient-days and provider counts per ICU type) added to Table 1.

### ltvv_wrangler.ipynb — Cell id=94 (Table 1 definition) — modified
**What:** Added `'icu_type': 'ICU Type, n (%)'` to `categorical_vars` and `'icu_type'` to `var_order` (after `'sex_category'`).
**Why:** Table 1 output now includes ICU type distribution stratified by AHRF cohort eligibility.

### ltvv_regression.ipynb — Cell index 9 — modified
**What:** Added `'icu_type'` to `factor_vars` and `icu_type = 'Medical'` to `reference_levels`.
**Why:** ICU type must be treated as a factor (not scaled); 'Medical' is the expected reference level (confirm after running discovery query). Adjust if a different category is most common.

### ltvv_regression.ipynb — 8 model cells (ids 20, 32, 34, 45, 57, 70, 81, 92) — modified
**What:** Added `"icu_type"` to `explanatory_vars` in all model formulas.
**Why:** Adds ICU type as a cluster-level fixed effect to all three primary models (ards6 overall, day-1, subsequent) and all secondary/sensitivity models (ards8 overall/initial/subsequent, COVID sensitivity, MV8 overall/initial/subsequent).

### ltvv_regression.ipynb — New cells (icu_comp_md + icu_comp) — inserted after ards6 overall summary
**What:** Added a before/after comparison cell. Fits `ards6_no_icu_model` using the same imputed data and formula but without `icu_type`, then calls `summarize_model()` on both and outputs `ards6_icu_type_comparison.html`.
**Why:** Task 2 requires reporting provider-level MOR and ICC before and after ICU-type adjustment side-by-side. The adjusted MOR is expected to be ≤ unadjusted MOR since ICU type absorbs structural between-provider variance.

---

## 2026-06-08 (Code review fixes — Task 9 cells)

**Notebooks:** `ltvv_regression.ipynb`, `ltvv_wrangler.ipynb`
**Task:** Code review follow-up — findings 1 and 5

### ltvv_regression.ipynb — Cell id=`10` — modified
**What:** Added `data_preimpute <- data` after the imputation variable split, before `mice()` runs.
**Why:** The complete-case sensitivity analysis (cell `task9_cc`) must identify rows that had no missing values in the *original* data, not in the post-MICE fully-imputed data. Saving `data_preimpute` here gives a reference point before any imputation fills NAs.

### ltvv_regression.ipynb — Cell id=`13` — modified
**What:** Added `ards_data_preimpute <- data_preimpute %>% dplyr::filter(cohort_eligible == 1L)` after `ards_data` is constructed.
**Why:** `ards_data` is the ARDS-eligible subset of the imputed data. The corresponding pre-imputation subset (same rows, original NAs intact) is needed so `complete.cases()` in cell `task9_cc` operates on the correct population.

### ltvv_regression.ipynb — Cell id=`task9_cc` — modified
**What:** Replaced `lapply(ards_data, function(df) { df[complete.cases(df[, model_vars]), ] })` with `complete_rows <- complete.cases(ards_data_preimpute[, model_vars])` followed by `lapply(ards_data, function(df) df[complete_rows, ])`. Updated the row-count `cat()` to use `sum(complete_rows)` and `length(complete_rows)`.
**Why:** `ards_data` is fully imputed — `complete.cases()` on it returns TRUE for every row, making the CC filter a no-op and producing an identical comparison to the main model. Using `ards_data_preimpute` (pre-MICE NAs intact) correctly identifies which rows were originally complete, then applies that mask to each imputed dataset.

### ltvv_wrangler.ipynb — Cell id=`task9_miss` — modified
**What:** Replaced `print(f"WARNING: '{col}' not found...")` with `raise ValueError(f"Column '{col}' not found...")`. Simplified the loop body to remove the `None`-handling branches (no longer needed since a missing column now raises immediately).
**Why:** A renamed upstream column produced a silent blank row in the Excel output with only a print warning. Hard-failing ensures the supplement is never published with a missing variable row.

---

## 2026-06-08 (Task 9 — Missingness Table and Complete-Case Sensitivity)

**Notebooks:** `ltvv_wrangler.ipynb`, `ltvv_regression.ipynb`
**Task:** TASK 9 — Missingness Table (All Variables)
**Reviewer source:** R1 Minor #8

### ltvv_wrangler.ipynb — New cells id=`task9_md` + id=`task9_miss` — inserted after ARDS merge, before Task 8
**What:** Builds a missingness summary table for all 15 model variables. For each variable: N missing, % missing, and handling method (MICE PMM / complete case / always present). Saves to `intermediate_outputs/etable_task9_missingness.xlsx`. Prints a WARNING if any variable exceeds the 20% threshold.
**Why:** e-Table required by reviewer R1 Minor #8. Claire references it in Methods. The table uses the final analysis `data` dataframe (after all exclusions, before parquet save) so missingness reflects the actual analysis population.

### ltvv_regression.ipynb — New cells id=`task9_cc_md` + id=`task9_cc` — inserted after `task3_comp`
**What:** Complete-case sensitivity analysis. Filters each imputed dataset to rows with no NA in any model variable (`complete.cases()`), refits the ards6 overall model, and compares MOR/ICC vs. the main MICE-imputed result via `create_model_summary_html()` → `ards6_task9_complete_case_comparison.html`. Reports % of rows retained.
**Why:** CLAUDE.md Task 9 requires a complete-case sensitivity analysis if any variable exceeds 20% missingness. This is an addition alongside the main model — it does not replace any existing cell.

---

## 2026-06-08 (Task 8 — Within-Day Tidal Volume Distribution Histogram)

**Notebook:** `ltvv_wrangler.ipynb`
**Task:** TASK 8 — Within-Day Tidal Volume Distribution Histogram
**Reviewer source:** Editor #8, R1 Minor #5

### New cells id=`task8_md` + id=`task8_fig` — inserted after ARDS merge cell (index 87), before Table 1

**What:** Two-panel supplementary figure:
- **Panel A:** Histogram of within-day coefficient of variation (CV = σ/μ × 100) of Vt/kg IBW across all cohort patient-days with ≥2 raw IMV charting events. Annotated with % of days having CV < 10%. Data: all `tidal_volume_set` records from `resp_supp_path` within episode 1, joined to `cohort_meta` for IBW.
- **Panel B:** Histogram of the single representative Vt/kg IBW value (from `data['tidal_volume_set_ibw']`) overlaid with 6 mL/kg and 8 mL/kg threshold lines. Shows bimodality of the distribution.

Outputs: `intermediate_outputs/fig_task8_vt_distribution.tiff` (600 dpi) and `.png` (150 dpi). Printed stats: median CV [IQR], median range [IQR], % days with CV < 10%.

**Why:** Editor and reviewer questioned the rationale for a binary outcome. Panel A demonstrates within-day Vt is near-constant (CV ≈ 0 for most days → the ≥5h representative measurement captures full-day practice). Panel B shows bimodality around the 6 mL/kg threshold (most patient-days are clearly adherent or non-adherent → binary classification loses minimal information).

---

## 2026-06-05 (Task 3 — ICU-Type × Department-Type Composite Secondary Analysis)

**Notebooks:** `ltvv_wrangler.ipynb`, `ltvv_regression.ipynb`
**Task:** TASK 3 — Build ICU-Type × Department-Name Composite (Secondary Analysis)
**Reviewer source:** Editor #1, WHO DOES WHAT summary

### ltvv_wrangler.ipynb — New cell id=`icu_composite` — inserted after BMI cell (id=61)
**What:** `data['icu_composite'] = data['icu_location_type'] + ' - ' + data['icu_department_type']`. Automatically saved in the final parquet.
**Why:** Creates the 9-level composite for Task 3. Using the composite directly (not `icu_location_type * icu_department_type`) avoids aliased terms — `icu_composite` subsumes `icu_location_type`, so fitting both as main effects + interaction creates structural zeros.

### ltvv_regression.ipynb — Cell id=`9` — modified
**What:** Added `'icu_composite'` to `factor_vars` and `icu_composite = 'general_icu - icu'` to `reference_levels`. Reference level = dominant combination (134,100 rows, 66%).
**Why:** Ensures `icu_composite` is factorized and releveled before any model that uses it is fitted.

### ltvv_regression.ipynb — New cells id=`task3_md` + id=`task3_comp` — inserted after `icu_comp`
**What:** Task 3 supplement section. Fits `ards6_composite_model` replacing `icu_location_type` with `icu_composite` via `setdiff()`. Prints composite frequency distribution. Compares MOR/ICC via `summarize_model()` + `create_model_summary_html()` → `ards6_task3_composite_comparison.html`.
**Why:** CLAUDE.md Task 3 requires secondary model with MOR/ICC comparison (location-type-only vs. composite) and frequency distribution of composite categories.

---

## 2026-06-05 (Task 2 — Replaced derived icu_type with raw location_type + department_type)

**Notebooks:** `ltvv_wrangler.ipynb`, `ltvv_regression.ipynb`
**Task:** TASK 2 — Remove arbitrary CASE mapping; use raw ADT fields directly

### ltvv_wrangler.ipynb — icu_type cell (id=22) — rewritten
**What:** Removed the CASE expression entirely. The `adt_icu` CTE now selects `location_type` and `department_type` raw. Output columns are `icu_location_type` (5 levels: general_icu, medical_icu, mixed_cardiothoracic_icu, mixed_neuro_icu, cardiac_icu) and `icu_department_type` (7 distinct values). Summary query now shows both columns with counts.
**Why:** The CASE mapping to Medical/Neurologic/Cardiac/Mixed was arbitrary and unmaintainable. `location_type` already has 5 self-descriptive, clinically meaningful levels that directly serve as the Task 2 fixed effect without any translation layer. `department_type` is preserved as a second column for Task 3's ICU-type × department-type composite.

### ltvv_wrangler.ipynb — final_df cell (id=60) — modified
**What:** Replaced `icu_type.icu_type` with `icu_type.icu_location_type, icu_type.icu_department_type` in the SELECT.

### ltvv_wrangler.ipynb — table1_data cell (id=92) — modified
**What:** Replaced `icu_type=('icu_type', ...)` with `icu_location_type=('icu_location_type', ...)`.

### ltvv_wrangler.ipynb — Table 1 definition cell (id=93) — modified
**What:** Replaced `'icu_type': 'ICU Type, n (%)'` with `'icu_location_type': 'ICU Location Type, n (%)'` in `categorical_vars` and `var_order`.

### ltvv_regression.ipynb — Cell id=9 — modified
**What:** Replaced `'icu_type'` with `'icu_location_type'` in `factor_vars`. Changed reference level from `icu_type = 'Mixed'` → `icu_location_type = 'general_icu'` (general_icu is 66% of rows, the correct reference category for the raw field).

### ltvv_regression.ipynb — All 8 model cells + vars_all + icu_comp — modified
**What:** Replaced `"icu_type"` / `'icu_type'` with `"icu_location_type"` / `'icu_location_type'` everywhere. Output filename changed to `ards6_icu_location_type_comparison.html`.

---

## 2026-06-05 (Task 2 — ICU type mapping updated from discovery query output)

**Notebooks:** `ltvv_wrangler.ipynb`, `ltvv_regression.ipynb`
**Task:** TASK 2 — Fix ICU type CASE mapping after running discovery query

### ltvv_wrangler.ipynb — Cell id=icu_type_view — modified
**What:** Replaced the generic ILIKE-on-COALESCE CASE with a two-field CASE that checks `department_type` first (for specificity) then `location_type` as a fallback when `department_type = 'icu'` (uninformative). Actual mappings from discovery output:

| location_type | department_type | n | → icu_type |
|---|---|---|---|
| general_icu | icu | 134,100 | Mixed (via `location_type = 'general_icu'`) |
| general_icu | neuro / surgical icu | 22,751 | Neurologic (dept ILIKE '%neuro%') |
| medical_icu | medical icu | 19,150 | Medical (dept ILIKE '%medical%') |
| general_icu | neuro icu | 16,194 | Neurologic (dept ILIKE '%neuro%') |
| mixed_cardiothoracic_icu | cardiac icu | 4,348 | Cardiac (dept ILIKE '%cardiac%') |
| mixed_neuro_icu | neuro / surgical icu | 3,718 | Neurologic (dept ILIKE '%neuro%') |
| general_icu | oncology icu | 2,295 | Medical (dept ILIKE '%oncology%') |
| general_icu | neonatal icu | 522 | Unknown (no match; excluded by age≥18) |
| cardiac_icu | cardiac icu | 303 | Cardiac (dept ILIKE '%cardiac%') |

Key design decisions: `neuro / surgical icu` → Neurologic (these are neurosurgical units where neurological conditions are primary). `oncology icu` → Medical (closest standard category). 'Surgical' does not appear as a distinct ICU type in this dataset. The original COALESCE(department_type, location_type) approach would have mapped the 134,100 `general_icu / icu` rows to 'Unknown' because `department_type = 'icu'` matches no ILIKE pattern.

### ltvv_regression.ipynb — Cell id=9 — modified
**What:** Changed `icu_type = 'Medical'` → `icu_type = 'Mixed'` in `reference_levels`.
**Why:** 'Mixed' (general_icu) is by far the dominant category (134,100 rows, ~66% of total). Using the most frequent category as reference is standard practice and produces more interpretable effect estimates for the less-common ICU types. 'Medical' has only ~19,150 rows (~9%).

---

## 2026-06-05 (Task 2 code review — third pass)

**Notebooks:** `ltvv_wrangler.ipynb`
**Task:** TASK 2 — Two additional bugs found in third review pass

### ltvv_wrangler.ipynb — Cell id=91 (Table 1 definition) — modified
**What:** Added `'icu_type': 'ICU Type, n (%)'` to `categorical_vars` and `'icu_type'` to `var_order` (after `'sex_category'`).
**Why:** Earlier edits targeted `cell_id='94'` which is a markdown section-header cell, not the Table 1 definition. The actual Table 1 definition is `cell id='91'`. `icu_type` was computed in `table1_data` but silently absent from the output because it was in neither `categorical_vars` nor `var_order`.

### ltvv_wrangler.ipynb — Cell id=47 (fio2_set_df for PF ratio) — modified
**What:** Changed `AND vent_episode_duration_hours >= '24'` → `AND vent_episode_duration_hours >= 24`.
**Why:** Same string-comparison bug fixed in `cohort_meta` (Cell id=10) was also present in the FiO2 hourly query used for PF ratio calculation. DuckDB likely auto-casts, but it is technically incorrect.

---

## 2026-06-05 (Task 2 code review — second pass)

**Notebooks:** `ltvv_wrangler.ipynb`, `ltvv_regression.ipynb`
**Task:** TASK 2 — Two additional fixes found during second code review pass

### ltvv_wrangler.ipynb — Cell id=icu_type_view — modified
**What:** Changed `CREATE OR REPLACE TEMP VIEW icu_type` → `CREATE OR REPLACE TEMP TABLE icu_type`. The COUNT summary query at the end of the cell still runs correctly.
**Why:** A TEMP VIEW is evaluated lazily each time it is queried. Since `icu_type` is joined in `final_df` (a full-table scan of `data`), a VIEW re-executes the entire range join against `adt_path` on every reference. Materializing as a TEMP TABLE executes the range join once, which is both faster and avoids any dependency issues if `data` were ever modified between the view definition and `final_df` creation.

### ltvv_regression.ipynb — Cell index 19 (vars_all missingness check) — modified
**What:** Added `"icu_type"` to the `vars_all` vector in the pre-model missingness diagnostic cell.
**Why:** The cell checks NA counts for all model covariates before fitting. `icu_type` is now a covariate in every model but was absent from `vars_all`, so its missingness rate would not be reported. Since `icu_type` is fully populated by the wrangler (COALESCE → 'Unknown'), the expected NA count is 0 — but the check should confirm this explicitly.

---

## 2026-06-05 (Task 2 code review fixes)

**Notebooks:** `ltvv_wrangler.ipynb`
**Task:** TASK 2 — Bug fixes found during post-implementation code review

### ltvv_wrangler.ipynb — Cell id=11 — modified
**What:** Added `r.recorded_dttm` to the explicit SELECT list in the `data` CTE's final SELECT.
**Why:** The `icu_type` view queries `FROM data d` and joins on `d.recorded_dttm`; the final_df join uses `USING (hospitalizations_joined_id, recorded_dttm)`. Neither works if `recorded_dttm` is absent from the `data` table. The column exists in `reps_with_prov` but was not included in the explicit column list.

### ltvv_wrangler.ipynb — Cell id=icu_type_view — modified
**What:** Changed `a.icu_type` → `COALESCE(a.icu_type, 'Unknown') AS icu_type` in the outer SELECT of the `icu_type` view.
**Why:** When the LEFT JOIN finds no ADT interval for a `recorded_dttm` (patient not in any ADT ICU record at that timestamp), `a.icu_type` is NULL. The CASE expression inside the CTE only produces 'Unknown' for ADT rows that exist but match no pattern — not for missing rows. Without COALESCE, NULL propagates to the final dataset and those rows are silently dropped by R's glmer. With COALESCE, they become 'Unknown' and are retained in the model.

---

## 2026-06-09 (Task 14 — Non-VC Mode Exclusion Count)

**Notebook:** `ltvv_wrangler.ipynb`
**Task:** TASK 14 — Non-VC Mode Exclusion Count
**Reviewer source:** R2 Minor #3

### New cells id=`e3f1a981` (markdown) + id=`b312b489` (code) — inserted after Cell id=`11`

**What:** Added a two-query analysis cell that quantifies how many patients (day-1) and patient-days (subsequent-day) were excluded because `tidal_volume_set` was NULL at the measurement window, and breaks down those excluded rows by `mode_category` to separate true non-VC mode exclusions from VC-mode data gaps.

- **Query 1 (summary_14):** For each stratum (day-1, subsequent-day), reports n_total at measurement window, n_included (Vt not NULL), n_excluded (Vt NULL), and % excluded.
- **Query 2 (mode_14):** Among excluded rows only, groups by `mode_category` and reports n and % of excluded — distinguishing non-VC modes (pressure_control, pressure_support, APRV, etc.) from `volume_control` rows where Vt happened to be NULL (data gap), and from rows with unknown mode.

Both queries mirror the Cell 11 `day1_recs` / `subseq_recs` CTE logic exactly (same intubation proxy, same ≥5h and ≥14:00 windows, same episode 1 boundary) but omit the `tidal_volume_set IS NOT NULL` predicate for the denominator. The `day1_date_anchor` CTE uses the Vt-not-null day-1 record (same as Cell 11) to exclude day-1 date from the subsequent-day denominator.

**Why:** R2 Minor #3 requested the number of patients/patient-days excluded due to non-VC ventilation mode at the measurement window, for the flow diagram and Methods. The existing code uses `tidal_volume_set IS NOT NULL` as a proxy for VC mode without explicitly filtering on `mode_category`. The mode breakdown clarifies what fraction of NULL-Vt exclusions reflect true non-VC mode versus a charting gap in a VC-mode patient.

---

## 2026-06-05 (Task 1 code review — second pass)

**Notebooks:** `ltvv_wrangler.ipynb`, `ltvv_regression.ipynb`
**Task:** TASK 1 — Bug fixes found during focused Task 1 code review

### ltvv_regression.ipynb — Cell 7 — modified
**What:** Changed `read_parquet('LPV_final_data.parquet')` → `read_parquet('intermediate_outputs/LPV_final_data.parquet')`.
**Why:** Wrangler saves to `intermediate_outputs/LPV_final_data.parquet` but regression was reading from the root directory — a path mismatch that would cause the R notebook to fail at startup with "file not found."

### ltvv_wrangler.ipynb — Cell id=77 — modified
**What:** Added `sf_ratio` to the carry-forward block alongside `ph`, `pco2`, and `pf_ratio_paired_min`.
**Why:** The markdown header for this cell explicitly listed sf_ratio as a variable to carry forward (up to 3 days), but the code omitted it. sf_ratio is an imputation variable in the regression (`vars_for_impute`), so missing values inflate imputation uncertainty unnecessarily.

### ltvv_wrangler.ipynb — Cell id=81 — modified
**What:** Added `data = data[data['ibw'].notna()]` exclusion with print statement, inside the existing exclusion block.
**Why:** Patients with no height recorded in the hourly table have NULL IBW in `cohort_meta`. When `tidal_volume_set / ibw` is computed in Cell 75, the result is NaN, and `NaN <= 6` evaluates to False → `ltvv_6 = 0`. These rows survive Cell 82's `tidal_volume_set` NA drop and enter the analysis with a silently incorrect outcome of "non-adherent." Explicitly excluding NULL-IBW rows at the exclusion step prevents this.

### ltvv_wrangler.ipynb — Cell id=10 — modified
**What:** Changed `vent_episode_duration_hours >= '24'` (string literal) → `>= 24` (numeric literal) in the `cohort_meta` CTE WHERE clause.
**Why:** `vent_episode_duration_hours` is a numeric column; comparing it to a string literal relies on implicit DuckDB casting and is technically incorrect. Fixed to a proper numeric comparison.

---

## 2026-06-05

**Notebook:** `ltvv_wrangler.ipynb`
**Task:** TASK 1 — Full architectural restructuring (raw table as backbone)

### Cell 9 (markdown) — modified
**What:** Updated header from "Merge hourly vent and hourly provider data" to "Get cohort metadata from hourly table".
**Why:** Accurately describes the hourly table's new sole role.

### Cell 10 — replaced (`hourly_data` → `cohort_meta`)
**What:** Replaced `hourly_data` (hourly table backbone) with `cohort_meta` — a hospitalization-level metadata table. Contains: `ibw`, `hospital_id`, `vent_episode_duration_hours`, `ep1_end_local` (naive local timestamp of last hour of episode 1), `mdm_link_id`. The hourly table is now used only as a cohort filter and metadata source.
**Why:** The hourly table uses LOCF to construct hourly Vt records. Using it as the primary backbone meant the `date`/`recorded_hour` structure was derived from an LOCF table even though Vt was being patched from the raw table. Separating metadata from measurement removes this inconsistency.

### Cell 11 — replaced (raw table as backbone)
**What:** Completely rewrote `data` construction to use `clif_respiratory_support.parquet` as the primary source. Key logic:
- `intubation_times`: MIN(recorded_dttm) per hospitalization within episode 1 = intubation proxy
- `day1_recs`: `QUALIFY ROW_NUMBER() = 1` ordered by `recorded_dttm` after `intubation_dttm + 5h` — selects the full raw record at the correct timepoint; all columns (tidal_volume_set, fio2_set, peep_set, tracheostomy, mode_category) guaranteed from the same charting event
- `subseq_recs`: `QUALIFY ROW_NUMBER() = 1` per `(hospitalization, local_date)` ordered by `recorded_dttm` after 14:00 local — only dates with actual Vt charting appear
- `date` and `recorded_hour` derived from `CAST(recorded_dttm AT TIME ZONE timezone AS DATE/INT)` — no LOCF timestamps in the backbone
- `ep1_end_local + 2h` bounds all raw queries to exclude episode 2+ records
- Provider joined at `(date, recorded_hour)` derived from raw timestamp
- Added `recorded_year = YEAR(date)` for regression covariate
**Why:** Makes the raw table the definitive source for all per-row clinical measurements. The LOCF hourly structure no longer influences date assignment, hour selection, or any column values.

### Cell 8d691c43 — deleted
**What:** Deleted the separate raw Vt query cell.
**Why:** Raw Vt ascertainment is now built directly into Cell 11 (`day1_recs`/`subseq_recs`). No separate patch step needed.

### Cells 43, 44 — deleted
**What:** Deleted the "Get observed tidal volumes" markdown and `tidal_volume_obs` DuckDB view.
**Why:** `tidal_volume_obs` is now selected directly from the raw representative record in Cell 11. The separate view is no longer needed.

### Cells 63, 64 — deleted
**What:** Deleted the "Merge raw tidal volume into data" markdown and the drop+merge cell.
**Why:** `tidal_volume_set` comes directly from Cell 11 now. No patching required.

### Cell 35 — replaced (`vent_daily` from raw table)
**What:** Rewrote `vent_daily` to read from `resp_supp_path` with `cohort_meta` episode 1 filter. `daily_hours_on_vent` computed as time span of IMV records + 1h buffer (approximation; previously was count of hourly records). FiO2 and PEEP aggregates from raw charting events.
**Why:** Removes last use of hourly table for data (as opposed to metadata). Episode 2+ records excluded via `ep1_end_local`.

### Cell 42 — replaced (`vent_mode` with episode 1 filter)
**What:** Updated `vent_mode` to use `resp_supp_path` with `cohort_meta` episode 1 filter and local-timezone date conversion.
**Why:** Was already using the raw table but lacked episode 1 boundary — could pick up episode 2 mode records. Also aligns date computation with the rest of the notebook.

### New cell (5f07b670) after Cell 51 — inserted (sf_ratio_paired)
**What:** Added `sf_ratio_paired` view — pairs SpO2 from vitals with FiO2 from raw `resp_supp_path` within a 1-hour window using `merge_asof`, then takes daily min sf_ratio. Computed identically to `pf_ratio_paired`.
**Why:** `sf_ratio` was previously `spo2 / fio2_set` from a single LOCF hourly row. This replaces it with a properly paired raw value. Both SpO2 and FiO2 timestamps are converted to naive local time before pairing (consistent with pf_ratio approach).

### Cell 59 — updated (`final_df` joins)
**What:** Added `sf_ratio_paired.sf_ratio` to SELECT and `LEFT JOIN sf_ratio_paired USING (hospitalizations_joined_id, date)` to FROM. Removed implicit `spo2` and `sf_ratio` from `data.*` (they no longer exist in `data`).
**Why:** `sf_ratio` is now a separate joined view; must be explicitly included.

**Net architectural change:** The hourly `clif_hourly_resp_support.parquet` table is now used only in Cell 10 (`cohort_meta`) for episode filtering and metadata. All per-row clinical measurements, dates, and hours come from `clif_respiratory_support.parquet`.

---

## 2026-06-09

**Notebook:** `ltvv_wrangler.ipynb`
**Task:** TASK 15 — Patients-Per-Provider for Sub-Cohorts (Table 1)
**Reviewer source:** R1 Minor #9

### Cell id=96 — modified
**What:** Added `_ppp_stat()` helper and patients-per-provider append step after `table1_stratified` is assembled. A new row ("Patients per provider, median [Q1, Q3]") is appended to both `table1` and `table1_stratified` before saving to Excel. Moved `table1.to_excel()` to after the append so the overall patients-per-provider appears in `table1.xlsx`. The stratified Excel gains columns for Overall, Persistent AHRF cohort, and Non-AHRF cohort.
**Why:** Table 1 currently reported patients-per-provider only for the overall cohort (median 69, IQR 41–131). R1 Minor #9 requests this statistic for each sub-cohort.

### Cell id=98 — modified
**What:** Replaced the single-cohort patients-per-provider print with a five-row summary table covering Overall, Persistent AHRF, Non-AHRF, Day-1 stratum, and Subsequent-day stratum. Results printed via `display(ppp_df)` for easy review.
**Why:** Same as above; the day-1 and subsequent-day strata feed into separate regression models and need their own patients-per-provider context.

### Cells id=96 and id=98 — follow-up fixes (code review)
**What:** (1) Changed `int()` to `round()` in the formatted stat string — `int()` truncates (e.g., 74.5 → 74) rather than rounding. (2) Cell id=98 now calls `_ppp_stat()` (defined in id=96) instead of inlining duplicate logic. (3) Boolean filter changed from `== True` / `== False` to `data['initial_vent_day']` / `~data['initial_vent_day']`.
**Note:** The new `_ppp_stat(data)` "Overall" value will differ from the previously reported "69 [41–131]" in the manuscript. The old code used `drop_duplicates('hospitalizations_joined_id')` which kept only the day-1 row per encounter (effectively counting day-1 encounters per provider). The new code uses pair dedup `(hospitalizations_joined_id, prov_npi_shifted)` which counts unique patients per provider across all days — a more complete definition. The manuscript value should be updated after the next full rerun.

---

## 2026-06-10

**Notebook:** `ltvv_regression.ipynb`
**Task:** TASK 17 — Figure 2 Exact Statistics
**Reviewer source:** R1 Minor #11

### New cell id=task17_fig2_stats — inserted after cell id=28 (Figure 2 generation)
**What:** Added a new R code cell that computes per-provider LTVV-6 adherence rates directly from `ards6_data[[1]]` (the same first-imputed AHRF dataset used to generate Figure 2). Groups by `prov_npi_shifted`, computes `pct_adherent = n_adherent / n_days * 100` where adherence is `tidal_volume_set_ibw <= 6`, then prints exact counts for (1) providers with 0% adherence ("never adherent") and (2) providers with >50% adherence.
**Why:** R1 Minor #11 flagged that the manuscript text cited visual estimates from Figure 2 rather than exact numerator/denominator counts. The reviewer noted these are "striking statistics" requiring exact reporting (e.g., "X of Y providers [Z.Z%] had zero LTVV-adherent patient-days").

---

## 2026-06-10 (Global ARDS → AHRF rename)

**Notebooks:** `ltvv_regression.ipynb`, `ltvv_wrangler.ipynb`, `vent_ebp_wrangler.ipynb`
**Task:** CLAUDE.md locked decision — cohort name is "persistent AHRF cohort" everywhere

### All three notebooks — source cells modified
**What:** Replaced every occurrence of `ARDS` → `AHRF` and `ards` → `ahrf` across all cell source in all three notebooks (53 cells in regression, 7 in wrangler, 4 in vent_ebp_wrangler). Covers: R variable names (`ahrf_data`, `ahrf6_model`, `ahrf_classifier_cohort`, etc.), Python variable names (`ahrf_eligible`, `ahrf_data`, etc.), string literals in titles and messages ("AHRF-6 Model", "AHRF-8 Model", etc.), markdown headers, output filenames, and comments.
**Why:** CLAUDE.md locked decision: cohort is "persistent AHRF cohort" (formerly "ARDS cohort"). Renamed throughout to eliminate the old label.
**External dependency:** `ahrf_classifier_cohort.csv` is read from disk in `ltvv_wrangler.ipynb` and `vent_ebp_wrangler.ipynb`. The file is produced by `ards_classifier.R` / `run_ards.bat`, which were not modified here. The CSV file on disk (and the R script that generates it) must be updated before re-running.

---

## 2026-06-10 (Task 17 code review fixes)

**Notebook:** `ltvv_regression.ipynb`
**Task:** TASK 17 — Figure 2 Exact Statistics (code review bug fixes)

### New cells id=figures_dir_md + id=figures_dir_setup — inserted at index 2 (after library imports)
**What:** Added a markdown header "Output Directory" and a two-line code cell: `figures_dir <- "Figures"` and `dir.create(figures_dir, showWarnings = FALSE)`. Updated every `ggsave()`, `output_file =`, and `filename =` argument across all 32 save calls in the notebook to use `file.path(figures_dir, "...")` instead of bare filenames. The function definition defaults in the `create_forest_plot`, `create_fe_table`, and `create_model_summary_html` helper functions were left unchanged.
**Why:** All figures and HTML tables were being written to the working directory root, making outputs hard to find and mixing them with code. Centralising to a `Figures/` subdirectory keeps the project tree clean and makes it easy to zip/share outputs.

---

## 2026-06-10 (Task 17 code review fixes)

**Notebook:** `ltvv_regression.ipynb`
**Task:** TASK 17 — Figure 2 Exact Statistics (code review bug fixes)

### Cell id=task17_fig2_stats — modified [SUPERSEDES entry 2026-06-10 above]
**What:** Two bugs fixed in the provider-level summary:
1. Added `dplyr::filter(!is.na(ltvv_6))` before `group_by`. Previously `n_days = dplyr::n()` counted all rows including those with `NA` in `ltvv_6`, while `n_adherent` excluded them — deflating `pct_adherent` for providers with missing outcome rows and potentially misclassifying providers as "never adherent."
2. Replaced `sum(tidal_volume_set_ibw <= 6, na.rm = TRUE)` with `sum(ltvv_6 == "1")`. The model outcome is the pre-computed binary `ltvv_6` column (a factor after `prepare_data()`). Recomputing adherence from the raw Vt field risks divergence if the wrangler applied different NA handling or capping. Using `ltvv_6` directly ensures the statistics match exactly what the model treats as an adherent event.
**Why:** Bug 1 (denominator mismatch) also created inconsistency with `ltvv6_proportion_plot` — Figure 2's left panel silently drops NA-Vt rows from both numerator and denominator via `cut()` → `group_by`, so the visual and the reported statistics were computed on different denominators. Bug 2 (outcome column divergence) is a correctness concern: Claire's Results text should describe the same adherence events the model fits.

---

## 2026-06-10

**Notebook:** `ltvv_wrangler.ipynb`
**Task:** TASK 20 — Figure 1 Provider Drop-Off Explanation
**Reviewer source:** R3 Minor #11
**Cells changed:** `task20_provider_dropoff` (added at index 12, after Cell id=11)

**What:** Added a new Python code cell that re-runs the minimal CTE chain from Cell 11 (provider_data → intubation_times → day1_recs → day1_with_hour → day1_with_prov → episode_counts) to compute provider counts before the ≥25 day-1-episode threshold is applied. The cell reports: (1) total providers with ≥1 day-1 encounter and a non-null NPI (pre-threshold pool); (2) providers included (≥25 episodes) and excluded (<25 episodes); (3) median [IQR] day-1 episodes per excluded provider; (4) % of excluded providers contributing <5 episodes; (5) a bucketed frequency table (1, 2–4, 5–9, 10–14, 15–19, 20–24 episodes) for the excluded pool. Results are printed to the notebook and saved to `intermediate_outputs/task20_provider_dropoff.txt`.

**Why:** R3 Minor #11 flagged the ~10:1 provider drop-off in Figure 1 (approximately 1,900 → 180 providers) as alarming. The exact pre/post counts and the episode distribution of excluded providers demonstrate that the ≥25 threshold removes providers with insufficient data for stable random-effect estimation (consistent with standard multilevel-analysis practice), not a systematically different subgroup. Claire will incorporate the numbers in Methods.

---

## 2026-06-10 (code review fixes)

**Notebook:** `ltvv_wrangler.ipynb`
**Task:** TASK 20 — Figure 1 Provider Drop-Off Explanation (code review)
**Cells changed:** `task20_provider_dropoff` (modified)

**What:** Three fixes applied during code review:
1. Materialized the shared CTE chain into `CREATE OR REPLACE TEMP TABLE task20_episode_counts` so both the summary-stats query and the bucket-frequency query read from it, eliminating the duplication of the 5-CTE chain.
2. Removed redundant `AND n_episodes < 25` conditions from `n_excluded_lt5` and `pct_excluded_lt5` expressions — `n_episodes < 5` already implies `< 25`.
3. Removed a redundant `import os` (already imported in Cell 3).
**Why:** Duplication of the CTE chain was a maintenance hazard — a filter change in one copy would silently diverge from the other. The redundant condition was misleading without being harmful.

---

## 2026-06-10

**Notebook:** `ltvv_wrangler.ipynb`
**Task:** TASK 22 — IBW Missingness Audit and Recovery
**Reviewer source:** Internal code review (2026-06-05) — NULL IBW causes silent ltvv_6 = 0 errors

### New cell `task22_ibw_audit` — inserted after cell id=62 (ICU composite), before BMI section
**What:** Added an audit cell that, before any recovery attempt, reports (a) total patient-days and unique hospitalizations with NULL `ibw`, (b) breakdown by `hospital_id`, and (c) breakdown by calendar year derived from the `date` column.
**Why:** Characterizes the distribution of NULL IBW to determine whether exclusions are non-random (e.g., concentrated in early years or specific hospitals), which would indicate selection bias.

### New cell `task22_ibw_recovery` — inserted immediately after `task22_ibw_audit`
**What:** For rows where `ibw` is NULL but `height_cm` is available within the plausible range (76.2–244 cm, matching ards_classifier.R bounds) and `sex_category` is Male or Female, derives IBW using the Devine formula: Males = max(50, 50 + 2.3 × (height_cm/2.54 − 60)) kg; Females = max(45.5, 45.5 + 2.3 × (height_cm/2.54 − 60)) kg. Prints counts before recovery, number recovered, and number still NULL.
**Why:** Patients dropped for NULL IBW in the upstream `clif_hourly_resp_support` table are silently excluded. Recovery from raw vitals-derived height reduces this selection bias. Both `height_cm` and `sex_category` are already in `data` after cell id=61 (final merge), making this feasible without additional data joins.

### Cell id=81 — comment updated
**What:** Updated the IBW filter comment from "Require non-null IBW (needed for Vt/kg outcome)" to "Require non-null IBW; recovery from height_cm was attempted above (Task 22)". Updated print label from `'IBW not null'` to `'IBW not null (post-recovery)'`.
**Why:** Clarifies that the filter now excludes only truly unrecoverable patients (no height_cm or out-of-range/unknown sex), not all NULL-IBW patients.

### 2026-06-10 (amendment — bug fixes from code review)

**Notebook:** `ltvv_wrangler.ipynb`
**Task:** TASK 22 — IBW Missingness Audit and Recovery (code-review fixes)

#### Cell `task22_ibw_audit` — updated
**What:** Added `errors='coerce'` to `pd.to_datetime()` call in year-breakdown query. Added comment noting the audit includes `hospital_id == 'delete'` hospitals that are later excluded at cell 81.
**Why:** `errors='coerce'` prevents silent failure on malformed date strings. Comment prevents misreading the audit totals as analysis-sample missingness.

#### Cell `task22_ibw_recovery` — updated
**What:** (1) Added `data['ibw'] = data['ibw'].astype(float)` before any `.loc` assignment to guard against `int64` dtype from DuckDB. (2) Added `n_hosp_before` snapshot (unique hospitalizations with NULL ibw) before the fills, using `.loc[ibw.isna()].nunique()`. (3) Added `n_hosp_after` and `n_hosp_recovered` (unique hospitalizations) after the fills using `recovery_mask`. (4) Updated print statements to report both patient-day and hospitalization counts side-by-side. (5) Added comment explaining that `height_cm` is patient-level (pooled via `mdm_link_id`) — benign for adults.
**Why:** The original cell reported only row (patient-day) counts, mismatching the CLAUDE.md spec ("n hospitalizations") and the audit cell's hospitalization-level reporting. IBW is hospitalization-level so patient-day counts inflate the "n recovered" figure by average ventilator duration.

---

### 2026-06-11 — Task 4: TeleICU-Excluded Sensitivity Analysis

**Notebook:** `ltvv_regression.ipynb`
**Cells added:** `task4_md` (markdown), `task4_notele` (code) — inserted after `task9_cc`, before cell `30`
**Task:** Task 4 — TeleICU-Excluded Sensitivity Analysis

#### Cell `task4_md` — added
**What:** Markdown header introducing the TeleICU-excluded sensitivity section.
**Why:** Section label for supplement; mirrors structure of other sensitivity sections.

#### Cell `task4_notele` — added
**What:** Filters hospitals 6, 7, and 8 from each of the 5 MICE-imputed AHRF datasets (overall, day-1, subsequent) using `droplevels()` to remove empty factor levels. Re-fits all three primary AHRF-6 mixed-effects logistic regression models on the restricted cohort. Calls `summarize_model` for each (primary and no-TeleICU) and outputs a side-by-side HTML comparison via `create_model_summary_html` to `Figures/ahrf6_notele_sensitivity.html`.
**Why:** R3 Major #1 — TeleICU coverage (hospitals 6, 7, 8) complicates attribution of ventilator decisions to the attending of record. Sensitivity tests whether primary MOR/ICC findings are driven by tele hospitals. `droplevels()` is required to prevent empty fixed-effect cells for the excluded hospitals in `glmer`.

---

## 2026-06-11 — ltvv_regression.ipynb — Task 6

**Cells changed:** Cell id=103 (index 114) — modified

#### Cell id=103 — modified
**What:** Updated model label strings in the three primary `summarize_model()` calls: `'ahrf-6 Overall'` → `'Overall'`, `'ahrf-6 Initial'` → `'Day 1'`, `'ahrf-6 Subsequent'` → `'Subsequent Days'`.
**Why:** Task 6 (Editor #5, R1 Minor #10) — Table 2 must have clear header labels matching the three-model structure. Labels for ahrf-8 and MV-8 models are unchanged.

---

## 2026-06-17 (R1 — Replace icu_location_type with icu_type_5cat in regression)

**Notebook:** `ltvv_regression.ipynb`
**Task:** TASK 2 — ICU Type as Cluster-Level Fixed Effect (downstream of W2 wrangler change)
**Reviewer source:** Editor #1, R1 Major #1; meeting 2026-06-12

### Cells id=9, 19, 20, icu_comp, task3_md, task3_comp, task4_notele, 32, 34, 45, 57, 70, 81, 92 — modified (14 cells)
**What:** Global replacement of `icu_location_type` → `icu_type_5cat` across all regression cells. Additional targeted fixes:
- Cell id=9: reference level changed from `icu_type_5cat = 'general_icu'` → `icu_type_5cat = 'mixed'` (mixed is the largest category ~134K rows, correct reference for the 5-category mapping)
- Cell id=icu_comp: output filename changed from `ahrf6_icu_location_type_comparison.html` → `ahrf6_icu_type_comparison.html`
- Cell id=task3_comp: `setdiff(explanatory_vars, "icu_type_5cat")` — composite secondary analysis now correctly drops `icu_type_5cat` before substituting `icu_composite`
**Why:** W2 (wrangler) replaced the raw `icu_location_type` column with the clinically agreed 5-category `icu_type_5cat` mapping (meeting 2026-06-12). The regression notebook must use the same column name. Reference level changed to `mixed` (was `general_icu` under the old raw column) because the 5-category mapping assigns the dominant `general_icu` raw level to the `mixed` clinical category.

### Cells id=9, task3_md, task3_comp — modified (icu_composite removal)
**What:** Removed `icu_composite` entirely from the regression notebook as a functional variable:
- Cell id=9: removed `'icu_composite'` from `factor_vars`; removed `icu_composite = 'general_icu - icu'` from `reference_levels`
- Cell id=task3_md: updated markdown header to reflect Task 3 now reports `icu_type_5cat` distribution, not a composite model
- Cell id=task3_comp: replaced the composite model fit (which swapped `icu_composite` in place of `icu_type_5cat`) with a frequency/provider-count table for `icu_type_5cat`. Removed `ahrf6_composite_model` fit and `ahrf6_task3_composite_comparison.html` output.
**Why:** `icu_composite` as coded in the wrangler is a raw ADT string concatenation (`location_type + ' - ' + department_type`), an intermediate artifact that `icu_type_5cat` supersedes. The meeting 2026-06-12 agreed on `icu_type_5cat` (5 clinical categories) as the definitive ICU-type variable. Fitting a second model with the raw 9-level composite is redundant and uses a variable without clinical labels. Task 3's supplement output is now the `icu_type_5cat` distribution table, which satisfies the reviewer's request to report ICU type patient-days and provider counts.

---

## 2026-06-17 (R2 — Age per decade and sf_ratio per 10 units rescaling)

**Notebook:** `ltvv_regression.ipynb`
**Task:** TASK 7 — MOR Rescaling: Age Per Decade and P/F Per 10 mmHg
**Reviewer source:** Editor #6; meeting 2026-06-12 (`%%` note: "unscale things... convert age to decades... same for PF ratio")

### Cell id=9 — modified
**What:** Added `use_scaling <- FALSE` flag above `scale_vars`. `scale_vars` reverts to all 8 variables (`age`, `bmi_calc`, `height_cm`, `elix_vw`, `laps2`, `ph`, `pco2`, `sf_ratio`). When `use_scaling = FALSE`, z-scoring is skipped; when `TRUE`, all 8 are z-scored.
**Why:** Meeting `%%` note: "unscale things and see if models converge as is." A single boolean is easier to toggle and review than surgical per-variable exclusions. Default is `FALSE` (clinical units) per the meeting decision.

### Cell id=10 — modified
**What:** Prepended two rescaling lines before the `data_impute` split: `data$age <- data$age / 10` (1 unit = 1 decade) and `data$sf_ratio <- data$sf_ratio / 10` (1 unit = 10 sf_ratio units). These run regardless of `use_scaling`.
**Why:** Unit rescaling must happen before the MICE split so imputed values are on the decade/per-10 scale. Independent of z-scoring — when `use_scaling = FALSE`, ORs are directly interpretable in clinical units; when `use_scaling = TRUE`, z-scoring is applied on top of the already-rescaled values.

### Cell id=11 — modified
**What:** Changed `prepare_data(data_combined, scale_vars, ...)` to `prepare_data(data_combined, if (use_scaling) scale_vars else character(0), ...)`. When `use_scaling = FALSE`, an empty character vector is passed so no variables are z-scored.
**Why:** Single toggle point — flipping `use_scaling` in Cell id=9 propagates to all 5 imputed datasets without touching any other cell.

---

## 2026-06-16 (W1 — Carry-forward reduction; W2 — ICU type 5-category; W3 — outside transfer count)

**Notebook:** `ltvv_wrangler.ipynb`
**Tasks:** TASK 9 (carry-forward), TASK 2/3 (ICU type mapping), TASK 11 (outside transfers)
**Reviewer source:** Meeting 2026-06-12 (Nick and Claire)

### W1 — Cell id=82 (markdown) — modified
**What:** Updated header from "3-day max" to "1-day max (per meeting 2026-06-12)" for all four carry-forward variables.
**Why:** Documents the scope change from 3-day to 1-day carry-forward decided at the June 12 meeting.

### W1 — Cell id=82 (code, carry-forward block) — replaced
**What:** Rewrote the carry-forward cell to: (1) capture `data_pre_fill` snapshot before any ffill; (2) apply `ffill(limit=1)` to all four variables (`ph`, `pco2`, `sf_ratio`, `pf_ratio_paired_min`) — reduced from limit=3; (3) compute a separate `data_3day` reference-only copy; (4) print a three-column comparison table (no carry-forward / 1-day / 3-day missingness counts and %) for Nick to review.
**Why:** Meeting decision: 3-day carry-forward was deemed too permissive for pH and pCO2; team agreed to 1-day for all four variables. The comparison printout satisfies the `%%` note "carry forward one day (and don't carry forward!!) and then look at numbers again!!"

### W1 — Cell id=94 (missingness table) — modified
**What:** Updated handling method strings for `ph`, `pco2`, and `sf_ratio` from `"MICE PMM; 3-day carry-forward"` to `"MICE PMM; 1-day carry-forward"`. Replaced `icu_location_type` key/label with `icu_type_5cat` / `"ICU type (5 category)"` / `"Complete (mapped from ADT composite)"`.
**Why:** Reflects actual carry-forward limit in use; aligns with W2 column rename.

### W2 — New cell id=2276c8ee — inserted after Cell id=65 (icu_composite)
**What:** Added a Python cell that maps `icu_composite` (9 raw ADT level combinations) to `icu_type_5cat` (5 agreed clinical categories: medical, surgical, neuro, cardiac, mixed) using an explicit dict. `fillna('unknown')` handles any future composites not in the map. Prints distribution and unmapped count.
**Why:** Meeting 2026-06-12 decision: regression models use 5 clean clinical ICU categories, not raw `icu_location_type` strings. Reference level for regression = `mixed` (largest group). The raw `icu_location_type` and `icu_department_type` columns are retained in the parquet for Task 3 composite secondary analysis.

### W2 — Cell id=102 (table1_data aggregation) — modified
**What:** Changed `icu_type_5cat=('icu_type_5cat', lambda x: x.mode()[0] if not x.mode().empty else None)`.
**Why:** Table 1 now uses the 5-category clinical column (modal ICU type per hospitalization) rather than the raw `icu_location_type`.

### W2 — Cell id=103 (Table 1 definitions) — modified
**What:** Changed `categorical_vars` key/label from `'icu_location_type': 'ICU Location Type, n (%)'` to `'icu_type_5cat': 'ICU Type (5 category), n (%)'`. Updated `var_order` from `'icu_location_type'` to `'icu_type_5cat'`.
**Why:** Table 1 output uses the agreed 5-category column.

### W3 — New cell id=task11_transfers — inserted after Cell id=23 (hospitalization view)
**What:** Added a DuckDB query that joins `hosp_path` against the cohort `data` temp table on `hospitalizations_joined_id`, groups by `admission_type_category`, and prints the full distribution plus total outside-transfer count (n, %). Placed immediately after the hospitalization view so it runs before any exclusions.
**Why:** Task 11 / meeting 2026-06-12 — team decided to include outside-IMV-transfer patients and defend the inclusion. Nick asked Casey to quantify how many there are for Methods. The `admission_type_category` field from the CLIF hospitalization table identifies transfer admissions.

### W3 — New cell id=task11_intub_timing — inserted after cell id=task11_transfers
**What:** Added a Python cell that computes hours from admission to first IMV record for every cohort hospitalization, grouped by admission type. Outputs a summary table (median, IQR, % arrived already intubated) and a histogram saved to `output_path/task11_intubation_timing.png`.
**Why:** Task 11 follow-up — quantifies how many OSH patients arrived already on IMV (negative hours-to-intubation). Provides Methods-paragraph numbers for outside-transfer handling per reviewer request.

---

## 2026-06-17

**Notebook:** `ltvv_regression.ipynb`
**Tasks:** TASK 7 (age/sf_ratio rescaling, use_scaling flag), TASK 3 (icu_composite removal), TASK 17 (day-1 provider stats)
**Reviewer source:** Meeting 2026-06-12 (Nick and Claire)

### R1 — Global find/replace across all model cells — modified
**What:** Replaced every occurrence of `icu_location_type` with `icu_type_5cat` across all model formula cells (ahrf-6 overall, day-1, subsequent; ahrf-8 overall, day-1, subsequent; TeleICU-excluded sensitivity), the `explanatory_vars` definition cells, and the Task 2 before/after MOR comparison cell. Updated reference level from `general_icu` to `mixed`.
**Why:** Downstream of wrangler W2 — the parquet now exports `icu_type_5cat` instead of `icu_location_type` as the primary ICU-type covariate. Reference level = `mixed` (largest group, ~134K rows).

### R1 — Cell id=task3_comp — replaced
**What:** Replaced the ICU composite secondary model (which fitted 9-level `icu_composite` as random effect) with a frequency-distribution table of `icu_type_5cat` (patient-days and unique providers per category). `icu_composite` removed from regression entirely.
**Why:** User decision: `icu_type_5cat` is the definitive variable; `icu_composite` was an intermediate artifact. The 9-level composite model is not needed.

### R2 — Cell id=9 (variable definitions) — modified
**What:** Added `use_scaling <- FALSE` boolean flag. Kept all 8 variables in `scale_vars` (including `age` and `sf_ratio`). Removed `icu_composite` from `factor_vars` and `reference_levels`. Added `icu_type_5cat = 'mixed'` reference level.
**Why:** Task 7 — `use_scaling` flag controls whether z-scoring is applied in `prepare_data()`. When FALSE (current default), ORs are in raw clinical units. Age and sf_ratio are rescaled in Cell id=10 (per-decade and per-10 units) regardless of flag.

### R2 — Cell id=10 (imputation setup) — modified
**What:** Prepended two rescaling lines before the MICE split: `data$age <- data$age / 10` and `data$sf_ratio <- data$sf_ratio / 10`. `original_means` and `original_sds` are computed after rescaling, so they reflect decade-scale age and per-10-unit sf_ratio.
**Why:** Task 7 (Editor #6, meeting 2026-06-12) — express age as per-decade and sf_ratio as per-10 units for clinical comparison against provider MOR. Rescaling before MICE ensures imputation operates on the clinical scale throughout.

### R2 — Cell id=11 (MICE + prepare_data) — modified
**What:** Changed `prepare_data()` call to pass `if (use_scaling) scale_vars else character(0)` as the scale_vars argument.
**Why:** Implements the `use_scaling` boolean introduced in Cell id=9 — when FALSE, `prepare_data()` receives an empty vector and performs no z-scoring.

### R3 — New cell id=task17_day1_stats — inserted after cell id=task17_fig2_stats
**What:** Added an R cell computing provider-level LTVV adherence statistics on day-1 observations only (`initial_ahrf_data[[1]]`): n providers never adherent on day 1, n providers >50% adherent on day 1.
**Why:** Task 17 / `%%` note in 260612_summary.md — "do stat on just initial day and see what that is. in ahrf-6 group. plan to say that stat and add to intro." Complements the overall Figure 2 stats from the existing task17_fig2_stats cell.


---

## 2026-06-22

### Cell id=11 — modified
**Notebook:** ltvv_regression.ipynb
**Task:** Bugfix (no task number — syntax error)
**What:** Removed trailing comma after `icu_type_5cat = 'mixed'` in `reference_levels <- list(...)`.
**Why:** R does not permit trailing commas in `list()` calls; the stray comma caused "argument 5 is empty" error at cell 6 execution, blocking all downstream model runs.

### Cell id=32 — modified (same date: 2026-06-22)
**Notebook:** ltvv_regression.ipynb
**Task:** Task 17 (Day-1 variant) bugfix
**What:** Wrapped the three adjacent string literals inside `cat(sprintf(...))` in `paste0()` to concatenate them before formatting.
**Why:** R does not auto-concatenate adjacent string literals; the missing commas caused "unexpected string constant" parse error, blocking cell execution.

---

## 2026-06-22 — Code Review Fixes (batch)

### Cell id=1 — modified
**Task:** Code review fix #1 — duplicate library
**What:** Removed duplicate `library(patchwork)` call.
**Why:** Loaded twice on lines ~13 and ~17; redundant and adds startup noise.

### Cell id=5 — modified
**Task:** Code review fixes #2, 4, 5, 8, 9
**What:** Five changes to the functions cell:
(a) `extract_random_effects` — added optional `re_group = "prov_npi_shifted"` parameter so the random-effect group is not hard-coded.
(b) `create_forest_plot` — added `exists("rename_terms")` and `exists("custom_order")` guards to prevent errors when those globals are absent.
(c) `summarize_model` — ICC now pooled on the logit scale (Rubin's rules on logit-transformed ICC, back-transformed to [0,1]) so CI cannot exceed bounds.
(d) `create_model_summary_html` — NNT column header relabelled "NNT (illustrative)" to match manuscript framing.
(e) Added `fit_glmer_model(data_list, explanatory_vars, outcome, random_effect)` helper encapsulating the `future_lapply(glmer(...), future.seed = 42L)` pattern, eliminating repeated boilerplate and fixing parallel seed propagation.
**Why:** Reviewers/analysis: robustness, reproducibility, and statistical correctness across all models.

### Cell id=22 — modified
**Task:** Code review fix #10 (mutable globals) + fix #2 (future.seed)
**What:** Defined `ahrf6_vars` as a named local variable; replaced manual `glmer` loop with `fit_glmer_model`.
**Why:** `explanatory_vars` was a mutable global overwritten 8+ times; re-running any model cell silently corrupted downstream formulas.

### Cell id=35 — modified
**Task:** Code review fix #10 + fix #2
**What:** No-ICU comparison cell now references `ahrf6_vars` instead of global `explanatory_vars`; added `future.seed = 42L`.
**Why:** Same mutable-global fragility + reproducibility.

### Cell id=39 — modified
**Task:** Code review fix #3
**What:** Complete-case row filter now matches by `hospitalizations_joined_id` instead of positional row index.
**Why:** Positional indexing silently misaligns if row order differs between `ahrf_data_preimpute` and any imputed dataset.

### Cell id=41 — modified
**Task:** Code review fix #1 (execution order) + fix #10 + fix #2
**What:** Removed comparison summary block (which referenced `ahrf6_initial_model` and `ahrf6_subsequent_model` defined in later cells); replaced manual `glmer` loops with `fit_glmer_model`.
**Why:** Running cell 41 before cells 44/46 errored with "object not found". Comparison block moved to new cell 53.

### Cells id=44, 46 — modified
**Task:** Code review fix #10 + fix #2
**What:** Both day-1 and subsequent ahrf6 model cells replaced with single-line `fit_glmer_model` calls.
**Why:** Eliminated copy-paste boilerplate and mutable-global mutation.

### New cell id=task4_comparison — inserted at position 53
**Task:** Code review fix #1 (execution order fix)
**What:** Task 4 comparison summary (primary vs. No-TeleICU MOR/ICC) now runs after cells 44 and 46, ensuring `ahrf6_initial_model` and `ahrf6_subsequent_model` are defined.
**Why:** Correct execution order for the Task 4 sensitivity analysis output.

### Cells id=58,70,72,83,94,105,107 — modified
**Task:** Code review fix #10 + fix #2
**What:** All remaining model-fitting cells (ahrf8 overall/initial/subsequent, COVID sensitivity, mv8 overall/initial/subsequent) refactored to use `fit_glmer_model` with uniquely-named local var lists (`ahrf8_vars`, `covid_vars`, `mv8_vars`).
**Why:** Eliminated mutable-global `explanatory_vars` overwriting pattern across 8 cells; parallel seeds now correctly propagated.

---

## 2026-06-22 — Back-transform scaled coefficients to clinical units

### Cell id=5 — modified (pool_fixed_effects)
**Task:** Task 7 / convergence fix follow-up
**What:** `pool_fixed_effects` now accepts `sds`, `vars_to_bt`, and `vars_to_skip` arguments. By default it back-transforms all `scale_vars` (using `original_sds`) except `laps2`, dividing β_scaled and SE by the SD used for z-scoring so OR is on the clinical unit scale: OR = exp(β_scaled / SD).
**Why:** Model must be fit on z-scored predictors for Hessian stability (especially Task 4 TeleICU-excluded subset), but ORs should be reported in interpretable clinical units. laps2 is excluded from back-transformation and stays per 1-SD per CLAUDE.md Task 7 guidance.

---

## 2026-06-22 — Remove vars_to_skip from pool_fixed_effects

### Cell id=5 — modified (pool_fixed_effects)
**Task:** Task 7 / back-transform correction
**What:** Removed `vars_to_skip` parameter; all `scale_vars` (including `laps2`) are now back-transformed to clinical units via β_original = β_scaled / SD.
**Why:** User confirmed laps2 should also be reported in its own units, not per 1-SD. vars_to_skip was unnecessary complexity.

---

## 2026-06-22 — Final code review: back-transform correctness fixes

### Cell id=5 — modified (pool_fixed_effects + prepare_data)
**Task:** Code review of back-transformation implementation
**What:** Three fixes:
(a) `pool_fixed_effects` — back-transform now guarded by `use_scaling == TRUE`; if scaling was not applied to the model, SDs are not used, preventing double-deflation of already-natural-unit coefficients.
(b) `pool_fixed_effects` — CI now uses per-row Barnard-Rubin df (`qt(0.975, df[var])`) from `testEstimates` instead of hardcoded 1.96, consistent with the pooled p-values.
(c) `prepare_data` — `scale()` output wrapped in `as.numeric()` to drop the 1-column matrix dimension and keep columns as plain numeric vectors.
**Why:** (a) Silent wrong ORs when use_scaling=FALSE. (b) 1.96 is inconsistent with the t-critical value implied by pooled p-values at small df. (c) matrix columns can cause unexpected coercion behaviour downstream.

## 2026-06-22 — Code Review Pass 1–3 (Iterative Bug-Fix Loop)

**Notebook:** ltvv_regression.ipynb
**Cells changed:** 5 (functions), 32 (Task 17 Day-1 sprintf)
**Task:** Cross-cutting code quality / correctness; also fixes from prior session passes

### Cell 5 — `pool_fixed_effects`: `extra.pars = FALSE`
**What changed:** Changed `mitml::testEstimates(model = model_obj, extra.pars = TRUE)` to `extra.pars = FALSE`.
**Why:** With `extra.pars = TRUE`, `testEstimates` appends variance-component rows (e.g., `Var1[prov_npi_shifted]`) to the estimates matrix. These rows then appeared in the fixed-effects output table as nonsensical ORs (e.g., `exp(0.47)` for a random-intercept variance). Removing extra.pars keeps only fixed-effect rows; MOR/ICC are extracted directly from `VarCorr()` in `summarize_model`.

### Cell 5 — `random_effect_aor`: add `ggsave` before `return(p)`
**What changed:** Added `ggplot2::ggsave(figure_name, plot = p, dpi = 600, width = 8, height = 6)` inside `random_effect_aor` before `return(p)`.
**Why:** The function accepted a `figure_name` parameter but never saved the plot, silently dropping each individual AOR plot. All callers pass a `figure_name` expecting the file to be written; now it is.

### Cell 5 — `create_fe_table`: variance-component row filter
**What changed:** Added `df <- df %>% dplyr::filter(!grepl("^(Var|Cov)[0-9]+\\[", Term))` after the intercept-drop block.
**Why:** Belt-and-suspenders guard in case `extra.pars` is re-enabled elsewhere; ensures variance-component rows never surface as table rows.

### Cell 5 — `prepare_data`: `!is.null(means[[var]])` → `var %in% names(means)`
**What changed:** Guard condition now uses `var %in% names(means) && var %in% names(sds)` instead of `!is.null(means[[var]])`.
**Why:** `means` is a named numeric vector (from `sapply`). For missing keys, `numeric_vec[["nonexistent"]]` returns `NA`, not `NULL`, so `!is.null(NA)` is `TRUE` — the guard would pass and `scale(..., center = NA)` would silently produce all-NA values. Name-membership check correctly handles this.

### Cell 32 — Task 17 Day-1 `sprintf`/`paste0`: `%%%%` → `%%`
**What changed:** Corrected percent-sign escaping in the `paste0` format string from `"0%%%% of day-1 encounters"` to `"0%% of day-1 encounters"` (and two similar occurrences).
**Why:** In a `paste0` string used as the format argument to `sprintf`, `%%` is the correct escape for a literal `%` in the output. `%%%%` causes `sprintf` to see `%%%%` → emit `%%` (two percent signs), displaying "0%%" instead of "0%" in the console output.

## 2026-06-22 — Convergence Fix: Gradient Restart in fit_glmer_model

**Notebook:** ltvv_regression.ipynb
**Cells changed:** 5 (fit_glmer_model helper)
**Task:** Cross-cutting convergence / Task 5 (year separation)

### Cell 5 — `fit_glmer_model`: add gradient restart on convergence warnings
**What changed:** After the initial bobyqa fit (`maxfun = 2e6`), check `fit@optinfo$conv$lme4$messages`. If convergence warnings are present, call `update(fit, start = getME(fit, c("theta","fixef")), ...)` with `maxfun = 2e7` (10x). Accept the restarted fit only if it has fewer warnings than the original.
**Why:** `recorded_year` as a factor (15 year dummies, 2011–2025) creates near-complete separation in sparse year cells, making the Hessian ill-conditioned. The gradient-restart approach is the canonical lme4 fix (Ben Bolker FAQ): re-entering bobyqa from the converged parameter vector lets the optimizer escape the degenerate region with a larger iteration budget. Does not yet implement Task 5 era collapse — that is still conditional on whether year ORs are in the millions after this rerun.

## 2026-06-22 — Task 5: Era Collapse (recorded_year → 4 eras)

**Notebook:** ltvv_regression.ipynb
**Cells changed:** inserted new cell 17 (era creation); modified cell 22 (vars_all), cell 23 (ahrf6_vars), cell 40 (CC analysis)
**Task:** Task 5 — Year Separation Re-Check; Conditional Era Collapse

### New Cell 17 — Add era variable to all data lists
**What changed:** Inserted `add_era()` helper that maps `recorded_year` → 4 eras (2011-2015, 2016-2019, 2020-2022, 2023-2025) and applies it to `ahrf_data`, `mv_data`, `initial_ahrf_data`, `subsequent_ahrf_data`, `initial_mv_data`, `subsequent_mv_data`. Placed before cell 17 alias assignments so `ahrf6_data`/`ahrf8_data` inherit `era` automatically.
**Why:** Persistent convergence warnings (degenerate Hessian, unable to evaluate scaled gradient) in the overall AHRF-6 model after the gradient-restart fix confirmed complete separation in sparse early-year dummy cells. CLAUDE.md Task 5 specifies era collapse as the conditional fix when "year ORs are still in the millions with CIs spanning 0 to infinity."

### Cell 22 (was 21) — vars_all: recorded_year → era
**What changed:** Replaced `"recorded_year"` with `"era"` in the missingness check variable list.
**Why:** Model now uses `era`; missingness check should reflect the actual model variables.

### Cell 23 (was 22) — ahrf6_vars: recorded_year → era
**What changed:** Replaced `"recorded_year"` with `"era"` in `ahrf6_vars`. All models (overall, day-1, subsequent, no-ICU, TeleICU sensitivity, CC, AHRF-8, MV-8, COVID) use `ahrf6_vars` as the base covariate set and will now use era.
**Why:** 4-era fixed effect provides stable year-trend control without per-year complete separation.

### Cell 40 (was 39) — CC analysis: model_vars_cc uses recorded_year for pre-imputation lookup
**What changed:** `model_vars_cc` now uses `setdiff(ahrf6_vars, "era")` + `"recorded_year"` instead of raw `ahrf6_vars`, so `complete.cases` can look up the variable in `ahrf_data_preimpute` (which predates era creation and has no `era` column).
**Why:** `ahrf_data_preimpute` is saved before the era cell runs and has no `era` column. Since `era` is derived from `recorded_year` and is never missing, substituting `recorded_year` in the CC check is equivalent.

## 2026-06-22 — Code Review: rename_terms/custom_order era update; cell 36 fix

**Notebook:** ltvv_regression.ipynb
**Cells changed:** 7 (rename_terms, custom_order), 36 (ahrf6_no_icu_model)
**Task:** Cross-cutting code review after Task 5 era collapse

### Cell 7 — rename_terms: replace 14 recorded_year entries with 3 era entries
**What changed:** Removed `recorded_year2012`–`recorded_year2025` from `rename_terms` and replaced with `era2016-2019`, `era2020-2022`, `era2023-2025` mapped to `"Year: 2016–2019"` etc. (Unicode en-dash). Added `icu_type_5cat` entries (cardiac, medical, neurologic, surgical).
**Why:** After era collapse, model terms are `era2016-2019` etc. — not individual year terms. Without this fix, era dummy terms would appear as raw R variable names in the forest plot and would miss the `^Year:` regex that routes them to the "Year Effects" panel. ICU type was a new Task 2 covariate with no display-name mapping.

### Cell 7 — custom_order: replace 14 year entries with 3 era entries + add ICU type
**What changed:** Replaced 14 "Year: 20XX" entries in `custom_order` with "Year: 2016–2019", "Year: 2020–2022", "Year: 2023–2025". Added ICU type entries (Cardiac, Medical, Neurologic, Surgical) after the hospital block.
**Why:** Same as rename_terms — unmapped terms are unordered in the forest plot table, and terms not in custom_order fall to the bottom of the factor level ordering.

### Cell 36 — ahrf6_no_icu_model: use fit_glmer_model helper
**What changed:** Replaced bare `future_lapply(ahrf_data, function(df) { glmer(...) }, future.seed = 42L)` with `fit_glmer_model(ahrf_data, ahrf6_no_icu_vars, "ltvv_6")`. Also removed the now-redundant `formula_no_icu` and `message(paste("No-ICU formula:", ...))` lines (fit_glmer_model prints the formula itself).
**Why:** This was the only model-fitting call bypassing the helper. Without fit_glmer_model, the no-ICU model skips the gradient restart logic and is inconsistently seeded. Using the helper ensures consistent optimizer settings, seeding, and restart behavior across all models.

## 2026-06-22 — Forest plot: collapse two-panel (main + year) to single panel

**Notebook:** ltvv_regression.ipynb
**Cells changed:** 5 (create_forest_plot); 27, 51, 63, 77, 88, 99, 112 (call sites)
**Task:** Cross-cutting display change following Task 5 era collapse

### Cell 5 — create_forest_plot: remove two-panel layout
**What changed:** Removed `year_breaks`, `year_limits` parameters, `plot_group` split, `plot_main`/`plot_years` separation, and patchwork combination. Now produces a single forest plot showing all fixed effects on one axis. Default `height` increased from 4 to 10 to accommodate a taller single panel.
**Why:** The two-panel design existed because individual year ORs were in the millions and required a completely different axis scale from main effects. After era collapse to 4 eras (Task 5), era ORs are in the same range as patient/hospital effects and belong on the same panel with the same axis.

### Cells 27, 51, 63, 77, 88, 99, 112 — call sites: remove year_breaks / year_limits arguments
**What changed:** Stripped `year_breaks = c(...)` and `year_limits = c(...)` lines from all seven create_forest_plot call sites.
**Why:** Parameters no longer exist in the function signature.

## 2026-06-22 — Fixed effects tables: rename output files; add reference levels

**Notebook:** ltvv_regression.ipynb
**Cells changed:** 5 (create_fe_table), 7 (custom_order, fe_reference_rows), 25, 49, 61, 75, 86, 97, 110 (call sites)
**Task:** Cross-cutting display improvement

### Cell 5 — create_fe_table: reference_rows parameter
**What changed:** Added `reference_rows = NULL` parameter. When supplied, injects rows with `OR = NA` into the table before ordering; these display as "Reference" in the OR column and "—" in the p-value column.
**Why:** Regression tables should show the reference category for each factor alongside the estimated contrasts, so readers don't need to look up the reference levels separately.

### Cell 7 — custom_order: reference label positions; fe_reference_rows definition
**What changed:** Inserted "Race: White", "Sex: Female", "Hospital 9 (ref)", "ICU Type: Mixed (ref)", "Year: 2011–2015 (ref)" into custom_order immediately before their respective factor groups. Added `fe_reference_rows` vector with the same labels for use in all create_fe_table calls.
**Why:** custom_order controls table row ordering; reference rows must appear in the right group position.

### Cells 25, 49, 61, 75, 86, 97, 110 — create_fe_table calls: new filenames + reference_rows
**What changed:** All output filenames renamed to the pattern `{model}_fixed_effects_table.html` (e.g., "ahrf6.html" → "ahrf6_fixed_effects_table.html", "MV8.html" → "mv8_fixed_effects_table.html"). Added `reference_rows = fe_reference_rows` to every call.
**Why:** Old filenames (e.g., "ahrf6.html", "MV8.html") gave no indication of what kind of table the file contained.

## 2026-06-22 — Forest plots: add reference level markers

**Notebook:** ltvv_regression.ipynb
**Cells changed:** 5 (create_forest_plot), 27, 51, 63, 77, 88, 99, 112 (call sites)
**Task:** Cross-cutting display improvement

### Cell 5 — create_forest_plot: reference_rows parameter
**What changed:** Added `reference_rows = NULL` parameter. When supplied, injects rows with `OR = 1.0` and `CI_lower/upper = NA` before the factor-ordering step. These appear as open diamonds (shape 5) at OR=1 on the dashed reference line, with no error bars (`na.rm = TRUE`). Model-estimated terms remain filled circles (shape 16). Legend suppressed (`guide = "none"`).
**Why:** Adds visual context to forest plots — readers see the reference category for each factor group in the correct position on the y-axis, sitting on the reference line.

### Cells 27, 51, 63, 77, 88, 99, 112 — forest plot call sites
**What changed:** Added `reference_rows = fe_reference_rows` to all 10 create_forest_plot calls (cells 51, 77, 112 each contain 2 calls for day-1 and subsequent-day models).
**Why:** All models share the same covariate set and therefore the same reference levels.

## 2026-06-22 — Fix corrupted rename_terms and missing create_fe_table parameter (code review pass)

**Notebook:** ltvv_regression.ipynb
**Cells changed:** 5 (create_fe_table), 7 (rename_terms), 27, 51, 63, 77, 88, 99, 112 (forest plot call sites)
**Task:** Bug fixes from code review

### Cell 7 — rename_terms: five corrupted mappings repaired
**What changed:** Earlier reference-row insertion into custom_order used string replace that also mangled rename_terms values. Five entries were wrong:
  - `race_categoryAmerican Indian or Alaska Native` was mapped to `"Race: White"` → fixed to `"Race: American Indian or Alaska Native"`
  - `sex_categoryMale` was mapped to `"Sex: Female"` → fixed to `"Sex: Male"`
  - `icu_type_5catcardiac` was mapped to `"ICU Type: Mixed (ref)"` → fixed to `"ICU Type: Cardiac"`
  - `era2016-2019` was mapped to `"Year: 2011–2015 (ref)"` → fixed to `"Year: 2016–2019"`
  - `hospital_idHospital 1` was mapped to `"Hospital 9 (ref)"` → fixed to `"Hospital 1"`
  Orphaned bare strings (unnamed vector elements left over from the corruption) were also removed.
**Why:** These would have caused forest plots and fixed-effect tables to display completely wrong label names for five model terms.

### Cell 5 — create_fe_table: reference_rows parameter was never applied
**What changed:** First edit session modified create_fe_table in memory but the file was not saved before a subsequent write overwrote it. Re-applied: added `reference_rows = NULL` parameter, reference row injection block, and `dplyr::if_else(is.na(OR), "Reference", ...)` / `"—"` handling in df_fmt.
**Why:** Without the parameter, every create_fe_table call site (which passes reference_rows = fe_reference_rows) would throw "unused argument" and abort.

### Cells 27, 51, 63, 77, 88, 99, 112 — forest plot call sites: broken file.path() syntax
**What changed:** Prior replacement turned `file.path(figures_dir, "....tiff")` into `file.path(figures_dir, "....tiff",` (the closing ) was consumed), passing reference_rows to file.path() instead of create_forest_plot(). Fixed to `file.path(figures_dir, "....tiff"),` with closing paren before the comma.
**Why:** Would have passed fe_reference_rows as extra path components to file.path(), likely causing a vector-filename error in ggsave.

## 2026-06-22 — Robustify reference row rendering in table and plot functions

**Notebook:** ltvv_regression.ipynb
**Cells changed:** 5 (create_fe_table, create_forest_plot)
**Task:** Bug fix — references not appearing in output

### create_fe_table: three robustness fixes
1. **Explicit is_ref flag**: model rows get `is_ref = FALSE` before injection; reference rows get `is_ref = TRUE` in ref_df. The OR/p-value formatting now uses this flag (via mapply/sapply) instead of relying on `is.na(OR)`.
2. **mapply/sapply instead of dplyr::if_else**: avoids dplyr type-strictness errors when `gtsummary::style_pvalue(NA)` returns an unexpected type; each row is processed independently.
3. **setdiff fallback in custom_order step**: any term not in custom_order now goes to the END rather than becoming NA (which caused silent blank rows). Changed `intersect(custom_order, all_terms)` → `c(intersect(...), setdiff(...))`.
4. **Diagnostic message**: `message("Reference rows injected: N")` printed when injection runs — confirms function received reference_rows.

### create_forest_plot: setdiff fallback in factor ordering
Changed `factor(term_pretty, levels = rev(intersect(custom_order, unique(term_pretty))))` → uses `c(intersect(custom_order, all_labels), setdiff(all_labels, custom_order))` so reference labels not in custom_order still appear in the plot (at the end) rather than becoming NA and being silently dropped by ggplot2.

## 2026-06-24

### ltvv_wrangler.ipynb

- **Cell 33** (modified) — Rewrote `icu_type` DuckDB temp table. Removed `department_type` from CTE and `icu_location_type`/`icu_department_type` from SELECT. Added CASE WHEN to compute 3-level `icu_type` directly from `location_type`: `medical_icu`, `mixed_specialty` (mixed_neuro_icu / cardiac_icu / mixed_cardiothoracic_icu), `general_icu` (all else including NULLs). Removed COALESCE on `out_dttm` — NULL out_dttm now means the range filter fails and the row falls through to `general_icu` rather than falsely extending a stay to '9999-12-31'. — **Task 2** (ICU type as cluster-level fixed effect)

- **Cell 71** (modified) — Replaced `icu_type.icu_location_type, icu_type.icu_department_type` with `icu_type.icu_type` in final_df SELECT. — **Task 2**

- **Cell 73** (modified) — Removed `icu_composite` creation (`icu_location_type + ' - ' + icu_department_type`). No longer needed since ICU type is fully derived in DuckDB. — **Task 2**

- **Cell 74** (modified) — Removed `icu_composite_map` dict and `icu_type_5cat` assignment. Replaced with simple `icu_type` distribution print. — **Task 2**

- **Cell 103** (modified) — Updated missingness table entry from `icu_type_5cat` to `icu_type` with updated description. — **Task 9** / **Task 2**

- **Cell 111** (modified) — Updated Table 1 aggregation from `icu_type_5cat` to `icu_type`. — **Task 2**

- **Cell 112** (modified) — Updated Table 1 categorical variable label and var_order from `icu_type_5cat` to `icu_type`. — **Task 2**

### ltvv_regression.ipynb

- **Cell 7** (modified) — Replaced 5 `icu_type_5cat*` rename_terms entries with 2 (`icu_typemedical_icu`, `icu_typemixed_specialty`). Replaced 6-item ICU custom_order block with 3-item block (`ICU Type: General (ref)`, `ICU Type: Medical`, `ICU Type: Mixed Specialty`). Updated fe_reference_rows from `ICU Type: Mixed (ref)` to `ICU Type: General (ref)`. — **Task 2**

- **Cell 11** (modified) — Updated factor_vars from `icu_type_5cat` to `icu_type`; reference level from `mixed` to `general_icu`. — **Task 2**

- **Cell 22** (modified) — Updated vars_all missingness check from `icu_type_5cat` to `icu_type`. — **Task 2**

- **Cell 23** (modified) — Updated ahrf6_vars from `icu_type_5cat` to `icu_type`. Propagates to ahrf8_vars and mv8_vars. — **Task 2**

- **Cell 36** (modified) — Updated setdiff call from `icu_type_5cat` to `icu_type`. — **Task 2**

- **Cell 37** (modified) — Updated markdown comment to reflect 3-category DuckDB derivation. — **Task 2**

- **Cell 38** (modified) — Updated code comment; replaced group_by from `icu_type_5cat` to `icu_type`. — **Task 2**

- **Cell 72** (modified) — Updated diagnostic group_by from `icu_type_5cat` to `icu_type`. — **Task 2**

### ltvv_regression.ipynb (continued, 2026-06-24)

- **Cell 37** (modified) — Updated markdown heading from "ICU Type 5-Category Distribution" to "3-Category Distribution". — **Task 2** (cosmetic)

- **Cell 38** (modified) — Updated `cat()` print string and comment from "5-category" to "3-category". — **Task 2** (cosmetic)

## 2026-06-25

### ltvv_regression.ipynb

**Cells changed:** 12 (modified), 13 (modified)
**Task:** Imputation model correction — methodological fix for MICE conditioning on AHRF membership

**What changed:**
- Cell 12: Added `cohort_eligible = data$cohort_eligible` as a sidecar column to `data_impute` (after the existing `data_nonimpute` split, so `vars_for_impute` and `data_nonimpute` are unchanged). `cohort_eligible` is preserved in `data_nonimpute` for the AHRF/MV split in cell 15.
- Cell 13: Replaced bare `mice(data_impute, m=5, method="pmm", seed=123)` with a custom call using `make.method()` and `make.predictorMatrix()`. `cohort_eligible` is set to `method=""` (predictor-only, never imputed) and its predictor-matrix row is zeroed (nothing predicts it). `maxit` increased from default 5 to 20 for better MICE convergence with the expanded predictor frame. The completed-dataset assembly now drops `cohort_eligible` from `complete(imp, i)` before `cbind` to avoid a duplicate column (it already exists in `data_nonimpute`).

**Why:** The previous imputation did not condition on AHRF membership. PMM matched missing-value donors from the full MV population, biasing imputed `sf_ratio`, `ph`, `laps2` for AHRF patients toward the (healthier) MV distribution. This left the within-AHRF `sf_ratio` SD at 0.318 (vs ~1.0 for properly scaled variables), inflating the Hessian condition number ~10× in the `sf_ratio` direction and contributing to the "Rescale variables?" convergence warning. Adding `cohort_eligible` as a predictor causes PMM to match AHRF patients to other AHRF patients, producing AHRF-appropriate imputed values. (R1 Minor #6 / CLAUDE.md Task 1 prerequisite.)

## 2026-06-25 (continued)

### ltvv_regression.ipynb

**Cells changed:** new cell inserted at position 17 (between former cells 16 and 17; all downstream cell indices shifted by 1)
**Task:** Post-split AHRF rescaling — convergence warning reduction (CLAUDE.md Task 1 prerequisite)

**What changed:**
- New cell inserted after the AHRF/MV day-1/subsequent split (cell 16) and before era derivation (now cell 18).
- Computes AHRF-specific mean and SD for sf_ratio, ph, laps2 from ahrf_data[[1]] (all AHRF patient-days, imputation 1).
- Applies identical rescaling to all 5 imputations of ahrf_data, initial_ahrf_data, and subsequent_ahrf_data. mv_data and its sub-cohorts are intentionally not rescaled.
- Stores ahrf_compound_sds for Task 7 OR-per-raw-unit conversion: OR per 10 mmHg sf_ratio = OR_model ^ (1 / ahrf_compound_sds["sf_ratio"]).

**Why:** The full-MV-cohort z-scoring in prepare_data() leaves sf_ratio at SD=0.318 within AHRF (AHRF patients have restricted oxygenation by clinical definition). This inflates the Hessian curvature ~10x in the sf_ratio direction, contributing to the "Rescale variables?" convergence warning. Post-split rescaling to AHRF-specific SD reduces this contribution. Clinical ORs are invariant to linear rescaling (OR per raw unit unchanged).

---

## 2026-06-25

**Notebook:** ltvv_wrangler.ipynb
**Cells changed:** 11 (modified), 12 (modified)
**Task:** Duplicate-row fix (provider_data fanout — no CLAUDE.md task number; identified during code review)
**What changed:**
- Cell 11: Added `QUALIFY ROW_NUMBER() OVER (PARTITION BY hospitalizations_joined_id, DATE(recorded_date), CAST(recorded_hour AS INT) ORDER BY hospitalization_id DESC) = 1` to the `provider_data` CTE. This deduplicates the provider table to one row per (hospitalizations_joined_id, date, recorded_hour) before the LEFT JOIN in `reps_with_prov`, eliminating the fanout that was creating duplicate rows in the `data` temp table. Tiebreaker `ORDER BY hospitalization_id DESC` selects the later sub-encounter (e.g. `_2` over `_1`).
- Cell 12: Applied the identical QUALIFY clause to the `provider_data` CTE in the Task 20 `task20_episode_counts` materialization so provider drop-off counts remain consistent.

**Why:** The `provider_path` (clif_provider.parquet) can have multiple rows per (hospitalizations_joined_id, date, recorded_hour) when provider records from sub-encounters (e.g. fv001_1 and fv001_2) both match the join key, or when overlapping shift handoffs produce two active provider records at the same hour. The unconstrained LEFT JOIN fanned each `all_reps` row (already deduplicated to 1 per hospitalization-date by QUALIFY in day1_recs/subseq_recs) into N rows — one per matching provider record — producing the observed duplicate rows in `data`.
