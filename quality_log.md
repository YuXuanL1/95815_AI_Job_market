# Data Quality Log — Layoffs dataset (raw.layoffs → clean.layoffs)

Source file: `layoffs.csv` (4,675 data rows, 11 columns, 817,342 bytes, ASCII, no BOM). The file was never modified; it is mounted read-only into the database container.
Every count below comes from `sql/02_profile.sql` (query IDs P1–P22) or `sql/04_verify_and_examples.sql` (V1–V3, E1–E10), run against PostgreSQL 16.16 on 2026-11-22.

**Rules used**
- **Critical issues fail or reject.**
  - A load-count mismatch or a raw ≠ clean + rejected mismatch raises an exception, and the whole clean transaction rolls back.
  - A row with a missing company, an unparseable date or a non-numeric number goes to `clean.layoffs_rejected` with a reason.
- **Recoverable issues are corrected, standardized or flagged.** None are imputed: missing values stay NULL.

| # | Issue | How detected | Rows affected | How handled |
|---|---|---|---|---|
| 1 | Load completeness | P1: `count(*)` vs Python `csv` reader count; assertion in `01_raw.sql` | 4,675 of 4,675 loaded | **Critical check passed.** The load script raises an exception if the counts differ. |
| 2 | Dates stored as text `M/D/YYYY`, with and without leading zeros (e.g. `11/11/2026`, `3/31/2020`) | P4 pattern scan (4 patterns: `9/99/9999`, `9/9/9999`, `99/99/9999`, `99/9/9999`) | 4,675 (`date`), 4,675 (`date_added`) | Parsed to `DATE` with a strict parser `clean.try_mdy_date()` that checks the format and that the date round-trips (rejects e.g. 2/30/2023). |
| 3 | Unparseable dates | P5 round-trip check | 0 `date`, 0 `date_added` | None found. Any future failure is rejected with reason `unparseable or missing layoff date` or `unparseable date_added`. |
| 4 | Date range | P5 | `date` 2020-03-11 to 2026-11-11; `date_added` 2020-03-28 to 2026-11-14 | No dates in the future. Matches the documented coverage. |
| 5 | `date_added` earlier than the layoff `date` (logically odd: record added before the event) | P5 | 36 | Kept as published (could be announced-in-advance layoffs or entry errors; we can't tell which). Documented; not corrected. Example: HP, date 2025-11-25, added 2025-03-01. |
| 6 | `total_laid_off` stored as float text (`1500.0`) | P7 pattern scan | 3,048 values | Cast to `INTEGER`. P8 found 0 non-integer values, so nothing is lost. |
| 7 | `total_laid_off` missing | P2 | 1,627 (34.8%) | Kept as NULL, not imputed. Counts are lower bounds (see Limitations). |
| 8 | `total_laid_off` non-numeric / ≤ 0 / extreme | P7, P8, P9 | 0 non-numeric, 0 ≤ 0; range 3–22,000; median 90; p99 ≈ 4,053 | Extreme values checked by hand (Intel 22,000; Oracle 21,000; Amazon 16,000). They are plausible large-company layoffs and were kept. `CHECK (total_laid_off > 0)` is added in clean. |
| 9 | `percentage_laid_off` format | P7, P10 | 2,917 values in `0.xx` form; 0 with a `%` sign; 0 > 1 | Already a 0–1 share. Stored as `NUMERIC(5,4)` with `CHECK (0..1)`. |
| 10 | `percentage_laid_off` floating-point artifacts (e.g. `0.35000000000000003`, `0.7000000000000001`) | P10 (more than 4 decimals) | 38 | Rounded to 4 decimals (→ 0.3500, 0.7000). |
| 11 | `percentage_laid_off` missing | P2 | 1,758 (37.6%) | Kept as NULL. |
| 12 | `percentage_laid_off = 0.0` with 52 people laid off (TaskUs) | P10 | 1 | Kept. It is most likely a share rounded down to 0 at the source. Documented. |
| 13 | `percentage_laid_off = 1.0` (company shut down) | P10 | 381 | Kept. Meaningful value: the whole company shut down. |
| 14 | No size information at all (both count and percentage missing) | P11 | 763 | Kept. The layoff event is still real and relevant to Q3 (did the company lay people off?). |
| 15 | `funds_raised` missing | P2 | 556 | Kept as NULL. |
| 16 | `funds_raised` has decimals in some rows (`455.2`) and very large values for public companies (Netflix 121,900) | P7, P12 | 53 with decimals | Stored as `NUMERIC(12,1)`. Assumed to be USD millions as published by Layoffs.fyi (unit still to be confirmed on the source page). Large values for public companies are kept. |
| 17 | `stage` placeholder `Unknown` | P2, P3, P13 | 782 | Converted to NULL (it means "missing"). |
| 18 | `stage` missing | P2, P13 | 8 | Kept as NULL. Clean `stage` therefore has 790 NULLs (V3). |
| 19 | `industry = 'Other'` (vague catch-all category) | P3, P14 | 320 | Kept as a real source category, not treated as missing. Analysts should note it is uninformative. |
| 20 | `industry` missing | P2 | 2 | Kept as NULL. |
| 21 | `country` synonym `UAE` vs `United Arab Emirates` | P15 | 3 rows `UAE` | Standardized to `United Arab Emirates` (10 rows in total after cleaning). |
| 22 | `country` missing | P2 | 2 | Kept as NULL. |
| 23 | `location` mixes two formats: `City` for U.S. HQs and `City, Non-U.S.` for others | P16 | 1,718 with suffix; 2,956 without | Original kept in `location`. Derived `location_city` (suffix removed) and `location_non_us_label` (boolean). |
| 24 | `location` = just `Non-U.S.` (no city) | E6 | 4 | `location_city` = NULL. |
| 25 | `location` missing | P2 | 1 | Kept as NULL. |
| 26 | `location` disagrees with `country` (e.g. `Tel Aviv, Non-U.S.` with country United States; `SF Bay Area` with country Israel) | P17 | 31 | Kept unchanged and flagged with `location_country_conflict = true`. We can't tell which field is wrong, so we don't guess. |
| 27 | Leading/trailing spaces in `company` | P2 (untrimmed) | 16 | Trimmed (e.g. `"WeWork "` → `WeWork`). |
| 28 | Leading/trailing spaces in `source` | P2 (untrimmed) | 3 | Trimmed. |
| 29 | `source` contains a non-URL (`Times Internet`) | E4 | 1 | Kept as published. Documented. |
| 30 | `source` URL does not match the record (Coursera row links to an article about an FAA ground stop) | Manual inspection of first rows | 1 found (not systematically checkable) | Kept. Documented as a limitation: source links were not verified. |
| 31 | `source` missing | P2 | 3 | Kept as NULL. |
| 32 | Exact duplicate rows (all 11 columns identical) | P18 | 0 | None found. |
| 33 | Same event recorded twice: identical on every column except `source` and `date_added` | P19 | 2 pairs: Beyond Meat (3197/3198) and Cazoo (3808/3809) | **Removed.** Rule: keep the first row in file order (lowest `row_id`). The later copy goes to `clean.layoffs_rejected` with reason `duplicate event` and `duplicate_of_row_id`. Rejected rows: 3198, 3809. |
| 34 | Near duplicates: same company and same date but different details (other location, count, stage or country) | P20 | 21 groups / 44 raw rows; after dedup, 19 groups / 40 clean rows | **Kept and flagged** with `same_day_reports > 1`. Many are real separate cuts at different sites (Amazon Port St. Lucie + Seattle; Oracle SF + Seattle). Others are conflicting reports of one event (Oda: Sweden vs Norway; IronNet 90 vs 55). Merging them would require choosing a value, which we avoid. To be resolved in analysis. |
| 35 | Same company spelled differently (case, punctuation, trailing spaces) | P21: compare after lowercasing and removing non-alphanumerics | 23 name groups (e.g. `HubSpot`/`Hubspot`, `TikTok`/`Tiktok`, `Mr Yum`/`Mr. Yum`, `SkipTheDishes`/`Skip the Dishes`) | Original spelling kept in `company`. Added `company_key` (lowercase alphanumerics) as a matching aid for the Milestone 3 join with Adzuna. Known false positive: `&Open` and `Open` share a key but appear to be different companies. Suffix variants (`Ada`/`Ada Health`, `Carbon`/`Carbon Health`) are **not** merged; deciding those needs manual review in Milestone 3. |
| 36 | Rows in the Q3 window (layoff date 2025-11-01 to 2026-11-11) | P22, V1 | 453 rows, 389 distinct companies (0 rejected) | Kept. In this window, 166 rows have no `total_laid_off` and 70 have `stage` Unknown/missing (P22). |
| 37 | Reconciliation raw = clean + rejected | `DO` block in `03_clean.sql`; V1 | 4,675 = 4,673 + 2 | **Critical check passed.** The script raises an exception and rolls back if it fails. |
| 38 | Uniqueness of the clean key | Checked in `03_clean.sql` before `ADD PRIMARY KEY` | 0 duplicate `row_id` | Primary key `row_id` added only after the check passed. |
| 39 | No imputation | V3: NULL counts raw vs clean | total 1,627 = 1,627; pct 1,758 = 1,758; funds 556 = 556; stage 790 = 790; industry 2 = 2; country 2 = 2 | Confirmed: cleaning did not fill in any values. |
