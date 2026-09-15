-- ChoreSplit: accounts, groups, shared chores, anonymous ratings and proof videos.
--
-- Two rules shape everything below:
--   1. Nobody can see who rated what. Rating rows are readable only by the person who wrote
--      them; everyone else gets counts, and averages only once enough ratings are in.
--   2. Points are decided by the server. A client can finish a task, but only the functions
--      here can settle it and set what it paid.

-- ============================================================================================
-- Profiles
-- ============================================================================================

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(btrim(display_name)) between 1 and 40),
  emoji text not null default '🙂' check (char_length(emoji) between 1 and 8),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================================================
-- Groups and membership
-- ============================================================================================

-- Eight characters from an alphabet with no look-alikes (no 0/O, 1/I). The entropy comes from
-- gen_random_uuid(); the version and variant bytes of a v4 UUID are skipped because they
-- aren't random.
create or replace function public.new_invite_code() returns text
language plpgsql volatile
set search_path = public
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  bytes bytea := uuid_send(gen_random_uuid());
  positions constant int[] := array[0, 1, 2, 3, 4, 5, 7, 9];
  code text := '';
  pos int;
begin
  foreach pos in array positions loop
    code := code || substr(alphabet, (get_byte(bytes, pos) % 32) + 1, 1);
  end loop;
  return code;
end;
$$;

create or replace function public.normalize_invite_code(raw text) returns text
language sql immutable
as $$
  select upper(regexp_replace(coalesce(raw, ''), '[^A-Za-z0-9]', '', 'g'));
$$;

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 60),
  cycle_length_days int not null default 7 check (cycle_length_days in (3, 7, 14)),
  cycle_start_date timestamptz not null default date_trunc('day', now()),
  setup_stage text not null default 'choreBuilding' check (setup_stage in ('choreBuilding', 'running')),
  fairness_tolerance double precision not null default 0.10 check (fairness_tolerance between 0 and 1),
  minimum_ratings_to_reveal int not null default 2 check (minimum_ratings_to_reveal >= 1),
  rating_window_hours int not null default 48 check (rating_window_hours between 1 and 720),
  auto_assign_enabled boolean not null default true,
  invite_code text not null unique default public.new_invite_code(),
  -- Lets exactly one device at a time run the jobs that hand out chores.
  maintenance_claimed_at timestamptz,
  created_by uuid not null references auth.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.group_members (
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  share_weight double precision not null default 1.0 check (share_weight > 0 and share_weight <= 1),
  carry_over_points double precision not null default 0,
  palette_index int not null default 0,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index group_members_user_idx on public.group_members (user_id);

-- Security definer so policies on group_members can call it without recursing into themselves.
create or replace function public.is_group_member(target uuid) returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.group_members
    where group_id = target and user_id = auth.uid()
  );
$$;

create or replace function public.shares_group_with(other uuid) returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.group_members mine
    join public.group_members theirs on theirs.group_id = mine.group_id
    where mine.user_id = auth.uid() and theirs.user_id = other
  );
$$;

-- ============================================================================================
-- Chores and anonymous value votes
-- ============================================================================================

create table public.chores (
  -- Ids are generated on the phone, so a chore made offline keeps the same id once it syncs.
  id uuid primary key,
  group_id uuid not null references public.groups (id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 120),
  notes text not null default '' check (char_length(notes) <= 1000),
  category text not null default 'other'
    check (category in ('kitchen', 'bathroom', 'living', 'laundry', 'trash', 'outdoor', 'admin', 'other')),
  recurrence text not null default 'weekly'
    check (recurrence in ('once', 'daily', 'everyOtherDay', 'weekly', 'biweekly', 'monthly')),
  is_active boolean not null default true,
  proposer_id uuid references auth.users (id) on delete set null,
  proposed_difficulty int not null check (proposed_difficulty between 1 and 5),
  proposed_labor int not null check (proposed_labor between 1 and 5),
  proposed_minutes int not null check (proposed_minutes between 1 and 240),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index chores_group_idx on public.chores (group_id);

create table public.chore_value_votes (
  chore_id uuid not null references public.chores (id) on delete cascade,
  group_id uuid not null references public.groups (id) on delete cascade,
  rater_id uuid not null references auth.users (id) on delete cascade,
  difficulty int not null check (difficulty between 1 and 5),
  labor int not null check (labor between 1 and 5),
  minutes int not null check (minutes between 1 and 240),
  created_at timestamptz not null default now(),
  primary key (chore_id, rater_id)
);

-- ============================================================================================
-- Assignments (tasks) and anonymous quality ratings
-- ============================================================================================

create table public.assignments (
  id uuid primary key,
  group_id uuid not null references public.groups (id) on delete cascade,
  chore_id uuid references public.chores (id) on delete set null,
  assignee_id uuid references auth.users (id) on delete set null,
  assigned_at timestamptz not null default now(),
  due_date timestamptz not null,
  status text not null default 'open' check (status in ('open', 'awaitingReview', 'settled', 'skipped')),
  points_quoted int not null check (points_quoted between 1 and 4),
  awarded_points double precision,
  completed_at timestamptz,
  was_auto_assigned boolean not null default false,
  assignment_reason text not null default '' check (char_length(assignment_reason) <= 200),
  proof_video_path text,
  proof_video_duration double precision,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index assignments_group_idx on public.assignments (group_id);

create table public.quality_ratings (
  assignment_id uuid not null references public.assignments (id) on delete cascade,
  group_id uuid not null references public.groups (id) on delete cascade,
  rater_id uuid not null references auth.users (id) on delete cascade,
  score int not null check (score between 1 and 5),
  note text not null default '' check (char_length(note) <= 280),
  created_at timestamptz not null default now(),
  primary key (assignment_id, rater_id)
);

-- What a finished task pays. Mirrors PointsEngine.settledPoints in the app: three stars or more
-- pays the full points, below that it scales down to half, in half-point steps, never below 0.5.
-- Rounding goes through numeric so ties round away from zero, the same as Swift's .rounded().
create or replace function public.settled_points(quoted int, average_score double precision)
returns double precision
language sql immutable
as $$
  select case
    when average_score is null then quoted::double precision
    else greatest(
      0.5,
      round((quoted * (
        case
          when least(5, greatest(1, average_score)) >= 3 then 1.0
          else 0.5 + (least(5, greatest(1, average_score)) - 1) * 0.25
        end
      ) * 2)::numeric) / 2
    )::double precision
  end;
$$;

-- Clients may create and update tasks, but never decide points. Rather than rejecting a sync
-- that carries stale values, the guard quietly keeps the server's: a phone that settled a task
-- while offline is coerced back to "being rated" and the server settles it properly.
create or replace function public.assignments_guard() returns trigger
language plpgsql
set search_path = public
as $$
begin
  if coalesce(current_setting('choresplit.settling', true), 'off') = 'on' then
    new.updated_at := now();
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.awarded_points := null;
    if new.status = 'settled' then
      new.status := 'awaitingReview';
    end if;
    if new.status = 'awaitingReview' and new.assignee_id is distinct from auth.uid() then
      raise exception 'only the person doing a task can finish it' using errcode = '42501';
    end if;
  else
    new.awarded_points := old.awarded_points;
    new.points_quoted := old.points_quoted;
    new.group_id := old.group_id;

    if old.status = 'settled' then
      -- Final. Clearing the video afterwards is still allowed.
      new.status := 'settled';
      new.completed_at := old.completed_at;
    else
      if new.status = 'settled' then
        new.status := 'awaitingReview';
      end if;
      if new.status = 'awaitingReview' and old.status = 'open'
         and old.assignee_id is distinct from auth.uid() then
        raise exception 'only the person doing a task can finish it' using errcode = '42501';
      end if;
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create trigger assignments_guard
  before insert or update on public.assignments
  for each row execute function public.assignments_guard();

-- ============================================================================================
-- Row-level security
-- ============================================================================================

alter table public.profiles enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.chores enable row level security;
alter table public.chore_value_votes enable row level security;
alter table public.assignments enable row level security;
alter table public.quality_ratings enable row level security;

-- Signed-out visitors get nothing, anywhere.
revoke all on public.profiles, public.groups, public.group_members, public.chores,
  public.chore_value_votes, public.assignments, public.quality_ratings from anon;

create policy "profiles: read yourself and people you share a group with"
  on public.profiles for select to authenticated
  using (id = auth.uid() or public.shares_group_with(id));
create policy "profiles: create your own"
  on public.profiles for insert to authenticated
  with check (id = auth.uid());
create policy "profiles: edit your own"
  on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- Groups are created and joined only through the functions below.
create policy "groups: members read"
  on public.groups for select to authenticated
  using (public.is_group_member(id));
create policy "groups: members update"
  on public.groups for update to authenticated
  using (public.is_group_member(id)) with check (public.is_group_member(id));
revoke insert, update, delete on public.groups from authenticated;
grant update (name, cycle_length_days, cycle_start_date, setup_stage, fairness_tolerance,
  minimum_ratings_to_reveal, rating_window_hours, auto_assign_enabled)
  on public.groups to authenticated;

create policy "members: read your groups' members"
  on public.group_members for select to authenticated
  using (public.is_group_member(group_id));
create policy "members: update within your groups"
  on public.group_members for update to authenticated
  using (public.is_group_member(group_id)) with check (public.is_group_member(group_id));
revoke insert, update, delete on public.group_members from authenticated;
grant update (share_weight, carry_over_points) on public.group_members to authenticated;

create policy "chores: members read"
  on public.chores for select to authenticated
  using (public.is_group_member(group_id));
create policy "chores: members add, as themselves"
  on public.chores for insert to authenticated
  with check (public.is_group_member(group_id) and proposer_id = auth.uid());
create policy "chores: members edit"
  on public.chores for update to authenticated
  using (public.is_group_member(group_id)) with check (public.is_group_member(group_id));
revoke delete on public.chores from authenticated;

-- Your own votes and ratings only. Everyone else's arrive as aggregates.
create policy "value votes: read your own"
  on public.chore_value_votes for select to authenticated
  using (rater_id = auth.uid());
revoke insert, update, delete on public.chore_value_votes from authenticated;

create policy "assignments: members read"
  on public.assignments for select to authenticated
  using (public.is_group_member(group_id));
create policy "assignments: members add"
  on public.assignments for insert to authenticated
  with check (
    public.is_group_member(group_id)
    and exists (select 1 from public.group_members m where m.group_id = assignments.group_id and m.user_id = assignments.assignee_id)
  );
create policy "assignments: members update"
  on public.assignments for update to authenticated
  using (public.is_group_member(group_id)) with check (public.is_group_member(group_id));
revoke delete on public.assignments from authenticated;

create policy "quality ratings: read your own"
  on public.quality_ratings for select to authenticated
  using (rater_id = auth.uid());
revoke insert, update, delete on public.quality_ratings from authenticated;

-- ============================================================================================
-- Functions the app calls
-- ============================================================================================

create or replace function public.require_profile() returns uuid
language plpgsql stable security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'sign in first' using errcode = '28000';
  end if;
  if not exists (select 1 from public.profiles where id = auth.uid()) then
    raise exception 'set up your profile first' using errcode = 'P0001';
  end if;
  return auth.uid();
end;
$$;

create or replace function public.create_group(group_name text, cycle_days int default 7)
returns public.groups
language plpgsql security definer
set search_path = public
as $$
declare
  me uuid := public.require_profile();
  created public.groups;
begin
  for attempt in 1..5 loop
    begin
      insert into public.groups (name, cycle_length_days, created_by)
      values (btrim(group_name), cycle_days, me)
      returning * into created;
      exit;
    exception when unique_violation then
      -- Invite code collision; draw another.
      if attempt = 5 then raise; end if;
    end;
  end loop;

  insert into public.group_members (group_id, user_id, role, palette_index)
  values (created.id, me, 'owner', 0);
  return created;
end;
$$;

create or replace function public.preview_invite(code text)
returns table (group_id uuid, group_name text, member_count int, already_member boolean)
language sql stable security definer
set search_path = public
as $$
  select g.id,
         g.name,
         (select count(*)::int from public.group_members m where m.group_id = g.id),
         exists (select 1 from public.group_members m where m.group_id = g.id and m.user_id = auth.uid())
  from public.groups g
  where auth.uid() is not null
    and g.invite_code = public.normalize_invite_code(code);
$$;

create or replace function public.join_group(code text) returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  me uuid := public.require_profile();
  target uuid;
  next_palette int;
begin
  select id into target from public.groups where invite_code = public.normalize_invite_code(code);
  if target is null then
    raise exception 'that invite code doesn''t match a group' using errcode = 'P0002';
  end if;

  if exists (select 1 from public.group_members where group_id = target and user_id = me) then
    return target;
  end if;

  select coalesce(max(palette_index) + 1, 0) into next_palette
  from public.group_members where group_id = target;

  insert into public.group_members (group_id, user_id, palette_index)
  values (target, me, next_palette);
  return target;
end;
$$;

create or replace function public.regenerate_invite_code(target uuid) returns text
language plpgsql security definer
set search_path = public
as $$
declare
  fresh text;
begin
  if not exists (select 1 from public.group_members where group_id = target and user_id = auth.uid() and role = 'owner') then
    raise exception 'only the group owner can change the invite code' using errcode = '42501';
  end if;
  loop
    fresh := public.new_invite_code();
    begin
      update public.groups set invite_code = fresh, updated_at = now() where id = target;
      return fresh;
    exception when unique_violation then
      -- try again
    end;
  end loop;
end;
$$;

create or replace function public.leave_group(target uuid) returns void
language plpgsql security definer
set search_path = public
as $$
declare
  was_owner boolean;
  successor uuid;
begin
  delete from public.group_members
  where group_id = target and user_id = auth.uid()
  returning role = 'owner' into was_owner;

  if was_owner is null then
    return;
  end if;

  select user_id into successor from public.group_members
  where group_id = target order by joined_at limit 1;

  if successor is null then
    delete from public.groups where id = target;
  elsif was_owner then
    update public.group_members set role = 'owner' where group_id = target and user_id = successor;
  end if;
end;
$$;

create or replace function public.cast_value_vote(target_chore uuid, difficulty int, labor int, minutes int)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  chore_group uuid;
  proposer uuid;
begin
  select c.group_id, c.proposer_id into chore_group, proposer from public.chores c where c.id = target_chore;
  if chore_group is null or not public.is_group_member(chore_group) then
    raise exception 'chore not found' using errcode = 'P0002';
  end if;
  if proposer = auth.uid() then
    raise exception 'you can''t rate a chore you added' using errcode = '42501';
  end if;

  insert into public.chore_value_votes (chore_id, group_id, rater_id, difficulty, labor, minutes)
  values (target_chore, chore_group, auth.uid(), difficulty, labor, minutes)
  on conflict (chore_id, rater_id) do nothing;
end;
$$;

-- Settles one task from its ratings. Internal: callable only from the functions below.
create or replace function public.settle_assignment_internal(target uuid) returns void
language plpgsql security definer
set search_path = public
as $$
begin
  perform set_config('choresplit.settling', 'on', true);
  update public.assignments a
  set status = 'settled',
      awarded_points = public.settled_points(
        a.points_quoted,
        (select avg(r.score)::double precision from public.quality_ratings r where r.assignment_id = a.id)
      )
  where a.id = target and a.status = 'awaitingReview';
  perform set_config('choresplit.settling', 'off', true);
end;
$$;

-- True once every member except the person who did the task has rated it.
create or replace function public.all_raters_in(target uuid) returns boolean
language sql stable security definer
set search_path = public
as $$
  select not exists (
    select 1
    from public.assignments a
    join public.group_members m on m.group_id = a.group_id
    where a.id = target
      and m.user_id is distinct from a.assignee_id
      and not exists (
        select 1 from public.quality_ratings r where r.assignment_id = a.id and r.rater_id = m.user_id
      )
  );
$$;

create or replace function public.rate_assignment(target uuid, score int, note text default '')
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  task public.assignments;
begin
  select * into task from public.assignments where id = target;
  if not found or not public.is_group_member(task.group_id) then
    raise exception 'task not found' using errcode = 'P0002';
  end if;
  if task.assignee_id = auth.uid() then
    raise exception 'you can''t rate your own task' using errcode = '42501';
  end if;
  if task.status <> 'awaitingReview' then
    raise exception 'this task isn''t being rated any more' using errcode = 'P0001';
  end if;

  insert into public.quality_ratings (assignment_id, group_id, rater_id, score, note)
  values (target, task.group_id, auth.uid(), score, left(btrim(coalesce(note, '')), 280))
  on conflict (assignment_id, rater_id) do nothing;

  if public.all_raters_in(target) then
    perform public.settle_assignment_internal(target);
  end if;
end;
$$;

-- Settles every task in a group whose rating window has closed, or that everyone has rated
-- (for instance a task finished in a one-person group). Returns how many were settled.
create or replace function public.settle_due_assignments(target_group uuid) returns int
language plpgsql security definer
set search_path = public
as $$
declare
  due record;
  settled_count int := 0;
begin
  if not public.is_group_member(target_group) then
    raise exception 'group not found' using errcode = 'P0002';
  end if;

  for due in
    select a.id
    from public.assignments a
    join public.groups g on g.id = a.group_id
    where a.group_id = target_group
      and a.status = 'awaitingReview'
      and (
        coalesce(a.completed_at, a.updated_at) + make_interval(hours => g.rating_window_hours) <= now()
        or public.all_raters_in(a.id)
      )
  loop
    perform public.settle_assignment_internal(due.id);
    settled_count := settled_count + 1;
  end loop;

  return settled_count;
end;
$$;

-- Aggregated value votes: enough to price every chore, never who voted what.
create or replace function public.chore_value_summaries(target_group uuid)
returns table (chore_id uuid, vote_count int, avg_difficulty double precision, avg_labor double precision, avg_minutes double precision)
language sql stable security definer
set search_path = public
as $$
  select c.id,
         count(v.rater_id)::int,
         avg(v.difficulty)::double precision,
         avg(v.labor)::double precision,
         avg(v.minutes)::double precision
  from public.chores c
  left join public.chore_value_votes v on v.chore_id = c.id
  where c.group_id = target_group and public.is_group_member(target_group)
  group by c.id;
$$;

-- Aggregated quality ratings. The average and the notes stay hidden until the group's reveal
-- threshold is met, so a single rating can never be traced back by elimination.
create or replace function public.assignment_rating_summaries(target_group uuid)
returns table (assignment_id uuid, rating_count int, average_score double precision, notes text[])
language sql stable security definer
set search_path = public
as $$
  select a.id,
         count(r.rater_id)::int,
         case when count(r.rater_id) >= g.minimum_ratings_to_reveal
              then avg(r.score)::double precision end,
         case when count(r.rater_id) >= g.minimum_ratings_to_reveal
              then coalesce(array_agg(r.note order by r.note) filter (where r.note <> ''), '{}') end
  from public.assignments a
  join public.groups g on g.id = a.group_id
  left join public.quality_ratings r on r.assignment_id = a.id
  where a.group_id = target_group
    and public.is_group_member(target_group)
    and a.status in ('awaitingReview', 'settled')
  group by a.id, g.minimum_ratings_to_reveal;
$$;

-- One device at a time hands out catch-up chores and rolls the cycle; otherwise two phones
-- opening at once would both assign the same work. The claim lapses after ten minutes.
create or replace function public.claim_maintenance(target_group uuid) returns boolean
language plpgsql security definer
set search_path = public
as $$
declare
  claimed boolean;
begin
  if not public.is_group_member(target_group) then
    return false;
  end if;
  update public.groups
  set maintenance_claimed_at = now()
  where id = target_group
    and (maintenance_claimed_at is null or maintenance_claimed_at < now() - interval '10 minutes')
  returning true into claimed;
  return coalesce(claimed, false);
end;
$$;

-- Functions are callable only by signed-in users, and the internal one by nobody.
revoke execute on function public.new_invite_code(), public.normalize_invite_code(text),
  public.is_group_member(uuid), public.shares_group_with(uuid), public.require_profile(),
  public.create_group(text, int), public.preview_invite(text), public.join_group(text),
  public.regenerate_invite_code(uuid), public.leave_group(uuid),
  public.cast_value_vote(uuid, int, int, int), public.settle_assignment_internal(uuid),
  public.all_raters_in(uuid), public.rate_assignment(uuid, int, text),
  public.settle_due_assignments(uuid), public.chore_value_summaries(uuid),
  public.assignment_rating_summaries(uuid), public.claim_maintenance(uuid),
  public.settled_points(int, double precision)
  from public, anon;

grant execute on function public.is_group_member(uuid), public.shares_group_with(uuid),
  public.create_group(text, int), public.preview_invite(text), public.join_group(text),
  public.regenerate_invite_code(uuid), public.leave_group(uuid),
  public.cast_value_vote(uuid, int, int, int), public.rate_assignment(uuid, int, text),
  public.settle_due_assignments(uuid), public.chore_value_summaries(uuid),
  public.assignment_rating_summaries(uuid), public.claim_maintenance(uuid),
  public.settled_points(int, double precision)
  to authenticated;

-- ============================================================================================
-- Proof videos
-- ============================================================================================

-- Videos live at "<group id>/<assignment id>.mp4". Returns the group id, or null for any path
-- that doesn't start with one — so a malformed name is simply refused rather than erroring.
create or replace function public.proof_video_group(object_name text) returns uuid
language plpgsql immutable
as $$
declare
  first_folder text := split_part(object_name, '/', 1);
begin
  if first_folder ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return first_folder::uuid;
  end if;
  return null;
end;
$$;
grant execute on function public.proof_video_group(text) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('proof-videos', 'proof-videos', false, 104857600, array['video/mp4', 'video/quicktime'])
on conflict (id) do nothing;

create policy "proof videos: group members watch"
  on storage.objects for select to authenticated
  using (bucket_id = 'proof-videos' and public.is_group_member(public.proof_video_group(name)));
create policy "proof videos: group members upload"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'proof-videos' and public.is_group_member(public.proof_video_group(name)));
create policy "proof videos: group members replace"
  on storage.objects for update to authenticated
  using (bucket_id = 'proof-videos' and public.is_group_member(public.proof_video_group(name)));
create policy "proof videos: group members delete"
  on storage.objects for delete to authenticated
  using (bucket_id = 'proof-videos' and public.is_group_member(public.proof_video_group(name)));

-- ============================================================================================
-- Realtime: phones hear about changes to their group's shared tables. Ratings and votes are
-- deliberately not published.
-- ============================================================================================

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.groups, public.group_members, public.chores, public.assignments;
  end if;
end;
$$;
