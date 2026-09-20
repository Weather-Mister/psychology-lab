create or replace function public.psychology_profile_load(p_username text)
returns table(username text, state_text text, revision bigint)
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_username !~ '^[a-z0-9_]{2,32}$' then
    raise exception 'Invalid username';
  end if;

  insert into public.psychology_profiles (username)
  values (p_username)
  on conflict on constraint psychology_profiles_pkey do nothing;

  return query
  select p.username, p.state_text, p.revision
  from public.psychology_profiles p
  where p.username = p_username;
end;
$$;

create or replace function public.psychology_profile_save(
  p_username text,
  p_state_text text,
  p_expected_revision bigint
)
returns table(ok boolean, state_text text, revision bigint)
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_username !~ '^[a-z0-9_]{2,32}$' then
    raise exception 'Invalid username';
  end if;
  if p_expected_revision < 0 then
    raise exception 'Invalid revision';
  end if;
  if length(p_state_text) > 1000000 then
    raise exception 'Profile state is too large';
  end if;

  perform p_state_text::jsonb;

  return query
  update public.psychology_profiles p
  set state_text = p_state_text,
      state = p_state_text::jsonb,
      revision = p.revision + 1,
      updated_at = now()
  where p.username = p_username
    and p.revision = p_expected_revision
  returning true, p.state_text, p.revision;

  if found then return; end if;

  if p_expected_revision = 0 then
    return query
    insert into public.psychology_profiles (username, state_text, state, revision)
    values (p_username, p_state_text, p_state_text::jsonb, 1)
    on conflict on constraint psychology_profiles_pkey do nothing
    returning true, psychology_profiles.state_text, psychology_profiles.revision;

    if found then return; end if;
  end if;

  return query
  select false, p.state_text, p.revision
  from public.psychology_profiles p
  where p.username = p_username;
end;
$$;

revoke all on table public.psychology_profiles from anon, authenticated;
revoke execute on function public.psychology_profile_load(text) from public, authenticated;
revoke execute on function public.psychology_profile_save(text, text, bigint) from public, authenticated;
grant execute on function public.psychology_profile_load(text) to anon;
grant execute on function public.psychology_profile_save(text, text, bigint) to anon;
