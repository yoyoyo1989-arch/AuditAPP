# Audit Test Tracker

A single-page audit testing app for financial documents, aligned to Singapore Standards on Auditing (SSA) and SFRS(I).

- Upload Excel (.xlsx, .xls) or CSV files. Each sheet is read, columns are detected and up to 17 audit tests run automatically (casting, trial balance, duplicates, round sums, weekend postings, cut-off, sequence gaps, ageing, NRV, related parties, Benford and more).
- Issue tracker with amount, risk level (High / Medium / Low), priority (P1–P4) and risk area, ranked by materiality and test type.
- Each issue shows the file, sheet, Excel row and cell, with a viewer that highlights the exact cell.
- Each issue links to SSA and SFRS(I) paragraphs, highlighted in a built-in standards library.
- Data is saved in the browser's local storage only. Nothing is sent to a server.

> Paragraph summaries in the standards library are paraphrased for quick reference and are not the official text. Always refer to the full standards published by ISCA (SSAs) and ACRA / ASC (SFRS(I)).

## Files

| Path | Purpose |
| --- | --- |
| `index.html` | The whole app (HTML, CSS and JavaScript in one file) |
| `vercel.json` | Vercel settings: security headers and clean URLs |
| `samples/Sample_GL_testing_FY2026.xlsx` | Example workbook with planted issues for testing |

## Deploy to Vercel

1. Go to [vercel.com/new](https://vercel.com/new) and import this GitHub repository.
2. Framework preset: **Other**. Leave Build Command and Output Directory empty, and Root Directory as `./`.
3. Click **Deploy**. Every push to `main` redeploys automatically.

No build step or dependencies are needed. The page loads SheetJS from cdnjs and fonts from Google Fonts at runtime.

## Run locally

Open `index.html` in a browser, or serve the folder:

```bash
npx serve .
```

## Try it

1. Open the app and click **Upload Excel**, then choose `samples/Sample_GL_testing_FY2026.xlsx`.
2. Under **Engagement**, set period end to 30 Jun 2026 and materiality to 250,000.
3. Review the ranked issues under **Issues**.
