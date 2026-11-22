# Dataset 2: Layoffs Dataset (Layoffs.fyi via Kaggle)

### Source
- **Provider:** Kaggle dataset by user *swaptr*, built from Layoffs.fyi (maintained by Roger Lee). Layoffs.fyi compiles tech-layoff reports from outlets such as Bloomberg, San Francisco Business Times, TechCrunch and The New York Times.
- **URL:** https://www.kaggle.com/datasets/swaptr/layoffs-2022 ; original source https://layoffs.fyi
- **License:** [Database: Open Database, Contents: © Original Authors](https://opendatacommons.org/licenses/odbl/1-0/)
- **Date retrieved:** [DATE RETRIEVED: 2026/11/22]
- **Format:** one CSV file, `layoffs.csv` (0.8 MB).

### Size and Structure
- **Size:** 4,675 records (one row per reported layoff event) and 11 columns. All 4,675 rows parse into exactly 11 fields, and no field contains a line break.
- **Columns:**
  - `company`
  - `location` (headquarters city; non-U.S. cities carry the suffix ", Non-U.S.")
  - `total_laid_off`
  - `date` (layoff date)
  - `percentage_laid_off` (share of the workforce, 0–1)
  - `industry` (30 categories)
  - `source` (news URL)
  - `stage` (funding stage, e.g. Seed, Series B, Post-IPO)
  - `funds_raised` (USD millions)
  - `country` (67 distinct values)
  - `date_added` (date the record was added to Layoffs.fyi)
- **Date coverage:** layoff dates run from 2020-03-11 to 2026-11-11. By year: 2020: 635 rows; 2021: 44; 2022: 1,231; 2023: 1,390; 2024: 635; 2025: 333; 2026: 407.

### Relevance to Our Questions
This dataset answers **Question 3**: among companies that announced layoffs between 2025 and 2026, which are still advertising AI-related roles today, and how does this differ by industry and funding stage?
- It gives us the list of companies with recent layoffs: 740 events from 569 distinct companies dated 2025-01-01 to 2026-11-11 (the last date in the data).
- It also supplies each company's `industry` and `stage`, which are the two grouping variables in Question 3.
- In Milestone 3 we will join it with the Adzuna job postings on a normalized company name. The cleaned table already includes a `company_key` column to support that join.

### Storage and Justification
- **PostgreSQL:** the data is tabular with a fixed, known schema, so relational storage fits. It lets us do all type conversion, validation and de-duplication in SQL inside the database, and it will let us join this table with the other tabular dataset later.
- **Two schemas keep raw and clean data apart:**
  - `raw.layoffs` stores every source column as `TEXT` with no keys, checks or NOT NULL constraints, so no source record can be rejected or altered on load. We add only a surrogate `row_id` (file order) and an `ingested_at` timestamp.
  - `clean.layoffs` holds the typed and standardized data: `DATE`, `INTEGER`, `NUMERIC(5,4)` and `NUMERIC(12,1)` columns, a primary key, NOT NULL on `company` and `layoff_date`, and CHECK constraints (share between 0 and 1, count > 0).
  - `clean.layoffs_rejected` keeps every excluded raw record together with its reason.
- **Loading:** `layoffs.csv` is loaded with a server-side `COPY` from a read-only mount, so the source file cannot be modified. The load script stops with an error if the loaded row count differs from the 4,675 rows in the CSV.
- **Rerunnable SQL:** all steps are numbered scripts that can be rerun: `01_raw`, `02_profile`, `03_clean` and `04_verify`.

### Data Quality
We profiled every column (log: `quality_log.md`, 39 entries). The most important issues are:
- **Missing size information:**
  - `total_laid_off` is missing in 1,627 rows (34.8%).
  - `percentage_laid_off` is missing in 1,758 rows (37.6%).
  - 763 rows have neither value.
- **Placeholders:** `stage` = "Unknown" in 782 rows, plus 8 blank stages. `industry` = "Other" in 320 rows.
- **Text-encoded types:** dates are stored as `M/D/YYYY` text, and counts are stored as float text (`1500.0`). 38 percentages carry floating-point artifacts, e.g. `0.35000000000000003`.
- **Inconsistent values:**
  - `UAE` vs `United Arab Emirates` for the same country.
  - 31 rows whose location label contradicts their country, e.g. "Tel Aviv, Non-U.S." with country United States.
  - 16 company names and 3 source values have stray spaces.
  - 23 companies appear under more than one spelling (`HubSpot`/`Hubspot`, `TikTok`/`Tiktok`).
- **Duplicates:**
  - No row is an exact duplicate.
  - 2 events were entered twice from different news articles (Beyond Meat, Cazoo).
  - 21 company–date groups (44 rows) are near duplicates: either separate cuts at different sites or conflicting reports of the same event.
- **No date problems:** no dates failed to parse and none are in the future. 36 records have a `date_added` earlier than the layoff date.

### Initial Cleaning
All cleaning is done in SQL (`03_clean.sql`) and runs as a single transaction:
- **Types:** parsed text into proper types with a strict date parser.
- **Rounding:** rounded percentages to 4 decimals.
- **Placeholders:** converted stage "Unknown" to NULL.
- **Text and categories:** trimmed text and standardized `UAE`.
- **Location:** split `location` into `location_city` plus a "Non-U.S." flag.
- **Duplicates:** removed exact repeat events. The rule is to keep the first row in file order; the duplicate goes to the rejected table with `duplicate_of_row_id`.
- **Flags instead of guesses:** location–country conflicts (`location_country_conflict`) and same-day multiple reports (`same_day_reports`) are flagged, not "fixed", because the correct value cannot be determined.
- **No imputation:** missing values were not filled in. The NULL counts in raw and clean match for every column.

**Row counts:**
- Before: raw 4,675.
- After: clean 4,673 and rejected 2. The check raw = clean + rejected passed, and the script fails loudly if it does not.
- The Question 3 window (2025–2026) keeps all 740 rows (569 companies); none were rejected.

### Limitations
- **Location:** `location` is the company's **headquarters**, not where employees were laid off.
- **Counts are lower bounds:** about a third of events have no headcount, and some report only a percentage or a shutdown.
- **No reason field:** we cannot separate AI-driven restructuring from other causes.
- **Coverage:** it is skewed toward tech companies and English-language media. 2,941 of the 4,675 rows are U.S. companies.
- **Unverified sources:** source URLs were not checked; at least one URL points to an unrelated article.
- **Company names:** names are not standardized across the dataset (e.g. "Meta" vs "Meta Platforms, Inc." in Adzuna). Full entity matching is deferred to Milestone 3.
