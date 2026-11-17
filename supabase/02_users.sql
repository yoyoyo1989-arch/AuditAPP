-- Audit Test Tracker: user management on top of Supabase Auth (auth.users).
-- Users sign in with a username; it maps to <username>@audit-tracker.example in auth.users.

create table public.audit_users (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (username ~ '^[a-z0-9_.-]{2,32}$'),
  display_name text not null default '',
  role text not null default 'member' check (role in ('admin','member')),
  active boolean not null default true,
  must_change_password boolean not null default true,
  created_by uuid,
  created_at timestamptz not null default now(),
  password_changed_at timestamptz
);
comment on table public.audit_users is 'Audit Test Tracker users. Passwords live in auth.users.';
alter table public.audit_users enable row level security;
revoke all on public.audit_users from anon;
revoke insert, update, delete on public.audit_users from authenticated;

-- Membership: active user who has replaced the initial password
create or replace function private.is_audit_member()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.audit_users u
    where u.id = auth.uid() and u.active and not u.must_change_password);
$$;
create or replace function private.is_audit_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.audit_users u
    where u.id = auth.uid() and u.active and u.role = 'admin');
$$;
revoke all on function private.is_audit_admin() from public, anon;
grant execute on function private.is_audit_admin() to authenticated;

create policy "Users see themselves; members see the team" on public.audit_users
  for select to authenticated
  using (id = (select auth.uid()) or (select private.is_audit_member()));

-- Internal: create an auth user + audit profile
create or replace function private.audit_create_user(p_username text, p_password text, p_display_name text, p_role text, p_created_by uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid := gen_random_uuid();
  v_user text := lower(trim(p_username));
  v_email text := lower(trim(p_username)) || '@audit-tracker.example';
begin
  if v_user !~ '^[a-z0-9_.-]{2,32}$' then raise exception 'Username must be 2 to 32 characters: lowercase letters, numbers, dot, dash or underscore.'; end if;
  if p_role not in ('admin','member') then raise exception 'Role must be admin or member.'; end if;
  if length(coalesce(p_password,'')) < 6 then raise exception 'Initial password must be at least 6 characters.'; end if;
  if exists (select 1 from public.audit_users where username = v_user) or exists (select 1 from auth.users where email = v_email) then
    raise exception 'Username "%" is already taken.', v_user;
  end if;

  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change)
  values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
    extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"],"app":"audit-tracker"}'::jsonb,
    jsonb_build_object('username', v_user, 'display_name', coalesce(nullif(trim(p_display_name),''), v_user)),
    now(), now(), '', '', '', '');

  insert into auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), v_id, jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true),
    'email', v_id::text, now(), now(), now());

  insert into public.audit_users (id, username, display_name, role, must_change_password, created_by)
  values (v_id, v_user, coalesce(nullif(trim(p_display_name),''), initcap(v_user)), p_role, true, p_created_by);
  return v_id;
end; $$;
revoke all on function private.audit_create_user(text,text,text,text,uuid) from public, anon, authenticated;

-- Admin: add a user with an initial password (they must change it at first sign-in)
create or replace function public.audit_admin_create_user(p_username text, p_password text, p_display_name text default null, p_role text default 'member')
returns uuid language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_audit_admin() then raise exception 'Only admins can add users.'; end if;
  return private.audit_create_user(p_username, p_password, p_display_name, p_role, auth.uid());
end; $$;

-- Admin: set a new initial password for a user
create or replace function public.audit_admin_reset_password(p_user_id uuid, p_password text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_audit_admin() then raise exception 'Only admins can reset passwords.'; end if;
  if not exists (select 1 from public.audit_users where id = p_user_id) then raise exception 'User not found.'; end if;
  if length(coalesce(p_password,'')) < 6 then raise exception 'Initial password must be at least 6 characters.'; end if;
  update auth.users set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')), updated_at = now() where id = p_user_id;
  update public.audit_users set must_change_password = (p_user_id <> auth.uid()) where id = p_user_id;
end; $$;

-- Admin: change name, role or active status
create or replace function public.audit_admin_update_user(p_user_id uuid, p_display_name text, p_role text, p_active boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_audit_admin() then raise exception 'Only admins can change users.'; end if;
  if p_role not in ('admin','member') then raise exception 'Role must be admin or member.'; end if;
  if p_user_id = auth.uid() and (p_role <> 'admin' or not p_active) then raise exception 'You cannot remove your own admin access.'; end if;
  update public.audit_users set display_name = coalesce(nullif(trim(p_display_name),''), display_name), role = p_role, active = p_active where id = p_user_id;
  if not found then raise exception 'User not found.'; end if;
  update auth.users set banned_until = case when p_active then null else 'infinity'::timestamptz end where id = p_user_id;
end; $$;

-- Admin: delete a user completely
create or replace function public.audit_admin_delete_user(p_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_audit_admin() then raise exception 'Only admins can delete users.'; end if;
  if p_user_id = auth.uid() then raise exception 'You cannot delete your own account.'; end if;
  if not exists (select 1 from public.audit_users where id = p_user_id) then raise exception 'User not found.'; end if;
  delete from auth.users where id = p_user_id;
end; $$;

-- Any user: change own password (checks the current one)
create or replace function public.audit_change_password(p_current text, p_new text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_hash text;
begin
  select encrypted_password into v_hash from auth.users where id = auth.uid();
  if v_hash is null or not exists (select 1 from public.audit_users where id = auth.uid() and active) then raise exception 'Not signed in.'; end if;
  if extensions.crypt(coalesce(p_current,''), v_hash) <> v_hash then raise exception 'Current password is incorrect.'; end if;
  if length(coalesce(p_new,'')) < 8 then raise exception 'New password must be at least 8 characters.'; end if;
  if p_new = p_current then raise exception 'New password must be different from the current one.'; end if;
  if lower(p_new) in ('password','password1','12345678','123456789','qwerty123') then raise exception 'Choose a less common password.'; end if;
  update auth.users set encrypted_password = extensions.crypt(p_new, extensions.gen_salt('bf')), updated_at = now() where id = auth.uid();
  update public.audit_users set must_change_password = false, password_changed_at = now() where id = auth.uid();
end; $$;

revoke all on function public.audit_admin_create_user(text,text,text,text), public.audit_admin_reset_password(uuid,text),
  public.audit_admin_update_user(uuid,text,text,boolean), public.audit_admin_delete_user(uuid), public.audit_change_password(text,text) from public, anon;
grant execute on function public.audit_admin_create_user(text,text,text,text), public.audit_admin_reset_password(uuid,text),
  public.audit_admin_update_user(uuid,text,text,boolean), public.audit_admin_delete_user(uuid), public.audit_change_password(text,text) to authenticated;


-- Starter users (initial password "password", must be changed at first sign-in)
select private.audit_create_user('priya',  'password', 'Priya',  'admin',  null);
select private.audit_create_user('dan',    'password', 'Dan',    'member', null);
select private.audit_create_user('marcus', 'password', 'Marcus', 'member', null);

-- Row level security on audit data: active members who have set their own password
alter table public.engagements  enable row level security;
alter table public.audit_files  enable row level security;
alter table public.audit_sheets enable row level security;
alter table public.audit_issues enable row level security;
revoke all on public.engagements, public.audit_files, public.audit_sheets, public.audit_issues from anon;

create policy "Members read engagements" on public.engagements for select to authenticated using ((select private.is_audit_member()));
create policy "Members add engagements" on public.engagements for insert to authenticated with check ((select private.is_audit_member()));
create policy "Members edit engagements" on public.engagements for update to authenticated using ((select private.is_audit_member())) with check ((select private.is_audit_member()));
create policy "Admins delete engagements" on public.engagements for delete to authenticated using ((select private.is_audit_member()) and (select private.is_audit_admin()));
create policy "Members manage files" on public.audit_files for all to authenticated using ((select private.is_audit_member())) with check ((select private.is_audit_member()));
create policy "Members manage sheets" on public.audit_sheets for all to authenticated using ((select private.is_audit_member())) with check ((select private.is_audit_member()));
create policy "Members manage issues" on public.audit_issues for all to authenticated using ((select private.is_audit_member())) with check ((select private.is_audit_member()));
