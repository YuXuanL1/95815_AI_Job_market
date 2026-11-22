-- 02_profile.sql : data-quality profile of raw.layoffs (read-only, rerunnable)
-- Every number in quality_log.md comes from one of these queries.
-- Run: docker exec -i de-postgres psql -U postgres -d ai_jobs -f /project/sql/02_profile.sql

\set ON_ERROR_STOP on
\pset pager off

\echo '== P1. Row count'
SELECT count(*) AS raw_rows FROM raw.layoffs;

\echo '== P2. Missing / blank / placeholder / untrimmed values per column'
SELECT c AS column_name,
       count(*) FILTER (WHERE v IS NULL)                                   AS null_or_empty,
       count(*) FILTER (WHERE v IS NOT NULL AND btrim(v) = '')             AS whitespace_only,
       count(*) FILTER (WHERE lower(btrim(v)) IN
             ('nan','null','none','n/a','na','unknown','-','?'))           AS placeholder,
       count(*) FILTER (WHERE v <> btrim(v))                               AS untrimmed,
       count(DISTINCT v)                                                   AS distinct_values
FROM raw.layoffs,
LATERAL (VALUES ('company',company),('location',location),('total_laid_off',total_laid_off),
                ('date',date),('percentage_laid_off',percentage_laid_off),('industry',industry),
                ('source',source),('stage',stage),('funds_raised',funds_raised),
                ('country',country),('date_added',date_added)) t(c, v)
GROUP BY c ORDER BY c;

\echo '== P3. Placeholder values found'
SELECT c AS column_name, v AS value, count(*)
FROM raw.layoffs,
LATERAL (VALUES ('industry',industry),('stage',stage),('country',country),('location',location)) t(c, v)
WHERE lower(btrim(v)) IN ('nan','null','none','n/a','na','unknown','-','?','other','non-u.s.')
GROUP BY 1, 2 ORDER BY 1, 2;

\echo '== P4. Date string patterns (9 = digit)'
SELECT 'date' AS column_name, regexp_replace(date, '\d', '9', 'g') AS pattern, count(*) FROM raw.layoffs GROUP BY 2
UNION ALL
SELECT 'date_added', regexp_replace(date_added, '\d', '9', 'g'), count(*) FROM raw.layoffs GROUP BY 2
ORDER BY 1, 3 DESC;

\echo '== P5. Date parse check (MM/DD/YYYY, strict round-trip) and ranges'
WITH d AS (
    SELECT date, date_added,
           to_date(date, 'MM/DD/YYYY') AS d_date, to_date(date_added, 'MM/DD/YYYY') AS d_added
    FROM raw.layoffs)
SELECT min(d_date) AS min_date, max(d_date) AS max_date,
       min(d_added) AS min_date_added, max(d_added) AS max_date_added,
       count(*) FILTER (WHERE to_char(d_date,  'FMMM/FMDD/YYYY') <> date)       AS unparseable_date,
       count(*) FILTER (WHERE to_char(d_added, 'FMMM/FMDD/YYYY') <> date_added) AS unparseable_date_added,
       count(*) FILTER (WHERE d_added < d_date)                                  AS date_added_before_date,
       count(*) FILTER (WHERE d_date > current_date)                             AS future_date
FROM d;

\echo '== P6. Rows per year of layoff date'
SELECT extract(year FROM to_date(date, 'MM/DD/YYYY'))::int AS year, count(*)
FROM raw.layoffs GROUP BY 1 ORDER BY 1;

\echo '== P7. Numeric string patterns (9 = run of digits)'
SELECT 'total_laid_off' AS column_name, regexp_replace(total_laid_off, '\d+', '9', 'g') AS pattern, count(*) FROM raw.layoffs GROUP BY 2
UNION ALL SELECT 'percentage_laid_off', regexp_replace(percentage_laid_off, '\d+', '9', 'g'), count(*) FROM raw.layoffs GROUP BY 2
UNION ALL SELECT 'funds_raised', regexp_replace(funds_raised, '\d+', '9', 'g'), count(*) FROM raw.layoffs GROUP BY 2
ORDER BY 1, 3 DESC;

\echo '== P8. total_laid_off range'
SELECT min(total_laid_off::numeric) AS min, max(total_laid_off::numeric) AS max,
       percentile_cont(0.5)  WITHIN GROUP (ORDER BY total_laid_off::numeric) AS median,
       percentile_cont(0.99) WITHIN GROUP (ORDER BY total_laid_off::numeric) AS p99,
       count(*) FILTER (WHERE total_laid_off::numeric <> trunc(total_laid_off::numeric)) AS non_integer,
       count(*) FILTER (WHERE total_laid_off::numeric <= 0) AS non_positive,
       count(*) FILTER (WHERE total_laid_off::numeric >= 10000) AS ge_10000
FROM raw.layoffs;

\echo '== P9. Largest total_laid_off values (plausibility check)'
SELECT row_id, company, total_laid_off, percentage_laid_off, date
FROM raw.layoffs ORDER BY total_laid_off::numeric DESC NULLS LAST LIMIT 8;

\echo '== P10. percentage_laid_off range and float artifacts'
SELECT min(percentage_laid_off::numeric) AS min, max(percentage_laid_off::numeric) AS max,
       count(*) FILTER (WHERE percentage_laid_off LIKE '%\%%') AS has_percent_sign,
       count(*) FILTER (WHERE percentage_laid_off::numeric > 1) AS gt_1,
       count(*) FILTER (WHERE percentage_laid_off::numeric = 0) AS zero,
       count(*) FILTER (WHERE percentage_laid_off::numeric = 1) AS full_shutdown,
       count(*) FILTER (WHERE length(split_part(percentage_laid_off, '.', 2)) > 4) AS float_artifacts
FROM raw.layoffs;

\echo '== P11. Rows with neither a count nor a percentage'
SELECT count(*) AS no_count_no_pct FROM raw.layoffs
WHERE total_laid_off IS NULL AND percentage_laid_off IS NULL;

\echo '== P12. funds_raised range'
SELECT min(funds_raised::numeric) AS min, max(funds_raised::numeric) AS max,
       count(*) FILTER (WHERE funds_raised LIKE '%.%') AS with_decimals
FROM raw.layoffs;

\echo '== P13. stage values'
SELECT coalesce(stage, '<NULL>') AS stage, count(*) FROM raw.layoffs GROUP BY 1 ORDER BY 2 DESC;

\echo '== P14. industry values'
SELECT coalesce(industry, '<NULL>') AS industry, count(*) FROM raw.layoffs GROUP BY 1 ORDER BY 2 DESC;

\echo '== P15. country values that look like synonyms'
SELECT country, count(*) FROM raw.layoffs
WHERE country IN ('UAE', 'United Arab Emirates') OR country IS NULL GROUP BY 1;

\echo '== P16. location formats (X = text between commas)'
SELECT regexp_replace(coalesce(location, ''), '[^,]+', 'X', 'g') AS pattern, count(*)
FROM raw.layoffs GROUP BY 1 ORDER BY 2 DESC;

\echo '== P17. location vs country inconsistencies (Non-U.S. suffix disagrees with country)'
SELECT location, country, count(*) FROM raw.layoffs
WHERE (location LIKE '%Non-U.S.%') = (country = 'United States')
GROUP BY 1, 2 ORDER BY 3 DESC, 1;

\echo '== P18. Exact duplicates (all 11 source columns identical)'
SELECT count(*) AS dup_groups, coalesce(sum(n - 1), 0) AS extra_rows FROM (
    SELECT count(*) AS n FROM raw.layoffs
    GROUP BY company, location, total_laid_off, date, percentage_laid_off, industry,
             source, stage, funds_raised, country, date_added
    HAVING count(*) > 1) x;

\echo '== P19. Duplicates of the same event: identical except source and date_added (company trimmed/case-folded)'
SELECT array_agg(row_id ORDER BY row_id) AS row_ids, min(btrim(company)) AS company, min(date) AS date,
       count(*) AS n
FROM raw.layoffs
GROUP BY lower(btrim(company)), location, total_laid_off, date, percentage_laid_off,
         industry, stage, funds_raised, country
HAVING count(*) > 1;

\echo '== P20. Near duplicates: same company (trimmed, case-folded) and same layoff date'
SELECT count(*) AS groups, sum(n) AS rows_in_groups FROM (
    SELECT count(*) AS n FROM raw.layoffs GROUP BY lower(btrim(company)), date HAVING count(*) > 1) x;

\echo '== P21. Same company spelled differently (equal after lowercasing and removing non-alphanumerics)'
SELECT k AS match_key, array_agg(DISTINCT '[' || company || ']') AS raw_spellings
FROM (SELECT company, regexp_replace(lower(company), '[^a-z0-9]', '', 'g') AS k FROM raw.layoffs) x
GROUP BY k HAVING count(DISTINCT company) > 1 ORDER BY k;

\echo '== P22. Rows in the Question 3 window (2025-11-01 .. 2026-11-11)'
SELECT count(*) AS window_rows,
       count(DISTINCT lower(btrim(company))) AS window_companies,
       count(*) FILTER (WHERE total_laid_off IS NULL) AS window_no_count,
       count(*) FILTER (WHERE stage = 'Unknown' OR stage IS NULL) AS window_no_stage
FROM raw.layoffs
WHERE to_date(date, 'MM/DD/YYYY') BETWEEN DATE '2025-11-01' AND DATE '2026-11-11';
