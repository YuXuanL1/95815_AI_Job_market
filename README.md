# AI Job Market — 95-815 Data Engineering Project (Team 2)

**Problem statement:** we help AI job seekers understand which skills, pay levels and employers define today's AI job market, including how layoff activity relates to current AI hiring.

| Dataset | Source | Storage |
|---|---|---|
| AI Jobs Market 2025-2026 \| Salaries | Kaggle (alitaqishah), CSV | PostgreSQL |
| Layoffs Dataset | Kaggle (swaptr), from Layoffs.fyi, CSV | PostgreSQL |
| Adzuna job postings | Adzuna API, JSON | MongoDB |

This repository currently contains the **Layoffs** pipeline (raw → clean).

## Repository layout

```
sql/01_raw.sql                  create raw/clean schemas, load layoffs.csv into raw.layoffs (all TEXT)
sql/02_profile.sql              data-quality profile of raw.layoffs (read-only)
sql/03_clean.sql                build clean.layoffs + clean.layoffs_rejected (one transaction)
sql/04_verify_and_examples.sql  final counts + before/after examples
quality_log.md                  every quality issue and how it was handled
query_outputs.txt               output of 04_verify_and_examples.sql
pdf_section.md                  Milestone 2 report section (Layoffs)
video_notes.md                  Milestone 2 video notes
```

## Get the data

The raw CSV is **not** in this repository (see `.gitignore`). Download `layoffs.csv` from
https://www.kaggle.com/datasets/swaptr/layoffs-2022 and put it in the repository root.
The pipeline expects 4,675 data rows; `01_raw.sql` stops with an error if the count differs.
A newer download will have a different row count, so update the check in `01_raw.sql` if you use one.

## Run

Requires Docker. Choose a password in your own shell, so it is never stored in a file:

```bash
export PGPASSWORD='choose-a-password'
docker run -d --name de-postgres -e POSTGRES_PASSWORD="$PGPASSWORD" -e POSTGRES_DB=ai_jobs \
  -p 127.0.0.1:5432:5432 -v de_pgdata:/var/lib/postgresql/data -v "$PWD":/project:ro postgres:16
```

Run the scripts in order (each can be rerun):

```bash
for f in 01_raw 02_profile 03_clean 04_verify_and_examples; do
  docker exec -i de-postgres psql -U postgres -d ai_jobs -f /project/sql/$f.sql
done
```

Expected result: raw 4,675 = clean 4,673 + rejected 2.

## Secrets

Never commit passwords or API keys. Keep them in environment variables or a local `.env` file; `.env` is git-ignored.
