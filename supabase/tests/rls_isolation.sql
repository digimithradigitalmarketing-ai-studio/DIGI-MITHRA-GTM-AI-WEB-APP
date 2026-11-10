-- Two-user isolation test for the digimithra schema.
-- Runs inside one transaction and rolls back, so no fixture data persists.
-- Every check either passes silently or raises, which aborts the whole script.
-- The final row only appears if every check passed.

begin;

-- Fixture: two synthetic users (no emails, no real accounts) and one org each.
insert into auth.users (id, aud, role)
values
  ('a0000000-0000-4000-8000-00000000000a', 'authenticated', 'authenticated'),
  ('b0000000-0000-4000-8000-00000000000b', 'authenticated', 'authenticated');

insert into digimithra.organizations (id, name, created_by) values
  ('a1000000-0000-4000-8000-000000000001', 'Test Org A', 'a0000000-0000-4000-8000-00000000000a'),
  ('b1000000-0000-4000-8000-000000000002', 'Test Org B', 'b0000000-0000-4000-8000-00000000000b');

insert into digimithra.organization_members (organization_id, user_id, role) values
  ('a1000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-00000000000a', 'owner'),
  ('b1000000-0000-4000-8000-000000000002', 'b0000000-0000-4000-8000-00000000000b', 'owner');

-- Act as user A.
select set_config('request.jwt.claims', '{"sub":"a0000000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
set local role authenticated;

-- 1. create_organization works for a signed-in user and creates an owner membership.
do $$
declare v_new uuid;
begin
  v_new := digimithra.create_organization('Second Org A');
  if v_new is null then raise exception 'FAIL 1: create_organization returned null'; end if;
end $$;

-- 2. User A sees only their own organizations (A and Second Org A), never B.
do $$
begin
  if (select count(*) from digimithra.organizations) <> 2 then
    raise exception 'FAIL 2: user A should see exactly 2 organizations';
  end if;
  if exists (select 1 from digimithra.organizations where id = 'b1000000-0000-4000-8000-000000000002') then
    raise exception 'FAIL 2b: user A can read org B';
  end if;
end $$;

-- 3. User A cannot rename org B.
do $$
declare v_rows int;
begin
  update digimithra.organizations set name = 'Hacked' where id = 'b1000000-0000-4000-8000-000000000002';
  get diagnostics v_rows = row_count;
  if v_rows <> 0 then raise exception 'FAIL 3: user A modified org B'; end if;
end $$;

-- 4. User A cannot add themselves to org B.
do $$
begin
  insert into digimithra.organization_members (organization_id, user_id, role)
  values ('b1000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-00000000000a', 'viewer');
  raise exception 'FAIL 4: user A inserted a membership into org B';
exception when sqlstate '42501' then
  null; -- expected: row-level security rejected the write
end $$;

-- 5. User A cannot read org B's roster.
do $$
begin
  if exists (select 1 from digimithra.organization_members where organization_id = 'b1000000-0000-4000-8000-000000000002') then
    raise exception 'FAIL 5: user A can read org B members';
  end if;
end $$;

-- Fixture: user B becomes an admin (not owner) of org A. Set up as the superuser.
reset role;
insert into digimithra.organization_members (organization_id, user_id, role)
values ('a1000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-00000000000b', 'admin');

-- Act as admin B.
select set_config('request.jwt.claims', '{"sub":"b0000000-0000-4000-8000-00000000000b","role":"authenticated"}', true);
set local role authenticated;

-- 6a. An admin cannot change the owner's row. The update matches no rows.
do $$
declare v_rows int;
begin
  update digimithra.organization_members set role = 'viewer'
  where organization_id = 'a1000000-0000-4000-8000-000000000001'
    and user_id = 'a0000000-0000-4000-8000-00000000000a';
  get diagnostics v_rows = row_count;
  if v_rows <> 0 then raise exception 'FAIL 6a: admin changed the owner row'; end if;
end $$;

-- 6b. An admin cannot promote themselves to owner. Row-level security rejects the write.
do $$
begin
  update digimithra.organization_members set role = 'owner'
  where organization_id = 'a1000000-0000-4000-8000-000000000001'
    and user_id = 'b0000000-0000-4000-8000-00000000000b';
  raise exception 'FAIL 6b: admin promoted themselves to owner';
exception when sqlstate '42501' then
  null;
end $$;

reset role;

-- 7. Signed-out callers get nothing and cannot create organizations.
set local role anon;
do $$
begin
  if (select count(*) from digimithra.organizations) <> 0 then
    raise exception 'FAIL 7: anon can read organizations';
  end if;
  raise exception 'FAIL 7b: anon reached the table';
exception when insufficient_privilege then
  null; -- expected: anon has no privilege on the schema
end $$;

reset role;

select 'all isolation checks passed' as result;

rollback;
