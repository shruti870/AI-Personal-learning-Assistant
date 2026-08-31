-- =====================================================================
-- 003_typing_telemetry.sql
-- Keystroke-derived focus signal for the coding section.
--
-- Stores AGGREGATES PER WINDOW ONLY. No keystrokes, no code content.
-- Gated behind profiles.tracking_opt_in like all attention data.
-- =====================================================================

create table typing_windows (
  window_id            bigserial primary key,
  session_id           uuid references study_sessions(session_id) on delete cascade,
  student_id           uuid not null references profiles(student_id) on delete cascade,
  minutes_into_session numeric not null,
  window_seconds       int     not null default 120,

  chars_typed          int     not null default 0,
  mean_iki_ms          numeric,          -- inter-key interval, pauses excluded
  sd_iki_ms            numeric,          -- rhythm consistency; rises with fatigue
  backspace_rate       numeric,          -- corrections per char
  pauses_over_2s       int     not null default 0,
  longest_pause_ms     int,
  mean_burst_len       numeric,          -- chars per uninterrupted run

  -- Pauses classified by how they END, which separates thinking from
  -- disengagement far better than pause length does.
  pauses_thinking      int     not null default 0,
  pauses_lost          int     not null default 0,

  run_attempts         int     not null default 0,
  run_failures         int     not null default 0,

  focus_index          numeric,          -- filled by the Python job
  created_at           timestamptz not null default now()
);
create index on typing_windows(student_id, created_at desc);
create index on typing_windows(session_id);

-- Per-student typing baseline. Needs ~3 sessions before it means anything;
-- until then focus_index stays null and the UI reports nothing.
create table typing_baseline (
  student_id      uuid primary key references profiles(student_id) on delete cascade,
  mean_iki_ms     numeric,
  sd_iki_ms       numeric,
  backspace_rate  numeric,
  mean_burst_len  numeric,
  sample_windows  int not null default 0,
  updated_at      timestamptz not null default now()
);

alter table typing_windows  enable row level security;
alter table typing_baseline enable row level security;

create policy own_typing_windows on typing_windows for all to authenticated
  using (student_id = auth.uid()) with check (student_id = auth.uid());
create policy own_typing_baseline on typing_baseline for all to authenticated
  using (student_id = auth.uid()) with check (student_id = auth.uid());

-- Coding problems are content, not student data: readable by any signed-in user.
create table coding_problems (
  problem_id   text primary key,
  concept_id   text references concepts(concept_id) on delete set null,
  title        text not null,
  prompt       text not null,
  starter_code text not null,
  difficulty   numeric not null default 0,
  language     text not null default 'javascript',
  is_active    boolean not null default true
);

create table coding_tests (
  test_id     bigserial primary key,
  problem_id  text not null references coding_problems(problem_id) on delete cascade,
  input_json  text not null,
  expect_json text not null,
  is_hidden   boolean not null default false,
  ordinal     int not null default 0
);

alter table coding_problems enable row level security;
alter table coding_tests    enable row level security;
create policy read_problems on coding_problems for select to authenticated using (true);
create policy read_tests    on coding_tests    for select to authenticated using (true);

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty) values
('cp.two_sum', 'dsa.arrays', 'Two Sum',
 'Return the indices of the two numbers in nums that add up to target. Exactly one solution exists. Return them as an array, smaller index first.',
 'function solve(nums, target) {\n  // your code here\n}', -0.3),
('cp.binary_search', 'dsa.binary_search', 'Binary Search',
 'Return the index of target in the sorted array nums, or -1 if it is not present. Must run in O(log n).',
 'function solve(nums, target) {\n  // your code here\n}', 0.0),
('cp.kth_largest', 'dsa.heaps', 'Kth Largest Element',
 'Return the kth largest element in nums. Duplicates count separately, so [3,2,3,1] with k=2 gives 3.',
 'function solve(nums, k) {\n  // your code here\n}', 0.5)
on conflict (problem_id) do nothing;

insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal) values
('cp.two_sum', '[[2,7,11,15],9]', '[0,1]', false, 0),
('cp.two_sum', '[[3,2,4],6]', '[1,2]', false, 1),
('cp.two_sum', '[[3,3],6]', '[0,1]', true, 2),
('cp.binary_search', '[[-1,0,3,5,9,12],9]', '4', false, 0),
('cp.binary_search', '[[-1,0,3,5,9,12],2]', '-1', false, 1),
('cp.binary_search', '[[5],5]', '0', true, 2),
('cp.kth_largest', '[[3,2,1,5,6,4],2]', '5', false, 0),
('cp.kth_largest', '[[3,2,3,1,2,4,5,5,6],4]', '4', false, 1),
('cp.kth_largest', '[[1],1]', '1', true, 2);