-- Audit Test Tracker: tables, row level security and realtime.
create schema if not exists private;
grant usage on schema private to authenticated;

create or replace function private.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end; $$;

create or replace function private.touch_issue()
returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at = now(); new.updated_by = coalesce(auth.uid(), new.updated_by); return new; end; $$;

create table public.engagements (
  id uuid primary key default gen_random_uuid(),
  entity text not null default '',
  period_end date,
  currency text not null default 'SGD',
  materiality numeric(18,2) not null default 0 check (materiality >= 0),
  pm_pct numeric(6,2) not null default 75 check (pm_pct > 0 and pm_pct <= 100),
  trivial_pct numeric(6,2) not null default 5 check (trivial_pct >= 0 and trivial_pct <= 50),
  disabled_tests text[] not null default '{}',
  issue_seq integer not null default 1,
  is_sample boolean not null default false,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.audit_files (
  id uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references public.engagements(id) on delete cascade,
  name text not null,
  uploaded_by uuid default auth.uid(),
  uploaded_at timestamptz not null default now()
);
create index audit_files_engagement_idx on public.audit_files(engagement_id);

create table public.audit_sheets (
  id uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references public.engagements(id) on delete cascade,
  file_id uuid not null references public.audit_files(id) on delete cascade,
  position integer not null default 0,
  name text not null,
  sheet_type text not null default 'gl' check (sheet_type in ('gl','tb','rev','ar','ap','inv','ppe','bank','other')),
  header_row integer not null default 0,
  origin_r integer not null default 0,
  origin_c integer not null default 0,
  col_map jsonb not null default '{}',
  rows jsonb not null default '[]',
  tested_at timestamptz
);
create index audit_sheets_engagement_idx on public.audit_sheets(engagement_id);
create index audit_sheets_file_idx on public.audit_sheets(file_id);

create table public.audit_issues (
  id uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references public.engagements(id) on delete cascade,
  file_id uuid references public.audit_files(id) on delete cascade,
  sheet_id uuid references public.audit_sheets(id) on delete cascade,
  code text not null,
  dedup_key text not null,
  test text not null,
  title text not null,
  detail text not null default '',
  category text not null default 'Other',
  assertion text not null default '',
  risk text not null default 'Medium' check (risk in ('High','Medium','Low')),
  priority text not null default 'P3' check (priority in ('P1','P2','P3','P4')),
  score integer not null default 0,
  amount numeric(18,2) not null default 0,
  is_population boolean not null default false,
  row_idx integer[] not null default '{}',
  cells jsonb not null default '[]',
  ssa_refs jsonb not null default '[]',
  sfrs_refs jsonb not null default '[]',
  status text not null default 'Open' check (status in ('Open','In review','Unadjusted','Adjusted','Cleared')),
  notes text not null default '',
  mis_type text not null default '' check (mis_type in ('','Factual','Judgemental','Projected')),
  proposed_adj numeric(18,2),
  boost integer not null default 0,
  is_auto boolean not null default true,
  touched boolean not null default false,
  risk_override boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  unique (engagement_id, code),
  unique (engagement_id, dedup_key)
);
create index audit_issues_file_idx on public.audit_issues(file_id);
create index audit_issues_sheet_idx on public.audit_issues(sheet_id);

create trigger engagements_touch before update on public.engagements for each row execute function private.touch_updated_at();
create trigger audit_issues_touch before update on public.audit_issues for each row execute function private.touch_issue();

-- Reserve a block of issue numbers atomically (caller's rights, so RLS applies)
create or replace function public.audit_reserve_issue_codes(p_engagement uuid, p_count integer)
returns integer language sql security invoker set search_path = '' as $$
  update public.engagements set issue_seq = issue_seq + greatest(p_count, 0)
  where id = p_engagement returning issue_seq - greatest(p_count, 0);
$$;
revoke all on function public.audit_reserve_issue_codes(uuid, integer) from public, anon;
grant execute on function public.audit_reserve_issue_codes(uuid, integer) to authenticated;

alter publication supabase_realtime add table public.engagements, public.audit_files, public.audit_issues;
