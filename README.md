# Audit Test Tracker

A single-page audit testing app for financial documents, aligned to Singapore Standards on Auditing (SSA) and SFRS(I).

- Upload Excel (.xlsx, .xls) or CSV files. Each sheet is read, columns are detected and up to 17 audit tests run automatically (casting, trial balance, duplicates, round sums, weekend postings, cut-off, sequence gaps, ageing, NRV, related parties, Benford and more).
- Issue tracker with amount, risk level (High / Medium / Low), priority (P1–P4) and risk area, ranked by materiality and test type.
- Each issue shows the file, sheet, Excel row and cell, with a viewer that highlights the exact cell.
- Each issue links to SSA and SFRS(I) paragraphs, highlighted in a built-in standards library.
- Sign-in with username and password (Supabase Auth). Admins add users, set initial passwords, reset passwords, change roles and deactivate users from the **Users** page. New users must choose their own password at first sign-in.
- Data is stored in Supabase (Postgres) and shared by everyone signed in. Changes appear for teammates live.

> Paragraph summaries in the standards library are paraphrased for quick reference and are not the official text. Always refer to the full standards published by ISCA (SSAs) and ACRA / ASC (SFRS(I)).

## Files

| Path | Purpose |
| --- | --- |
| `index.html` | The whole app (HTML, CSS and JavaScript in one file) |
| `vercel.json` | Vercel settings: security headers and clean URLs |
| `supabase/01_schema.sql` | Tables, triggers and realtime |
| `supabase/02_users.sql` | User management (`audit_users` linked to `auth.users`), row level security and the starter users |
| `supabase/03_sample_data.sql` | The sample engagement (optional) |
| `samples/Sample_GL_testing_FY2026.xlsx` | Example workbook with planted issues for testing |

## Database (Supabase)

The app connects to the Supabase project set at the top of the script in `index.html`:

```js
const SUPABASE_URL = 'https://aisfafhifqdkqdnodiiu.supabase.co';
const SUPABASE_KEY = 'sb_publishable_...';
```

The publishable key is safe to ship in the page. All tables use row level security, so only signed-in, active users who have set their own password can read or change data.

To use a different Supabase project:

1. Open the project's **SQL Editor** and run `supabase/01_schema.sql`, then `02_users.sql`, then (optionally) `03_sample_data.sql`.
2. Replace `SUPABASE_URL` and `SUPABASE_KEY` in `index.html` with that project's URL and publishable key, then push.

### Users

Users sign in with a username. Behind the scenes each username maps to `<username>@audit-tracker.example` in Supabase's `auth.users` table, which stores the hashed password. The `audit_users` table holds the username, display name, role (admin or member), and status.

Starter users, all with the initial password `password`:

| Username | Role |
| --- | --- |
| priya | Admin |
| dan | Member |
| marcus | Member |

Each must choose a new password (at least 8 characters) at first sign-in before any data is shown.

To add the first admin to a fresh project from the SQL Editor:

```sql
select private.audit_create_user('yourname', 'initial-password', 'Your Name', 'admin', null);
```

## Deploy to Vercel

1. Go to [vercel.com/new](https://vercel.com/new) and import this GitHub repository.
2. Framework preset: **Other**. Leave Build Command and Output Directory empty, and Root Directory as `./`.
3. Click **Deploy**. Every push to `main` redeploys automatically.

No build step or dependencies are needed. The page loads SheetJS from cdnjs, supabase-js from jsDelivr and fonts from Google Fonts at runtime.

## Run locally

Serve the folder (sign-in needs http, not a file:// page):

```bash
npx serve .
```

## Try it

1. Sign in as `priya` / `password` and choose a new password.
2. The sample engagement opens with 37 ranked issues. Click **Upload Excel** and choose `samples/Sample_GL_testing_FY2026.xlsx` to start a new engagement from a file.
3. Under **Engagement**, set period end to 30 Jun 2026 and materiality to 250,000.
4. Under **Users**, add teammates and give them an initial password.
