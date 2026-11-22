-- 03_clean.sql : CLEAN layer for the Layoffs dataset (rerunnable, all-or-nothing)
-- Input : raw.layoffs (all text)
-- Output: clean.layoffs           typed, trimmed, standardized, de-duplicated
--         clean.layoffs_rejected  every raw row NOT in clean.layoffs, with a reason
-- Guarantee (checked at the end, fails loudly): raw rows = clean rows + rejected rows.
-- No imputation: missing values stay NULL.
-- Run: docker exec -i de-postgres psql -U postgres -d ai_jobs -f /project/sql/03_clean.sql

\set ON_ERROR_STOP on
BEGIN;

CREATE SCHEMA IF NOT EXISTS clean;

-- ---------------------------------------------------------------------------
-- Helper: strict M/D/YYYY parser. Returns NULL instead of raising an error,
-- and rejects strings that to_date would silently "fix" (e.g. 2/30/2023).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clean.try_mdy_date(s text) RETURNS date
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE d date;
BEGIN
    IF s IS NULL OR btrim(s) !~ '^\d{1,2}/\d{1,2}/\d{4}$' THEN
        RETURN NULL;
    END IF;
    d := to_date(btrim(s), 'MM/DD/YYYY');
    IF to_char(d, 'FMMM/FMDD/YYYY') <> regexp_replace(btrim(s), '(^|/)0', '\1', 'g') THEN
        RETURN NULL;
    END IF;
    RETURN d;
EXCEPTION WHEN others THEN
    RETURN NULL;
END $$;

DROP TABLE IF EXISTS clean.layoffs;
DROP TABLE IF EXISTS clean.layoffs_rejected;

-- ---------------------------------------------------------------------------
-- Step 1: type every row (no rows removed yet)
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE typed ON COMMIT DROP AS
SELECT
    r.row_id,
    nullif(btrim(r.company), '')                                     AS company,
    regexp_replace(lower(btrim(r.company)), '[^a-z0-9]', '', 'g')    AS company_key,
    nullif(btrim(r.location), '')                                    AS location,
    CASE WHEN btrim(r.location) = 'Non-U.S.' THEN NULL
         ELSE nullif(regexp_replace(btrim(r.location), ',\s*Non-U\.S\.$', ''), '')
    END                                                              AS location_city,
    (r.location LIKE '%Non-U.S.%')                                   AS location_non_us_label,
    CASE WHEN btrim(r.country) = 'UAE' THEN 'United Arab Emirates'
         ELSE nullif(btrim(r.country), '') END                       AS country,
    nullif(btrim(r.industry), '')                                    AS industry,
    CASE WHEN lower(btrim(r.stage)) = 'unknown' THEN NULL
         ELSE nullif(btrim(r.stage), '') END                         AS stage,
    CASE WHEN btrim(r.total_laid_off) ~ '^\d+(\.0+)?$'
         THEN btrim(r.total_laid_off)::numeric::integer END          AS total_laid_off,
    CASE WHEN btrim(r.percentage_laid_off) ~ '^\d*\.?\d+$'
         THEN round(btrim(r.percentage_laid_off)::numeric, 4) END    AS percentage_laid_off,
    CASE WHEN btrim(r.funds_raised) ~ '^\d*\.?\d+$'
         THEN btrim(r.funds_raised)::numeric END                     AS funds_raised,
    clean.try_mdy_date(r.date)                                       AS layoff_date,
    clean.try_mdy_date(r.date_added)                                 AS date_added,
    nullif(btrim(r.source), '')                                      AS source,
    -- raw strings kept to detect values that failed to parse
    r.total_laid_off AS raw_total, r.percentage_laid_off AS raw_pct, r.funds_raised AS raw_funds,
    r.date AS raw_date, r.date_added AS raw_date_added
FROM raw.layoffs r;

-- ---------------------------------------------------------------------------
-- Step 2: critical-issue checks -> reject reason (first failing rule wins)
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE judged ON COMMIT DROP AS
SELECT t.*,
    CASE
        WHEN company IS NULL                                  THEN 'missing company'
        WHEN layoff_date IS NULL                              THEN 'unparseable or missing layoff date'
        WHEN raw_total IS NOT NULL AND total_laid_off IS NULL THEN 'non-numeric total_laid_off'
        WHEN raw_pct   IS NOT NULL AND percentage_laid_off IS NULL THEN 'non-numeric percentage_laid_off'
        WHEN percentage_laid_off > 1                          THEN 'percentage_laid_off above 1'
        WHEN raw_funds IS NOT NULL AND funds_raised IS NULL   THEN 'non-numeric funds_raised'
        WHEN raw_date_added IS NOT NULL AND date_added IS NULL THEN 'unparseable date_added'
    END AS critical_reason
FROM typed t;

-- ---------------------------------------------------------------------------
-- Step 3: de-duplication among rows that passed Step 2
-- Rule: two rows describe the same layoff event if they are identical on every
-- source column except `source` and `date_added` (company compared after trim +
-- lower-case). Keep the FIRST row in file order (lowest row_id); later copies
-- are rejected with duplicate_of_row_id pointing to the kept row.
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE deduped ON COMMIT DROP AS
SELECT j.*,
       first_value(row_id) OVER w AS keep_row_id,
       row_number()        OVER w AS rn
FROM judged j
WHERE critical_reason IS NULL
WINDOW w AS (PARTITION BY lower(company), location, total_laid_off, percentage_laid_off,
                          layoff_date, industry, stage, funds_raised, country
             ORDER BY row_id);

-- ---------------------------------------------------------------------------
-- Step 4: outputs
-- ---------------------------------------------------------------------------
CREATE TABLE clean.layoffs (
    row_id                    bigint       NOT NULL,   -- lineage to raw.layoffs.row_id
    company                   text         NOT NULL,   -- trimmed, original spelling/casing kept
    company_key               text         NOT NULL,   -- lower-case alphanumerics only; matching aid for Milestone 3
    location                  text,                    -- HQ location as published (trimmed)
    location_city             text,                    -- location without the ', Non-U.S.' suffix
    location_non_us_label     boolean,                 -- source labelled the location 'Non-U.S.'
    location_country_conflict boolean      NOT NULL,   -- Non-U.S. label disagrees with country
    country                   text,
    industry                  text,
    stage                     text,                    -- 'Unknown' -> NULL
    total_laid_off            integer,
    percentage_laid_off       numeric(5,4),            -- share 0..1, rounded to 4 dp
    funds_raised              numeric(12,1),           -- as published by Layoffs.fyi (USD millions)
    layoff_date               date         NOT NULL,
    date_added                date,
    source                    text,
    same_day_reports          integer      NOT NULL,   -- rows for this company on this date (>1 = possible near duplicate, kept)
    CONSTRAINT chk_pct   CHECK (percentage_laid_off BETWEEN 0 AND 1),
    CONSTRAINT chk_total CHECK (total_laid_off > 0),
    CONSTRAINT chk_funds CHECK (funds_raised >= 0)
);

INSERT INTO clean.layoffs
SELECT row_id, company, company_key, location, location_city, location_non_us_label,
       coalesce((location_non_us_label) = (country = 'United States'), false),
       country, industry, stage, total_laid_off, percentage_laid_off, funds_raised,
       layoff_date, date_added, source,
       count(*) OVER (PARTITION BY lower(company), layoff_date)
FROM deduped
WHERE rn = 1;

CREATE TABLE clean.layoffs_rejected AS
SELECT r.*,                                   -- the raw record, untouched
       coalesce(j.critical_reason,
                'duplicate event (identical except source/date_added)') AS reject_reason,
       d.keep_row_id                                                    AS duplicate_of_row_id,
       now()                                                            AS rejected_at
FROM raw.layoffs r
JOIN judged j ON j.row_id = r.row_id
LEFT JOIN deduped d ON d.row_id = r.row_id
WHERE j.critical_reason IS NOT NULL OR d.rn > 1;

-- ---------------------------------------------------------------------------
-- Step 5: keys only after uniqueness is confirmed; reconciliation check
-- ---------------------------------------------------------------------------
DO $$
DECLARE n_raw bigint; n_clean bigint; n_rej bigint; n_dupkey bigint; n_overlap bigint;
BEGIN
    SELECT count(*) INTO n_raw   FROM raw.layoffs;
    SELECT count(*) INTO n_clean FROM clean.layoffs;
    SELECT count(*) INTO n_rej   FROM clean.layoffs_rejected;
    SELECT count(*) - count(DISTINCT row_id) INTO n_dupkey FROM clean.layoffs;
    SELECT count(*) INTO n_overlap FROM clean.layoffs c JOIN clean.layoffs_rejected x USING (row_id);
    IF n_dupkey <> 0 THEN RAISE EXCEPTION 'row_id not unique in clean.layoffs (% duplicates)', n_dupkey; END IF;
    IF n_overlap <> 0 THEN RAISE EXCEPTION '% rows are in both clean and rejected', n_overlap; END IF;
    IF n_raw <> n_clean + n_rej THEN
        RAISE EXCEPTION 'Reconciliation failed: raw % <> clean % + rejected %', n_raw, n_clean, n_rej;
    END IF;
    RAISE NOTICE 'Reconciled: raw % = clean % + rejected %', n_raw, n_clean, n_rej;
END $$;

ALTER TABLE clean.layoffs          ADD CONSTRAINT layoffs_pkey          PRIMARY KEY (row_id);
ALTER TABLE clean.layoffs_rejected ADD CONSTRAINT layoffs_rejected_pkey PRIMARY KEY (row_id);
CREATE INDEX layoffs_company_key_idx ON clean.layoffs (company_key);
CREATE INDEX layoffs_date_idx        ON clean.layoffs (layoff_date);

COMMIT;
