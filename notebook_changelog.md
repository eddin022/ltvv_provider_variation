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
