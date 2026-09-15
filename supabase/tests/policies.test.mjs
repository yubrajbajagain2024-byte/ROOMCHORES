import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';

const migration = readFileSync(process.argv[2], 'utf8');
const db = new PGlite();
let passed = 0, failed = 0;

// --- Minimal stand-ins for the parts of Supabase the migration relies on -----------------
await db.exec(`
  create role anon nologin;
  create role authenticated nologin;
  grant usage on schema public to anon, authenticated;
  alter default privileges in schema public grant all on tables to anon, authenticated;
  alter default privileges in schema public grant all on functions to anon, authenticated;

  create schema auth;
  create table auth.users (id uuid primary key);
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
  $$;
  grant usage on schema auth to anon, authenticated;
  grant execute on function auth.uid() to anon, authenticated;

  create schema storage;
  create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
  create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets(id), name text, owner uuid);
  alter table storage.objects enable row level security;
  grant usage on schema storage to authenticated;
  grant select, insert, update, delete on storage.objects to authenticated;

  create publication supabase_realtime;
`);
await db.exec(migration);
console.log('migration applied\n');

const users = {
  alice: 'aaaaaaaa-0000-4000-8000-000000000001',
  bob:   'bbbbbbbb-0000-4000-8000-000000000002',
  carol: 'cccccccc-0000-4000-8000-000000000003',
  dave:  'dddddddd-0000-4000-8000-000000000004',
};
for (const id of Object.values(users)) await db.query(`insert into auth.users (id) values ($1)`, [id]);

// Run SQL as a signed-in user, in a transaction so settings and role don't leak.
async function as(user, sql, params = []) {
  await db.exec('begin');
  try {
    await db.query(`select set_config('request.jwt.claim.sub', $1, true)`, [user ? users[user] : '']);
    await db.exec(user ? 'set local role authenticated' : 'set local role anon');
    const result = await db.query(sql, params);
    await db.exec('commit');
    return result.rows;
  } catch (e) {
    await db.exec('rollback');
    throw e;
  }
}
async function check(name, fn) {
  try { await fn(); passed++; console.log('  ✔', name); }
  catch (e) { failed++; console.log('  ✘', name, '\n     ', e.message); }
}
function eq(actual, expected, what = '') {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(`${what} expected ${b}, got ${a}`);
}
async function rejects(promise, fragment) {
  try { await promise; } catch (e) {
    if (fragment && !e.message.toLowerCase().includes(fragment.toLowerCase()))
      throw new Error(`rejected with "${e.message}", expected "${fragment}"`);
    return;
  }
  throw new Error(`expected rejection containing "${fragment}"`);
}

let groupId, inviteCode;
const chore = 'c0000000-0000-4000-8000-000000000001';
const task = 'a0000000-0000-4000-8000-000000000001';
const oldTask = 'a0000000-0000-4000-8000-000000000002';

console.log('Accounts and groups');
await check('you need a profile before creating a group', () =>
  rejects(as('alice', `select * from create_group('Flat 3B', 7)`), 'profile'));
await check('profiles can only be created for yourself', () =>
  rejects(as('alice', `insert into profiles (id, display_name) values ($1, 'Imposter')`, [users.bob]), 'row-level security'));
for (const [name, emoji] of [['alice', '🦊'], ['bob', '🌻'], ['carol', '🎧'], ['dave', '🐙']]) {
  await as(name, `insert into profiles (id, display_name, emoji) values ($1, $2, $3)`, [users[name], name[0].toUpperCase() + name.slice(1), emoji]);
}
await check('creating a group makes you its owner and issues an invite code', async () => {
  const [g] = await as('alice', `select * from create_group('Flat 3B', 7)`);
  groupId = g.id; inviteCode = g.invite_code;
  if (!/^[A-HJ-NP-Z2-9]{8}$/.test(inviteCode)) throw new Error(`bad invite code ${inviteCode}`);
  eq(await as('alice', `select role from group_members where group_id = $1`, [groupId]), [{ role: 'owner' }]);
});
await check('signed-out visitors see nothing', async () =>
  rejects(as(null, `select * from groups`), 'permission denied'));
await check('a stranger can\'t see the group', async () =>
  eq(await as('bob', `select id from groups`), []));
await check('a stranger can\'t join by writing a membership row', () =>
  rejects(as('bob', `insert into group_members (group_id, user_id) values ($1, $2)`, [groupId, users.bob]), 'permission denied'));
await check('previewing an invite shows the group without joining it', async () => {
  const typed = inviteCode.toLowerCase().slice(0, 4) + '-' + inviteCode.toLowerCase().slice(4);
  eq(await as('bob', `select group_name, member_count, already_member from preview_invite($1)`, [typed]),
     [{ group_name: 'Flat 3B', member_count: 1, already_member: false }]);
  eq(await as('bob', `select id from groups`), []);
});
await check('a wrong code is refused', () => rejects(as('bob', `select join_group('ZZZZZZZZ')`), 'doesn\'t match'));
await check('joining with the code works, however it was typed', async () => {
  const typed = ' ' + inviteCode.slice(0, 4).toLowerCase() + ' ' + inviteCode.slice(4) + ' ';
  const [{ join_group }] = await as('bob', `select join_group($1)`, [typed]);
  eq(join_group, groupId);
  eq((await as('bob', `select name from groups`)).map(r => r.name), ['Flat 3B']);
  await as('carol', `select join_group($1)`, [inviteCode]);
});
await check('joining twice is harmless', async () => {
  await as('bob', `select join_group($1)`, [inviteCode]);
  eq(await as('alice', `select count(*)::int as n from group_members where group_id = $1`, [groupId]), [{ n: 3 }]);
});
await check('members see each other\'s profiles; strangers don\'t', async () => {
  eq((await as('bob', `select display_name from profiles order by display_name`)).map(r => r.display_name), ['Alice', 'Bob', 'Carol']);
  eq((await as('dave', `select display_name from profiles`)).map(r => r.display_name), ['Dave']);
});
await check('members can\'t promote themselves or change the invite code', async () => {
  await rejects(as('bob', `update group_members set role = 'owner' where user_id = $1`, [users.bob]), 'permission denied');
  await rejects(as('bob', `update groups set invite_code = 'AAAAAAAA'`), 'permission denied');
  await rejects(as('bob', `select regenerate_invite_code($1)`, [groupId]), 'owner');
});
await check('the owner can issue a new invite code, and the old one stops working', async () => {
  const [{ regenerate_invite_code: fresh }] = await as('alice', `select regenerate_invite_code($1)`, [groupId]);
  if (fresh === inviteCode) throw new Error('code did not change');
  eq(await as('dave', `select * from preview_invite($1)`, [inviteCode]), []);
  inviteCode = fresh;
});

console.log('\nChores and anonymous value votes');
await check('members add chores as themselves only', async () => {
  await rejects(as('bob', `insert into chores (id, group_id, title, proposer_id, proposed_difficulty, proposed_labor, proposed_minutes)
                           values (gen_random_uuid(), $1, 'Forged', $2, 3, 3, 15)`, [groupId, users.alice]), 'row-level security');
  await as('alice', `insert into chores (id, group_id, title, category, recurrence, proposer_id, proposed_difficulty, proposed_labor, proposed_minutes)
                     values ($1, $2, 'Scrub the toilet', 'bathroom', 'weekly', $3, 4, 3, 15)`, [chore, groupId, users.alice]);
});
await check('outsiders can\'t add chores to the group', () =>
  rejects(as('dave', `insert into chores (id, group_id, title, proposer_id, proposed_difficulty, proposed_labor, proposed_minutes)
                      values (gen_random_uuid(), $1, 'Spam', $2, 1, 1, 5)`, [groupId, users.dave]), 'row-level security'));
await check('you can\'t rate the worth of your own chore', () =>
  rejects(as('alice', `select cast_value_vote($1, 5, 5, 60)`, [chore]), 'you added'));
await check('a second vote from the same person is ignored', async () => {
  await as('bob', `select cast_value_vote($1, 5, 4, 30)`, [chore]);
  await as('bob', `select cast_value_vote($1, 1, 1, 5)`, [chore]);
  await as('carol', `select cast_value_vote($1, 3, 2, 20)`, [chore]);
  eq(await as('bob', `select difficulty from chore_value_votes`), [{ difficulty: 5 }]);
});
await check('votes are private: nobody reads anyone else\'s', async () => {
  eq(await as('alice', `select * from chore_value_votes`), []);
  eq((await as('carol', `select difficulty from chore_value_votes`)).length, 1);
});
await check('the group sees only aggregates', async () => {
  eq(await as('alice', `select vote_count, avg_difficulty, avg_labor, avg_minutes from chore_value_summaries($1)`, [groupId]),
     [{ vote_count: 2, avg_difficulty: 4, avg_labor: 3, avg_minutes: 25 }]);
  eq(await as('dave', `select * from chore_value_summaries($1)`, [groupId]), []);
});

console.log('\nTasks, completion and settlement');
await check('you can only give tasks to people in the group', async () => {
  await rejects(as('alice', `insert into assignments (id, group_id, chore_id, assignee_id, due_date, points_quoted)
                             values (gen_random_uuid(), $1, $2, $3, now() + interval '1 day', 3)`, [groupId, chore, users.dave]), 'row-level security');
  await as('alice', `insert into assignments (id, group_id, chore_id, assignee_id, due_date, points_quoted)
                     values ($1, $2, $3, $4, now() + interval '1 day', 3)`, [task, groupId, chore, users.alice]);
});
await check('only the person doing a task can finish it', () =>
  rejects(as('bob', `update assignments set status = 'awaitingReview', completed_at = now() where id = $1`, [task]), 'only the person'));
await check('a phone can\'t award itself points', async () => {
  await as('alice', `update assignments set status = 'settled', awarded_points = 99, points_quoted = 4, completed_at = now() where id = $1`, [task]);
  eq(await as('alice', `select status, awarded_points, points_quoted from assignments where id = $1`, [task]),
     [{ status: 'awaitingReview', awarded_points: null, points_quoted: 3 }]);
});
await check('you can\'t rate your own task', () =>
  rejects(as('alice', `select rate_assignment($1, 5, '')`, [task]), 'your own task'));
await check('outsiders can\'t rate', () =>
  rejects(as('dave', `select rate_assignment($1, 5, '')`, [task]), 'not found'));
await check('one rating in: count shown, score and notes hidden', async () => {
  await as('bob', `select rate_assignment($1, 1, 'Missed behind the toilet')`, [task]);
  eq(await as('alice', `select rating_count, average_score, notes from assignment_rating_summaries($1)`, [groupId]),
     [{ rating_count: 1, average_score: null, notes: null }]);
  eq(await as('alice', `select status from assignments where id = $1`, [task]), [{ status: 'awaitingReview' }]);
});
await check('ratings are private: not even the person rated can read them', async () => {
  eq(await as('alice', `select * from quality_ratings`), []);
  eq(await as('carol', `select * from quality_ratings`), []);
  eq((await as('bob', `select score from quality_ratings`)), [{ score: 1 }]);
});
await check('a second rating from the same person is ignored', async () => {
  await as('bob', `select rate_assignment($1, 5, 'changed my mind')`, [task]);
  eq((await as('bob', `select score from quality_ratings`)), [{ score: 1 }]);
});
await check('last rating in: the server settles and reveals', async () => {
  await as('carol', `select rate_assignment($1, 2, '')`, [task]);
  // average 1.5 → multiplier 0.625 → 3 × 0.625 = 1.875 → nearest half point 2.0
  eq(await as('alice', `select status, awarded_points from assignments where id = $1`, [task]),
     [{ status: 'settled', awarded_points: 2 }]);
  eq(await as('alice', `select rating_count, average_score, notes from assignment_rating_summaries($1)`, [groupId]),
     [{ rating_count: 2, average_score: 1.5, notes: ['Missed behind the toilet'] }]);
});
await check('a settled task is final, but its video can still be cleared', async () => {
  await as('alice', `update assignments set proof_video_path = 'x', status = 'open', completed_at = null where id = $1`, [task]);
  await as('alice', `update assignments set proof_video_path = null where id = $1`, [task]);
  eq(await as('bob', `select status, awarded_points, proof_video_path, completed_at is not null as done from assignments where id = $1`, [task]),
     [{ status: 'settled', awarded_points: 2, proof_video_path: null, done: true }]);
});
await check('rating a settled task is refused', () =>
  rejects(as('bob', `select rate_assignment($1, 5, '')`, [task]), 'isn\'t being rated'));
await check('tasks whose rating window has closed settle on the next sweep', async () => {
  await as('bob', `insert into assignments (id, group_id, chore_id, assignee_id, due_date, points_quoted, status, completed_at)
                   values ($1, $2, $3, $4, now() - interval '3 days', 4, 'awaitingReview', now() - interval '49 hours')`, [oldTask, groupId, chore, users.bob]);
  await as('carol', `select rate_assignment($1, 2, '')`, [oldTask]);
  eq(await as('dave', `select settle_due_assignments($1)`, [groupId]).catch(e => e.message.includes('not found') ? 'refused' : e.message), 'refused');
  const [{ settle_due_assignments: n }] = await as('alice', `select settle_due_assignments($1)`, [groupId]);
  eq(n, 1, 'settled count');
  // one 2-star rating → multiplier 0.75 → 4 × 0.75 = 3.0
  eq(await as('bob', `select status, awarded_points from assignments where id = $1`, [oldTask]), [{ status: 'settled', awarded_points: 3 }]);
});

console.log('\nPoints parity with the app');
await check('settled_points matches PointsEngine.settledPoints for every chore and score', async () => {
  const swift = (quoted, avg) => {
    if (avg === null) return quoted;
    const s = Math.min(5, Math.max(1, avg));
    const m = s >= 3 ? 1 : 0.5 + (s - 1) * 0.25;
    const raw = quoted * m * 2;
    const rounded = Math.sign(raw) * Math.round(Math.abs(raw));   // half away from zero, as Swift
    return Math.max(0.5, rounded / 2);
  };
  for (let quoted = 1; quoted <= 4; quoted++) {
    for (const avg of [null, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75, 3, 4, 5]) {
      const [{ settled_points }] = await as('alice', `select settled_points($1, $2)`, [quoted, avg]);
      if (settled_points !== swift(quoted, avg)) throw new Error(`quoted ${quoted}, avg ${avg}: sql ${settled_points} vs swift ${swift(quoted, avg)}`);
    }
  }
});

console.log('\nMaintenance claim');
await check('only one phone at a time gets to hand out chores', async () => {
  eq(await as('alice', `select claim_maintenance($1) as c`, [groupId]), [{ c: true }]);
  eq(await as('bob', `select claim_maintenance($1) as c`, [groupId]), [{ c: false }]);
  eq(await as('dave', `select claim_maintenance($1) as c`, [groupId]), [{ c: false }]);
});

console.log('\nProof videos');
const videoPath = () => `${groupId}/${task}.mp4`;
await check('members can upload and watch; outsiders can\'t', async () => {
  await as('alice', `insert into storage.objects (bucket_id, name) values ('proof-videos', $1)`, [videoPath()]);
  eq((await as('bob', `select name from storage.objects`)).length, 1);
  eq(await as('dave', `select name from storage.objects`), []);
  await rejects(as('dave', `insert into storage.objects (bucket_id, name) values ('proof-videos', $1)`, [`${groupId}/sneaky.mp4`]), 'row-level security');
});
await check('paths that don\'t start with a group are refused', () =>
  rejects(as('alice', `insert into storage.objects (bucket_id, name) values ('proof-videos', 'not-a-group/x.mp4')`), 'row-level security'));

console.log('\nLeaving');
await check('when the owner leaves, the longest-standing member takes over', async () => {
  await as('alice', `select leave_group($1)`, [groupId]);
  eq(await as('alice', `select id from groups`), []);
  eq(await as('bob', `select role from group_members where user_id = $1`, [users.bob]), [{ role: 'owner' }]);
});
await check('when the last member leaves, the group is gone', async () => {
  await as('bob', `select leave_group($1)`, [groupId]);
  await as('carol', `select leave_group($1)`, [groupId]);
  const [{ n }] = await db.query(`select count(*)::int as n from groups`).then(r => r.rows);
  eq(n, 0);
});

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
