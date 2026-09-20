create table if not exists public.psychology_profiles (
  username text primary key check (username ~ '^[a-z0-9_]{2,32}$'),
  state jsonb not null default '{}'::jsonb,
  revision bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  state_text text not null default '{}'
);

alter table public.psychology_profiles enable row level security;

create or replace function public.psychology_profile_load(p_username text)
returns table(username text, state_text text, revision bigint)
language plpgsql
security invoker
set search_path = public
as $$
begin
  insert into public.psychology_profiles (username)
  values (p_username)
  on conflict (username) do nothing;

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
security invoker
set search_path = public
as $$
begin
  return query
  update public.psychology_profiles p
  set state_text = p_state_text,
      state = p_state_text::jsonb,
      revision = p.revision + 1,
      updated_at = now()
  where p.username = p_username
    and p.revision = p_expected_revision
  returning true, p.state_text, p.revision;

  if found then
    return;
  end if;

  if p_expected_revision = 0 then
    return query
    insert into public.psychology_profiles (username, state_text, state, revision)
    values (p_username, p_state_text, p_state_text::jsonb, 1)
    on conflict (username) do nothing
    returning true, psychology_profiles.state_text, psychology_profiles.revision;

    if found then
      return;
    end if;
  end if;

  return query
  select false, p.state_text, p.revision
  from public.psychology_profiles p
  where p.username = p_username;
end;
$$;
