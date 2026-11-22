# Video Notes — Layoffs dataset segment (about 1 minute of the 5-minute video)

## Pages to show
- Kaggle dataset page: https://www.kaggle.com/datasets/swaptr/layoffs-2022 
- Original source: https://layoffs.fyi

## Narration script (about 45 seconds)
> Our third dataset is the Layoffs dataset from Kaggle. It is compiled from Layoffs.fyi, which tracks tech layoffs reported by outlets like Bloomberg and TechCrunch. It has 4,675 layoff events and 11 columns, from March 2020 to November 2026; 740 of those events, from 569 companies, happened in 2025 or 2026, the window for our layoff question. We loaded the CSV into PostgreSQL with every column stored as text in a raw schema, so no source record could be lost, and the load script checks that the row count matches the file. The worst quality issues are missing size data: about 35 percent of rows have no layoff count, and 782 rows use the placeholder "Unknown" for funding stage. On top of that, dates and numbers are stored as text, and 31 rows have locations that contradict their country. In the clean schema we parsed the types, turned "Unknown" into NULL without imputing anything, flagged the conflicts instead of guessing, and moved 2 duplicate events into a rejected table, so 4,673 clean rows plus 2 rejected rows add back up to exactly 4,675.

## What to show on screen (in order)
1. **Kaggle page:** the description and the license box.
2. **`layoffs.csv`:** open it and show the header plus the first rows (e.g. Qualcomm, Innoviz).
3. **`sql/01_raw.sql`:**
   - point out that every column is TEXT with no constraints;
   - show the `COPY` command;
   - show the row-count check and its output: "raw.layoffs loaded: 4675 rows (matches CSV)".
4. **`query_outputs.txt`:** screenshot these sections:
   - **V1:** final counts;
   - **E1:** text → date and integer;
   - **E2:** float artifacts;
   - **E3:** Unknown → NULL;
   - **E8:** duplicate removed;
   - **E7:** location–country conflicts flagged;
   - **E10:** company spellings.
5. **`quality_log.md`:** scroll through the table.
6. **Clean data in psql:** run `\d clean.layoffs` to show the types, primary key and CHECK constraints.

Command to regenerate the outputs:

```bash
docker exec -i de-postgres psql -U postgres -d ai_jobs -f /project/sql/04_verify_and_examples.sql > query_outputs.txt
```

## Key numbers (all from executed queries)

| Metric | Value |
|---|---|
| Raw rows / columns | 4,675 / 11 |
| Layoff date range | 2020-03-11 to 2026-11-11 |
| Clean rows / rejected rows | 4,673 / 2 (raw = clean + rejected ✔) |
| Q3 window (2025–2026, data ends 2026-11-11) | 740 rows, 569 companies |
| `total_laid_off` missing | 1,627 (34.8%) |
| `percentage_laid_off` missing | 1,758 (37.6%) |
| Neither count nor percentage | 763 |
| `stage` "Unknown" → NULL | 782 (+8 already blank) |
| Percentage float artifacts rounded | 38 |
| Location vs country conflicts (flagged) | 31 |
| Exact-duplicate events removed | 2 (Beyond Meat, Cazoo) |
| Same company + same date, kept and flagged | 19 groups / 40 clean rows |
| Company name spelling variants | 23 groups |


