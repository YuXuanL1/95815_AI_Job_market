-- 04_verify_and_examples.sql : final counts + before/after examples (read-only, rerunnable)
-- Run: docker exec -i de-postgres psql -U postgres -d ai_jobs -f /project/sql/04_verify_and_examples.sql > query_outputs.txt

\set ON_ERROR_STOP on
\pset pager off
\pset border 2

\echo '================================================================'
\echo ' V1. FINAL COUNTS'
\echo '================================================================'
SELECT (SELECT count(*) FROM raw.layoffs)                                  AS raw_rows,
       (SELECT count(*) FROM clean.layoffs)                                AS clean_rows,
       (SELECT count(*) FROM clean.layoffs_rejected)                       AS rejected_rows,
       (SELECT count(*) FROM raw.layoffs)
         = (SELECT count(*) FROM clean.layoffs) + (SELECT count(*) FROM clean.layoffs_rejected) AS reconciles,
       (SELECT count(*) FROM clean.layoffs
         WHERE layoff_date BETWEEN DATE '2025-11-01' AND DATE '2026-11-11') AS clean_rows_q3_window,
       (SELECT count(DISTINCT company_key) FROM clean.layoffs
         WHERE layoff_date BETWEEN DATE '2025-11-01' AND DATE '2026-11-11') AS companies_q3_window;

\echo ' V2. Rejected rows and reasons'
SELECT row_id, company, date, total_laid_off, reject_reason, duplicate_of_row_id
FROM clean.layoffs_rejected ORDER BY row_id;

\echo ' V3. Missing values were NOT imputed: NULLs raw vs clean'
SELECT 'total_laid_off' AS col,
       (SELECT count(*) FROM raw.layoffs WHERE total_laid_off IS NULL) AS raw_nulls,
       (SELECT count(*) FROM clean.layoffs WHERE total_laid_off IS NULL) AS clean_nulls
UNION ALL SELECT 'percentage_laid_off',
       (SELECT count(*) FROM raw.layoffs WHERE percentage_laid_off IS NULL),
       (SELECT count(*) FROM clean.layoffs WHERE percentage_laid_off IS NULL)
UNION ALL SELECT 'funds_raised',
       (SELECT count(*) FROM raw.layoffs WHERE funds_raised IS NULL),
       (SELECT count(*) FROM clean.layoffs WHERE funds_raised IS NULL)
UNION ALL SELECT 'stage (raw NULL or ''Unknown'')',
       (SELECT count(*) FROM raw.layoffs WHERE stage IS NULL OR stage = 'Unknown'),
       (SELECT count(*) FROM clean.layoffs WHERE stage IS NULL)
UNION ALL SELECT 'industry',
       (SELECT count(*) FROM raw.layoffs WHERE industry IS NULL),
       (SELECT count(*) FROM clean.layoffs WHERE industry IS NULL)
UNION ALL SELECT 'country',
       (SELECT count(*) FROM raw.layoffs WHERE country IS NULL),
       (SELECT count(*) FROM clean.layoffs WHERE country IS NULL);

\echo '================================================================'
\echo ' BEFORE / AFTER EXAMPLES'
\echo '================================================================'

\echo ' E1. Data types: text dates and "1500.0" counts -> DATE / INTEGER / NUMERIC'
SELECT r.row_id, r.company,
       r.date AS raw_date, c.layoff_date, r.date_added AS raw_date_added, c.date_added,
       r.total_laid_off AS raw_total, c.total_laid_off,
       r.funds_raised AS raw_funds, c.funds_raised
FROM raw.layoffs r JOIN clean.layoffs c USING (row_id)
WHERE r.row_id IN (1, 2, 8);

\echo ' E2. percentage_laid_off float artifacts -> numeric(5,4)'
SELECT r.row_id, r.company, r.percentage_laid_off AS raw_pct, c.percentage_laid_off AS clean_pct
FROM raw.layoffs r JOIN clean.layoffs c USING (row_id)
WHERE length(split_part(r.percentage_laid_off, '.', 2)) > 4
ORDER BY r.row_id LIMIT 5;

\echo ' E3. stage ''Unknown'' -> NULL'
SELECT r.row_id, r.company, '[' || coalesce(r.stage, 'NULL') || ']' AS raw_stage,
       coalesce(c.stage, 'NULL') AS clean_stage
FROM raw.layoffs r JOIN clean.layoffs c USING (row_id)
WHERE r.row_id IN (SELECT min(row_id) FROM raw.layoffs WHERE stage = 'Unknown'
                   UNION ALL SELECT min(row_id) FROM raw.layoffs WHERE stage IS NULL
                   UNION ALL SELECT min(row_id) FROM raw.layoffs WHERE stage = 'Series B')
ORDER BY r.row_id;

\echo ' E4. Untrimmed company / source text -> trimmed (brackets show whitespace)'
SELECT r.row_id, '[' || r.company || ']' AS raw_company, '[' || c.company || ']' AS clean_company
FROM raw.layoffs r JOIN clean.layoffs c USING (row_id)
WHERE r.company <> btrim(r.company) ORDER BY r.row_id LIMIT 5;
SELECT r.row_id, '[' || r.source || ']' AS raw_source, '[' || c.source || ']' AS clean_source
FROM raw.layoffs r JOIN clean.layoffs c USING (row_id)
WHERE r.source <> btrim(r.source);

\echo ' E5. Country synonym UAE -> United Arab Emirates'
SELECT r.country AS raw_country, c.country AS clean_country, count(*)
FROM raw.layoffs r JOIN clean.layoffs c USING (row_id)
WHERE r.country IN ('UAE', 'United Arab Emirates') GROUP BY 1, 2;

\echo ' E6. Location: ", Non-U.S." suffix split into location_city + flag'
SELECT r.row_id, r.location AS raw_location, c.location_city, c.location_non_us_label, c.country
FROM raw.layoffs r JOIN clean.layoffs c USING (row_id)
WHERE r.row_id IN (1, 3) OR r.location = 'Non-U.S.'
ORDER BY r.row_id LIMIT 5;

\echo ' E7. Location vs country conflicts: kept, flagged (not corrected)'
SELECT row_id, company, location, country, location_country_conflict
FROM clean.layoffs WHERE location_country_conflict ORDER BY row_id LIMIT 8;
SELECT count(*) AS conflict_rows FROM clean.layoffs WHERE location_country_conflict;

\echo ' E8. Duplicate events: before (raw) and after (clean / rejected)'
SELECT row_id, company, date, total_laid_off, percentage_laid_off, date_added, left(source, 45) AS source
FROM raw.layoffs WHERE row_id IN (3197, 3198, 3808, 3809) ORDER BY row_id;
SELECT 'clean' AS lands_in, row_id FROM clean.layoffs WHERE row_id IN (3197, 3198, 3808, 3809)
UNION ALL
SELECT 'rejected', row_id FROM clean.layoffs_rejected WHERE row_id IN (3197, 3198, 3808, 3809)
ORDER BY row_id;

\echo ' E9. Near duplicates (same company + same date, different details): kept, flagged'
SELECT count(*) AS rows_flagged, count(DISTINCT (company_key, layoff_date)) AS groups
FROM clean.layoffs WHERE same_day_reports > 1;
SELECT row_id, company, location, total_laid_off, layoff_date, same_day_reports
FROM clean.layoffs WHERE company_key IN ('amazon', 'oracle') AND same_day_reports > 1
ORDER BY company_key, row_id;

\echo ' E10. Same company, different spellings: original kept, company_key aligns them'
SELECT company_key, array_agg(DISTINCT company) AS spellings, count(*) AS rows
FROM clean.layoffs
WHERE company_key IN ('hubspot', 'tiktok', 'uipath', 'characterai', 'mryum', 'skipthedishes', 'open')
GROUP BY company_key ORDER BY company_key;
