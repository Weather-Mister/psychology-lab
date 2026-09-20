drop policy if exists psychology_profiles_select_own_username on public.psychology_profiles;
drop policy if exists psychology_profiles_insert_own_username on public.psychology_profiles;
drop policy if exists psychology_profiles_update_own_username on public.psychology_profiles;

grant select, insert, update on table public.psychology_profiles to anon, authenticated;

create policy psychology_profiles_select_own_username
on public.psychology_profiles
for select
to anon, authenticated
using (username = current_setting('app.psychology_profile_username', true));

create policy psychology_profiles_insert_own_username
on public.psychology_profiles
for insert
to anon, authenticated
with check (username = current_setting('app.psychology_profile_username', true));

create policy psychology_profiles_update_own_username
on public.psychology_profiles
for update
to anon, authenticated
using (username = current_setting('app.psychology_profile_username', true))
with check (username = current_setting('app.psychology_profile_username', true));

create or replace function public.psychology_profile_load(p_username text)
returns table(username text, state_text text, revision bigint)
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_username text;
begin
  v_username := lower(trim(p_username));
  if v_username !~ '^[a-z0-9_]{2,32}$' then
    raise exception 'invalid_username';
  end if;

  perform set_config('app.psychology_profile_username', v_username, true);

  insert into public.psychology_profiles(username, state, state_text, revision)
  values (v_username, '{}'::jsonb, '{}', 0)
  on conflict on constraint psychology_profiles_pkey do nothing;

  return query
  select p.username, p.state_text, p.revision
  from public.psychology_profiles p
  where p.username = v_username;
end;
$$;

create or replace function public.psychology_profile_save(
  p_username text,
  p_state_text text,
  p_expected_revision bigint
)
returns table(ok boolean, state_text text, revision bigint)
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_username text;
  v_state jsonb;
  v_row public.psychology_profiles%rowtype;
begin
  v_username := lower(trim(p_username));

  if v_username !~ '^[a-z0-9_]{2,32}$' then
    raise exception 'invalid_username';
  end if;
  if p_expected_revision is null or p_expected_revision < 0 then
    raise exception 'invalid_revision';
  end if;
  if p_state_text is null or octet_length(p_state_text) > 1000000 then
    raise exception 'invalid_state';
  end if;

  v_state := p_state_text::jsonb;
  if jsonb_typeof(v_state) <> 'object' then
    raise exception 'invalid_state';
  end if;

  perform set_config('app.psychology_profile_username', v_username, true);

  select p.* into v_row
  from public.psychology_profiles p
  where p.username = v_username;

  if not found then
    insert into public.psychology_profiles(username, state, state_text, revision)
    values (v_username, '{}'::jsonb, '{}', 0)
    returning * into v_row;
  end if;

  if v_row.revision <> p_expected_revision then
    return query select false, v_row.state_text, v_row.revision;
    return;
  end if;

  if v_row.state = v_state then
    return query select true, v_row.state_text, v_row.revision;
    return;
  end if;

  update public.psychology_profiles p
     set state = v_state,
         state_text = p_state_text,
         revision = p.revision + 1,
         updated_at = now()
   where p.username = v_username
     and p.revision = p_expected_revision
  returning p.* into v_row;

  if found then
    return query select true, v_row.state_text, v_row.revision;
    return;
  end if;

  select p.* into v_row
  from public.psychology_profiles p
  where p.username = v_username;

  return query select false, v_row.state_text, v_row.revision;
end;
$$;

revoke execute on function public.psychology_profile_load(text) from public;
revoke execute on function public.psychology_profile_save(text, text, bigint) from public;
grant execute on function public.psychology_profile_load(text) to anon, authenticated;
grant execute on function public.psychology_profile_save(text, text, bigint) to anon, authenticated;
