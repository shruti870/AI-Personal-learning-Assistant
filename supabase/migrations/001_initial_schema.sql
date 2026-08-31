-- =====================================================================
-- AI Personal Learning Assistant â€” initial Supabase schema
-- Run in Supabase SQL Editor, or save as supabase/migrations/001_initial_schema.sql
--
-- Section 1  Content model      (subjects, concepts, DAG, questions)
-- Section 2  Student model      (profiles, attempts, mastery)
-- Section 3  Attention model    (sessions, focus events, focus curve)
-- Section 4  Planning model     (exam targets, study plans)
-- Section 5  Inline BKT trigger (fast-path mastery update)
-- Section 6  Row Level Security
-- =====================================================================

create extension if not exists "pgcrypto";


-- =====================================================================
-- SECTION 1 â€” CONTENT MODEL
-- =====================================================================

create table subjects (
  subject_id    text primary key,              -- 'dbms', 'cn', 'os', 'dsa', 'aptitude'
  name          text not null,
  description   text,
  is_authored   boolean not null default false -- true = hand-verified content
);

create table concepts (
  concept_id    text primary key,              -- 'dbms.normalization.3nf'
  subject_id    text not null references subjects(subject_id) on delete cascade,
  name          text not null,
  level         int  not null default 0,       -- DAG depth, 0 = no prerequisites
  description   text
);
create index on concepts(subject_id);

-- DAG edges. parent is a prerequisite for child.
-- weight = how strongly the child depends on the parent (0..1)
create table prerequisites (
  parent_id  text not null references concepts(concept_id) on delete cascade,
  child_id   text not null references concepts(concept_id) on delete cascade,
  weight     numeric not null default 0.7 check (weight between 0 and 1),
  primary key (parent_id, child_id),
  check (parent_id <> child_id)
);
create index on prerequisites(child_id);

-- Named wrong beliefs. This table is what makes diagnosis possible.
create table misconceptions (
  misconception_id text primary key,           -- 'dbms.m041'
  concept_id       text not null references concepts(concept_id) on delete cascade,
  label            text not null,              -- 'confuses 3NF with BCNF'
  remediation_note text
);

create table questions (
  question_id        uuid primary key default gen_random_uuid(),
  primary_concept_id text not null references concepts(concept_id) on delete cascade,
  stem               text not null,
  difficulty         numeric not null default 0.0,   -- IRT b-parameter, -3..+3
  median_time_sec    int     not null default 45,
  source             text    not null default 'authored'
    check (source in ('authored', 'llm_generated', 'llm_verified')),
  is_active          boolean not null default true
);
create index on questions(primary_concept_id);

-- A question may exercise several concepts; weights sum to ~1.0
create table question_concepts (
  question_id uuid not null references questions(question_id) on delete cascade,
  concept_id  text not null references concepts(concept_id) on delete cascade,
  weight      numeric not null default 1.0 check (weight between 0 and 1),
  primary key (question_id, concept_id)
);

create table options (
  option_id        uuid primary key default gen_random_uuid(),
  question_id      uuid not null references questions(question_id) on delete cascade,
  body             text not null,
  is_correct       boolean not null default false,
  misconception_id text references misconceptions(misconception_id) on delete set null,
  ordinal          int not null default 0
);
create index on options(question_id);

-- Exactly one correct option per question
create unique index one_correct_per_question
  on options(question_id) where is_correct;


-- =====================================================================
-- SECTION 2 â€” STUDENT MODEL
-- =====================================================================

create table profiles (
  student_id      uuid primary key references auth.users(id) on delete cascade,
  display_name    text,
  cohort          text,
  weekly_minutes  int not null default 300,      -- declared study budget
  tracking_opt_in boolean not null default false,-- attention tracking consent
  created_at      timestamptz not null default now()
);

create type error_kind as enum (
  'mastered',           -- correct, high confidence
  'uncertain_correct',  -- correct, low confidence
  'guess',              -- correct, implausibly fast
  'careless',           -- wrong, implausibly fast
  'misconception',      -- wrong, chose a tagged distractor
  'procedural_slip',    -- wrong, untagged distractor
  'unattempted'
);

create table attempts (
  attempt_id           uuid primary key default gen_random_uuid(),
  student_id           uuid not null references profiles(student_id) on delete cascade,
  question_id          uuid not null references questions(question_id) on delete cascade,
  chosen_option_id     uuid references options(option_id) on delete set null,
  session_id           uuid,                    -- FK added after study_sessions
  is_correct           boolean not null,
  confidence           smallint check (confidence between 1 and 3),
  time_taken_sec       int not null,
  minutes_into_session numeric,                 -- key feature for the focus curve
  explanation_text     text,
  explanation_score    numeric,                 -- 0..1, semantic match to rubric
  error_type           error_kind,
  created_at           timestamptz not null default now()
);
create index on attempts(student_id, created_at desc);
create index on attempts(session_id);

create table mastery (
  student_id       uuid not null references profiles(student_id) on delete cascade,
  concept_id       text not null references concepts(concept_id) on delete cascade,
  mastery_prob     numeric not null default 0.15 check (mastery_prob between 0 and 1),
  uncertainty      numeric not null default 1.0,
  half_life_days   numeric not null default 5.0,   -- from the forgetting model
  observation_count int    not null default 0,
  last_review_at   timestamptz,
  next_review_at   timestamptz,
  updated_at       timestamptz not null default now(),
  primary key (student_id, concept_id)
);
create index on mastery(student_id, next_review_at);

-- Per-concept BKT parameters, fit offline by the Python service
create table bkt_params (
  concept_id text primary key references concepts(concept_id) on delete cascade,
  p_init     numeric not null default 0.15,
  p_transit  numeric not null default 0.15,
  p_slip     numeric not null default 0.10,
  p_guess    numeric not null default 0.25
);

-- Concept pairs this student systematically confuses
create table confusion_pairs (
  student_id      uuid not null references profiles(student_id) on delete cascade,
  concept_a       text not null references concepts(concept_id) on delete cascade,
  concept_b       text not null references concepts(concept_id) on delete cascade,
  confusion_count int not null default 1,
  updated_at      timestamptz not null default now(),
  primary key (student_id, concept_a, concept_b),
  check (concept_a < concept_b)
);


-- =====================================================================
-- SECTION 3 â€” ATTENTION MODEL
-- =====================================================================

create table study_sessions (
  session_id           uuid primary key default gen_random_uuid(),
  student_id           uuid not null references profiles(student_id) on delete cascade,
  subject_id           text references subjects(subject_id) on delete set null,
  started_at           timestamptz not null default now(),
  ended_at             timestamptz,
  planned_minutes      int,
  active_minutes       numeric,      -- wall clock minus idle and blurred time
  blur_count           int not null default 0,
  idle_seconds         int not null default 0,
  baseline_accuracy    numeric,      -- accuracy in the first 5 minutes
  end_reason           text          -- 'completed', 'fatigue_cutoff', 'abandoned'
);
create index on study_sessions(student_id, started_at desc);

alter table attempts
  add constraint attempts_session_fk
  foreign key (session_id) references study_sessions(session_id) on delete set null;

create type focus_event_kind as enum (
  'tab_blur', 'tab_focus', 'idle_start', 'idle_end', 'break_taken'
);

create table focus_events (
  event_id    bigserial primary key,
  session_id  uuid not null references study_sessions(session_id) on delete cascade,
  student_id  uuid not null references profiles(student_id) on delete cascade,
  event_type  focus_event_kind not null,
  occurred_at timestamptz not null default now(),
  duration_ms int
);
create index on focus_events(session_id, occurred_at);

-- One row per student. Written by the nightly Python job.
create table attention_profile (
  student_id            uuid primary key references profiles(student_id) on delete cascade,
  focus_half_life_min   numeric,   -- tau in accuracy(t) = baseline * exp(-t / tau)
  baseline_accuracy     numeric,
  fatigue_slope         numeric,   -- response-time drift per minute
  recommended_block_min int,       -- derived: roughly tau, clamped to 15..50
  recommended_break_min int not null default 5,
  active_ratio          numeric,   -- active_minutes / wall_clock, rolling mean
  sample_sessions       int not null default 0,
  updated_at            timestamptz not null default now()
);

-- Circadian performance, bucketed by local hour
create table hourly_performance (
  student_id   uuid not null references profiles(student_id) on delete cascade,
  hour_of_day  smallint not null check (hour_of_day between 0 and 23),
  attempt_count int not null default 0,
  accuracy     numeric,
  mean_time_ratio numeric,
  primary key (student_id, hour_of_day)
);


-- =====================================================================
-- SECTION 4 â€” PLANNING MODEL
-- =====================================================================

-- Placement targets: same engine, different topic weights
create table exam_profiles (
  exam_id     text primary key,          -- 'tcs_nqt', 'infosys_se', 'amazon_sde1'
  name        text not null,
  description text
);

create table exam_topic_weights (
  exam_id    text not null references exam_profiles(exam_id) on delete cascade,
  concept_id text not null references concepts(concept_id) on delete cascade,
  weight     numeric not null default 1.0,
  primary key (exam_id, concept_id)
);

alter table profiles
  add column target_exam_id text references exam_profiles(exam_id) on delete set null;

create table study_plans (
  plan_id      uuid primary key default gen_random_uuid(),
  student_id   uuid not null references profiles(student_id) on delete cascade,
  generated_at timestamptz not null default now(),
  horizon_days int not null default 7,
  is_current   boolean not null default true
);
create index on study_plans(student_id, generated_at desc);

create table plan_items (
  plan_item_id      uuid primary key default gen_random_uuid(),
  plan_id           uuid not null references study_plans(plan_id) on delete cascade,
  concept_id        text not null references concepts(concept_id) on delete cascade,
  scheduled_for     date,
  block_index       int,                -- which block of that day
  allocated_minutes int not null,
  position_in_block text check (position_in_block in ('early','middle','late')),
  priority_score    numeric not null,
  reason            jsonb,              -- blame trace, for the "why?" link
  completed_at      timestamptz
);
create index on plan_items(plan_id, scheduled_for);


-- =====================================================================
-- SECTION 5 â€” INLINE BKT UPDATE (fast path)
-- Runs on every attempt so the dashboard reacts immediately.
-- Heavy work (forgetting model, blame, planning) stays in Python.
-- =====================================================================

create or replace function apply_bkt_update()
returns trigger
language plpgsql
as $$
declare
  qc          record;
  p           record;
  prior       numeric;
  guess       numeric;
  slip        numeric;
  posterior   numeric;
  updated     numeric;
begin
  for qc in
    select concept_id, weight from question_concepts
    where question_id = new.question_id
  loop
    select * into p from bkt_params where concept_id = qc.concept_id;
    if not found then
      select 0.15 as p_init, 0.15 as p_transit, 0.10 as p_slip, 0.25 as p_guess
        into p;
    end if;

    select mastery_prob into prior from mastery
      where student_id = new.student_id and concept_id = qc.concept_id;
    if prior is null then prior := p.p_init; end if;

    slip  := p.p_slip;
    guess := p.p_guess;

    -- Confidence modulates the guess rate: a hesitant correct answer
    -- earns less credit, a confident wrong answer costs more.
    if new.confidence = 1 then
      guess := least(0.60, guess * 2.0);
    elsif new.confidence = 3 then
      guess := greatest(0.05, guess * 0.4);
    end if;

    if new.is_correct then
      posterior := (prior * (1 - slip))
                 / nullif(prior * (1 - slip) + (1 - prior) * guess, 0);
    else
      posterior := (prior * slip)
                 / nullif(prior * slip + (1 - prior) * (1 - guess), 0);
    end if;
    posterior := coalesce(posterior, prior);

    -- Learning opportunity, scaled by how central the concept is to the item
    updated := posterior + (1 - posterior) * p.p_transit * qc.weight;
    updated := greatest(0.01, least(0.99, updated));

    insert into mastery (student_id, concept_id, mastery_prob, uncertainty,
                         observation_count, last_review_at, updated_at)
    values (new.student_id, qc.concept_id, updated,
            1.0 / sqrt(2.0), 1, now(), now())
    on conflict (student_id, concept_id) do update
      set mastery_prob      = updated,
          observation_count = mastery.observation_count + 1,
          uncertainty       = 1.0 / sqrt(mastery.observation_count + 2.0),
          last_review_at    = now(),
          updated_at        = now();
  end loop;

  return new;
end;
$$;

create trigger trg_apply_bkt
  after insert on attempts
  for each row execute function apply_bkt_update();


-- =====================================================================
-- SECTION 6 â€” ROW LEVEL SECURITY
-- Content is world-readable to signed-in users.
-- Student data is visible only to its owner.
-- =====================================================================

alter table subjects            enable row level security;
alter table concepts            enable row level security;
alter table prerequisites       enable row level security;
alter table misconceptions      enable row level security;
alter table questions           enable row level security;
alter table question_concepts   enable row level security;
alter table options             enable row level security;
alter table bkt_params          enable row level security;
alter table exam_profiles       enable row level security;
alter table exam_topic_weights  enable row level security;

create policy read_subjects   on subjects           for select to authenticated using (true);
create policy read_concepts   on concepts           for select to authenticated using (true);
create policy read_prereqs    on prerequisites      for select to authenticated using (true);
create policy read_misc       on misconceptions     for select to authenticated using (true);
create policy read_questions  on questions          for select to authenticated using (true);
create policy read_qconcepts  on question_concepts  for select to authenticated using (true);
create policy read_bkt        on bkt_params         for select to authenticated using (true);
create policy read_exams      on exam_profiles      for select to authenticated using (true);
create policy read_exam_w     on exam_topic_weights for select to authenticated using (true);

-- Options are readable, but is_correct must not leak before answering.
-- Serve options to the quiz player through this view instead of the table.
create policy read_options on options for select to authenticated using (true);

create view public.options_for_display as
  select option_id, question_id, body, ordinal from options;


alter table profiles          enable row level security;
alter table attempts          enable row level security;
alter table mastery           enable row level security;
alter table confusion_pairs   enable row level security;
alter table study_sessions    enable row level security;
alter table focus_events      enable row level security;
alter table attention_profile enable row level security;
alter table hourly_performance enable row level security;
alter table study_plans       enable row level security;
alter table plan_items        enable row level security;

create policy own_profile     on profiles           for all to authenticated
  using (student_id = auth.uid()) with check (student_id = auth.uid());
create policy own_attempts    on attempts           for all to authenticated
  using (student_id = auth.uid()) with check (student_id = auth.uid());
create policy own_mastery     on mastery            for all to authenticated
  using (student_id = auth.uid()) with check (student_id = auth.uid());
create policy own_confusion   on confusion_pairs    for all to authenticated
  using (student_id = auth.uid()) with check (student_id = auth.uid());
create policy own_sessions    on study_sessions     for all to authenticated
  using (student_id = auth.uid()) with check (student_id = auth.uid());
create policy own_focus       on focus_events       for all to authenticated
  using (student_id = auth.uid()) with check (student_id = auth.uid());
create policy own_attention   on attention_profile  for all to authenticated
  using (student_id = auth.uid()) with check (student_id = auth.uid());
create policy own_hourly      on hourly_performance for all to authenticated
  using (student_id = auth.uid()) with check (student_id = auth.uid());
create policy own_plans       on study_plans        for all to authenticated
  using (student_id = auth.uid()) with check (student_id = auth.uid());

create policy own_plan_items  on plan_items         for all to authenticated
  using (exists (select 1 from study_plans sp
                 where sp.plan_id = plan_items.plan_id
                   and sp.student_id = auth.uid()));

-- Auto-create a profile row on signup
create or replace function handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (student_id, display_name)
  values (new.id, new.raw_user_meta_data->>'display_name');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();