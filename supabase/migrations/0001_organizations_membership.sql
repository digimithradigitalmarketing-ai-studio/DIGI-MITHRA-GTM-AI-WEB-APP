-- DigiMithra AI Gym: tenant foundation (Phase 2)
-- Lives in its own schema so it does not touch other products in the same Supabase project.

create schema if not exists digimithra;
revoke all on schema digimithra from public;
grant usage on schema digimithra to authenticated, service_role;

create table digimithra.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 80),
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now()
);

create table digimithra.organization_members (
  organization_id uuid not null references digimithra.organizations (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null check (role in ('owner', 'admin', 'sales_operator', 'viewer')),
  created_at timestamptz not null default now(),
  primary key (organization_id, user_id)
);

create index organization_members_user_idx on digimithra.organization_members (user_id);

alter table digimithra.organizations enable row level security;
alter table digimithra.organization_members enable row level security;

-- True when the signed-in user belongs to the organization, optionally with one of the given roles.
create or replace function digimithra.is_member(p_org uuid, p_roles text[] default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from digimithra.organization_members m
    where m.organization_id = p_org
      and m.user_id = (select auth.uid())
      and (p_roles is null or m.role = any (p_roles))
  );
$$;

revoke execute on function digimithra.is_member(uuid, text[]) from public, anon;
grant execute on function digimithra.is_member(uuid, text[]) to authenticated;

-- Organizations: members can read; owners and admins can rename. Creation goes through create_organization().
create policy organizations_select on digimithra.organizations
  for select to authenticated
  using (digimithra.is_member(id));

create policy organizations_update on digimithra.organizations
  for update to authenticated
  using (digimithra.is_member(id, array['owner', 'admin']))
  with check (digimithra.is_member(id, array['owner', 'admin']));

-- Memberships: members see their own organization's roster; only owners and admins change it.
-- Only an owner can create, change or remove an owner row.
create policy members_select on digimithra.organization_members
  for select to authenticated
  using (user_id = (select auth.uid()) or digimithra.is_member(organization_id));

create policy members_insert on digimithra.organization_members
  for insert to authenticated
  with check (
    digimithra.is_member(organization_id, array['owner', 'admin'])
    and (role <> 'owner' or digimithra.is_member(organization_id, array['owner']))
  );

create policy members_update on digimithra.organization_members
  for update to authenticated
  using (
    digimithra.is_member(organization_id, array['owner', 'admin'])
    and (role <> 'owner' or digimithra.is_member(organization_id, array['owner']))
  )
  with check (
    digimithra.is_member(organization_id, array['owner', 'admin'])
    and (role <> 'owner' or digimithra.is_member(organization_id, array['owner']))
  );

create policy members_delete on digimithra.organization_members
  for delete to authenticated
  using (
    digimithra.is_member(organization_id, array['owner', 'admin'])
    and (role <> 'owner' or digimithra.is_member(organization_id, array['owner']))
  );

grant select, update on digimithra.organizations to authenticated;
grant select, insert, update, delete on digimithra.organization_members to authenticated;
grant select, insert, update, delete on digimithra.organizations, digimithra.organization_members to service_role;

-- Creates an organization and its owner membership in one step, so no org is ever left without an owner.
create or replace function digimithra.create_organization(p_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_org uuid;
begin
  if v_user is null then
    raise exception 'sign in required' using errcode = '42501';
  end if;
  if p_name is null or char_length(trim(p_name)) not between 2 and 80 then
    raise exception 'organization name must be 2 to 80 characters' using errcode = '22023';
  end if;

  insert into digimithra.organizations (name, created_by)
  values (trim(p_name), v_user)
  returning id into v_org;

  insert into digimithra.organization_members (organization_id, user_id, role)
  values (v_org, v_user, 'owner');

  return v_org;
end;
$$;

revoke execute on function digimithra.create_organization(text) from public, anon;
grant execute on function digimithra.create_organization(text) to authenticated;
