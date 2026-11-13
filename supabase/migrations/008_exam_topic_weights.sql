-- =====================================================================
-- 008 - Exam topic weights
--
-- exam_profiles has existed since 002, but exam_topic_weights was never
-- seeded, so choosing a target exam in Settings changed nothing: the
-- planner falls back to weight 1.0 for every concept.
--
-- Weights are set per SUBJECT and fanned out to every concept in it, so new
-- concepts pick up their exam weight when this migration is re-run. 1.0 is
-- neutral; above 1.0 the planner prioritises the subject, below 1.0 it
-- de-prioritises it. They are an approximation of each exam's published
-- pattern, not official numbers.
--
-- Basis (checked 2026-11-12):
--   TCS NQT      Foundation section = numerical, verbal, reasoning; Advanced
--                section = advanced aptitude + coding. Aptitude and reasoning
--                dominate, coding second, CS theory light.
--                (faceprep.in, prepinsta.com, newleafins.org 2026 pattern pages)
--   Infosys SE   Same shape as TCS NQT, reasoning weighted more heavily.
--   Amazon SDE-1 Online assessment is DSA coding; interviews add CS
--                fundamentals (OS, DBMS, networks). Aptitude barely tested.
--
-- Safe to re-run: upserts.
-- =====================================================================

with subject_weights (exam_id, subject_id, weight) as (
  values
    ('tcs_nqt',     'apt',  1.5),
    ('tcs_nqt',     'lr',   1.5),
    ('tcs_nqt',     'dsa',  1.0),
    ('tcs_nqt',     'dbms', 0.6),
    ('tcs_nqt',     'os',   0.5),
    ('tcs_nqt',     'cn',   0.5),

    ('infosys_se',  'apt',  1.3),
    ('infosys_se',  'lr',   1.6),
    ('infosys_se',  'dsa',  1.0),
    ('infosys_se',  'dbms', 0.7),
    ('infosys_se',  'os',   0.5),
    ('infosys_se',  'cn',   0.5),

    ('amazon_sde1', 'dsa',  1.8),
    ('amazon_sde1', 'os',   0.8),
    ('amazon_sde1', 'dbms', 0.8),
    ('amazon_sde1', 'cn',   0.6),
    ('amazon_sde1', 'apt',  0.3),
    ('amazon_sde1', 'lr',   0.3)
)
insert into exam_topic_weights (exam_id, concept_id, weight)
select sw.exam_id, c.concept_id, sw.weight
  from subject_weights sw
  join concepts c on c.subject_id = sw.subject_id
  join exam_profiles e on e.exam_id = sw.exam_id
on conflict (exam_id, concept_id) do update set weight = excluded.weight;

-- Read access already granted by read_exam_w / read_exams in 001.
