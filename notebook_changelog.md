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
