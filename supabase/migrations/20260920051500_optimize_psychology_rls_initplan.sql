
drop policy if exists psychology_profiles_select_own_username on public.psychology_profiles;
drop policy if exists psychology_profiles_insert_own_username on public.psychology_profiles;
drop policy if exists psychology_profiles_update_own_username on public.psychology_profiles;

create policy psychology_profiles_select_own_username
on public.psychology_profiles
for select
to anon, authenticated
using (username = (select current_setting('app.psychology_profile_username', true)));

create policy psychology_profiles_insert_own_username
on public.psychology_profiles
for insert
to anon, authenticated
with check (username = (select current_setting('app.psychology_profile_username', true)));

create policy psychology_profiles_update_own_username
on public.psychology_profiles
for update
to anon, authenticated
using (username = (select current_setting('app.psychology_profile_username', true)))
with check (username = (select current_setting('app.psychology_profile_username', true)));
