-- 01_raw.sql : RAW layer for the Layoffs dataset (Kaggle swaptr / Layoffs.fyi)
-- Rerunnable. Rebuilds raw.layoffs from the source CSV.
-- Rules: every source column stored as TEXT, no keys / checks / NOT NULL on source columns,
-- no cleaning. Only two technical columns are added:
--   row_id      : surrogate id assigned in file order (row_id = CSV line number - 1)
--   ingested_at : load timestamp
-- Load: server-side COPY from /project/layoffs.csv (the project folder is mounted read-only
-- into the container, so the original file cannot be modified).
-- Note: COPY ... CSV stores an unquoted empty cell as NULL. That is the only conversion.

\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS clean;

DROP TABLE IF EXISTS raw.layoffs CASCADE;

CREATE TABLE raw.layoffs (
    row_id              bigint GENERATED ALWAYS AS IDENTITY,
    company             text,
    location            text,
    total_laid_off      text,
    date                text,
    percentage_laid_off text,
    industry            text,
    source              text,
    stage               text,
    funds_raised        text,
    country             text,
    date_added          text,
    ingested_at         timestamptz DEFAULT now()
);

COPY raw.layoffs (company, location, total_laid_off, date, percentage_laid_off,
                  industry, source, stage, funds_raised, country, date_added)
FROM '/project/layoffs.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

-- Row-count check against the CSV (4,675 data rows counted with Python's csv reader).
-- Fails loudly (critical issue) if the load is incomplete.
DO $$
DECLARE n bigint;
BEGIN
    SELECT count(*) INTO n FROM raw.layoffs;
    IF n <> 4675 THEN
        RAISE EXCEPTION 'raw.layoffs row count % does not match CSV row count 4675', n;
    END IF;
    RAISE NOTICE 'raw.layoffs loaded: % rows (matches CSV)', n;
END $$;

SELECT count(*) AS raw_rows, min(row_id) AS min_row_id, max(row_id) AS max_row_id,
       min(ingested_at) AS ingested_at
FROM raw.layoffs;
