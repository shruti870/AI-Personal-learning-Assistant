-- =====================================================================
-- 007_content_expansion_2.sql
-- Aptitude and logical reasoning (placement-critical), plus more depth
-- across the existing subjects. +16 concepts, +14 edges,
-- +11 misconceptions, +59 questions, +12 coding problems.
-- Idempotent.
-- =====================================================================

insert into subjects (subject_id, name, description, is_authored) values
  ('apt', 'Quantitative Aptitude', 'Number systems through probability', true),
  ('lr', 'Logical Reasoning', 'Series through data sufficiency', true)
on conflict (subject_id) do nothing;

insert into concepts (concept_id, subject_id, name, level) values
  ('apt.number_system', 'apt', 'Number systems', 0),
  ('apt.percentages', 'apt', 'Percentages', 0),
  ('apt.ratios', 'apt', 'Ratio and proportion', 1),
  ('apt.averages', 'apt', 'Averages', 1),
  ('apt.profit_loss', 'apt', 'Profit and loss', 2),
  ('apt.si_ci', 'apt', 'Simple and compound interest', 2),
  ('apt.time_work', 'apt', 'Time and work', 2),
  ('apt.time_speed', 'apt', 'Time speed distance', 2),
  ('apt.permutations', 'apt', 'Permutations and combinations', 3),
  ('apt.probability', 'apt', 'Probability', 4),
  ('lr.series', 'lr', 'Number and letter series', 0),
  ('lr.coding', 'lr', 'Coding decoding', 1),
  ('lr.blood_relations', 'lr', 'Blood relations', 1),
  ('lr.syllogism', 'lr', 'Syllogisms', 2),
  ('lr.seating', 'lr', 'Seating arrangement', 3),
  ('lr.data_suff', 'lr', 'Data sufficiency', 3)
on conflict (concept_id) do nothing;

insert into prerequisites (parent_id, child_id, weight) values
  ('apt.number_system', 'apt.percentages', 0.6),
  ('apt.percentages', 'apt.ratios', 0.7),
  ('apt.ratios', 'apt.averages', 0.6),
  ('apt.percentages', 'apt.profit_loss', 0.9),
  ('apt.percentages', 'apt.si_ci', 0.85),
  ('apt.ratios', 'apt.time_work', 0.8),
  ('apt.ratios', 'apt.time_speed', 0.8),
  ('apt.number_system', 'apt.permutations', 0.7),
  ('apt.permutations', 'apt.probability', 0.9),
  ('lr.series', 'lr.coding', 0.5),
  ('lr.series', 'lr.blood_relations', 0.4),
  ('lr.coding', 'lr.syllogism', 0.4),
  ('lr.blood_relations', 'lr.seating', 0.6),
  ('lr.syllogism', 'lr.data_suff', 0.6)
on conflict (parent_id, child_id) do nothing;

insert into misconceptions (misconception_id, concept_id, label, remediation_note) values
  ('apt.m01', 'apt.percentages', 'Treats successive percentage changes as additive', '20% up then 20% down is not zero; it is a 4% net loss.'),
  ('apt.m02', 'apt.profit_loss', 'Computes profit percent on selling price', 'Profit percent is always on cost price unless stated otherwise.'),
  ('apt.m03', 'apt.si_ci', 'Applies the simple interest formula to compound problems', 'CI compounds on the accumulated amount, not the principal alone.'),
  ('apt.m04', 'apt.time_work', 'Adds days instead of adding rates', 'Two people finishing in 6 and 12 days work at 1/6 + 1/12 per day.'),
  ('apt.m05', 'apt.time_speed', 'Averages two speeds arithmetically', 'Equal distances need the harmonic mean, not the arithmetic mean.'),
  ('apt.m06', 'apt.permutations', 'Confuses permutation with combination', 'Order matters in a permutation and does not in a combination.'),
  ('apt.m07', 'apt.probability', 'Adds probabilities of non-mutually-exclusive events', 'P(A or B) needs the intersection subtracted.'),
  ('apt.m08', 'apt.averages', 'Averages the averages of unequal groups', 'Weight by group size, or the result is wrong.'),
  ('lr.m01', 'lr.syllogism', 'Accepts a conclusion that only seems plausible', 'Only what follows necessarily from the premises counts.'),
  ('lr.m02', 'lr.blood_relations', 'Assumes gender from a relation word', 'Cousin, child and spouse do not fix gender.'),
  ('lr.m03', 'lr.data_suff', 'Solves the problem instead of testing sufficiency', 'The question is whether the data suffices, not what the answer is.')
on conflict (misconception_id) do nothing;

insert into bkt_params (concept_id, p_init, p_transit, p_slip, p_guess)
select concept_id, 0.15, 0.15, 0.10, 0.25 from concepts
on conflict (concept_id) do nothing;

do $$
declare qid uuid;
begin
  qid := md5('x3-q001')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.percentages', 'A price rises 20% then falls 20%. What is the net change?', 0.2, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.percentages', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q001-o0')::uuid, qid, 'No change', false, 'apt.m01', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q001-o1')::uuid, qid, '4% decrease', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q001-o2')::uuid, qid, '4% increase', false, 'apt.m01', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q001-o3')::uuid, qid, '40% decrease', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q002')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.percentages', 'If 40% of a number is 96, what is the number?', -0.6, 35, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.percentages', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q002-o0')::uuid, qid, '240', true, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q002-o1')::uuid, qid, '38.4', false, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q002-o2')::uuid, qid, '384', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q002-o3')::uuid, qid, '120', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q003')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.percentages', 'A student scores 60 out of 80. What percentage is that?', -1.0, 25, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.percentages', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q003-o0')::uuid, qid, '80%', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q003-o1')::uuid, qid, '75%', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q003-o2')::uuid, qid, '70%', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q003-o3')::uuid, qid, '65%', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q004')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.profit_loss', 'An item costs 400 and sells for 500. What is the profit percent?', -0.3, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.profit_loss', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q004-o0')::uuid, qid, '20%', false, 'apt.m02', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q004-o1')::uuid, qid, '25%', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q004-o2')::uuid, qid, 'ADD 100%', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q004-o3')::uuid, qid, '80%', false, 'apt.m02', 3) on conflict (option_id) do nothing;

  qid := md5('x3-q005')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.profit_loss', 'A shopkeeper sells at 10% loss. If cost is 250, what is the selling price?', -0.2, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.profit_loss', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q005-o0')::uuid, qid, '275', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q005-o1')::uuid, qid, '225', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q005-o2')::uuid, qid, '240', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q005-o3')::uuid, qid, '230', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q006')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.profit_loss', 'Two articles are sold at 1200 each, one at 20% profit and one at 20% loss. What is the net result?', 0.7, 70, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.profit_loss', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q006-o0')::uuid, qid, 'No profit no loss', false, 'apt.m01', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q006-o1')::uuid, qid, 'Loss of 100', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q006-o2')::uuid, qid, 'Profit of 100', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q006-o3')::uuid, qid, 'Loss of 200', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q007')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.si_ci', 'What is the simple interest on 5000 at 8% for 3 years?', -0.5, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.si_ci', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q007-o0')::uuid, qid, '1200', true, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q007-o1')::uuid, qid, '1300', false, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q007-o2')::uuid, qid, '400', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q007-o3')::uuid, qid, '1500', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q008')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.si_ci', 'What is the compound interest on 10000 at 10% for 2 years?', 0.3, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.si_ci', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q008-o0')::uuid, qid, '2000', false, 'apt.m03', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q008-o1')::uuid, qid, '2100', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q008-o2')::uuid, qid, '1000', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q008-o3')::uuid, qid, '2200', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q009')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.si_ci', 'At what rate does a sum double in 8 years under simple interest?', 0.4, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.si_ci', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q009-o0')::uuid, qid, '8%', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q009-o1')::uuid, qid, '12.5%', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q009-o2')::uuid, qid, '10%', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q009-o3')::uuid, qid, '16%', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q010')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.time_work', 'A finishes a job in 6 days, B in 12. Working together, how long?', 0.0, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.time_work', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q010-o0')::uuid, qid, '18 days', false, 'apt.m04', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q010-o1')::uuid, qid, '4 days', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q010-o2')::uuid, qid, '9 days', false, 'apt.m04', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q010-o3')::uuid, qid, '3 days', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q011')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.time_work', '12 workers finish a task in 10 days. How long for 15 workers?', 0.1, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.time_work', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q011-o0')::uuid, qid, '12.5 days', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q011-o1')::uuid, qid, '8 days', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q011-o2')::uuid, qid, '7 days', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q011-o3')::uuid, qid, '6 days', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q012')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.time_speed', 'A car covers half a journey at 40 kmph and half at 60 kmph. What is the average speed?', 0.5, 60, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.time_speed', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q012-o0')::uuid, qid, '50 kmph', false, 'apt.m05', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q012-o1')::uuid, qid, '48 kmph', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q012-o2')::uuid, qid, '45 kmph', false, 'apt.m05', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q012-o3')::uuid, qid, '52 kmph', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q013')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.time_speed', 'A train 200m long crosses a pole in 10 seconds. What is its speed?', 0.1, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.time_speed', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q013-o0')::uuid, qid, '20 m/s', true, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q013-o1')::uuid, qid, '10 m/s', false, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q013-o2')::uuid, qid, '40 m/s', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q013-o3')::uuid, qid, '2 m/s', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q014')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.time_speed', 'Two trains 120m and 180m long move toward each other at 20 and 30 m/s. Time to cross?', 0.6, 65, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.time_speed', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q014-o0')::uuid, qid, '10 s', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q014-o1')::uuid, qid, '6 s', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q014-o2')::uuid, qid, '12 s', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q014-o3')::uuid, qid, '5 s', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q015')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.averages', 'The average of 5 numbers is 20. If one number 30 is removed, what is the new average?', 0.2, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.averages', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q015-o0')::uuid, qid, '20', false, 'apt.m08', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q015-o1')::uuid, qid, '17.5', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q015-o2')::uuid, qid, '15', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q015-o3')::uuid, qid, '22.5', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q016')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.averages', 'Class A has 20 students averaging 60, class B has 30 averaging 70. Combined average?', 0.4, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.averages', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q016-o0')::uuid, qid, '65', false, 'apt.m08', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q016-o1')::uuid, qid, '66', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q016-o2')::uuid, qid, '64', false, 'apt.m08', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q016-o3')::uuid, qid, '68', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q017')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.ratios', 'If a:b = 2:3 and b:c = 4:5, what is a:c?', 0.3, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.ratios', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q017-o0')::uuid, qid, '2:5', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q017-o1')::uuid, qid, '8:15', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q017-o2')::uuid, qid, '6:5', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q017-o3')::uuid, qid, '1:2', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q018')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.ratios', 'Divide 600 between two people in the ratio 2:3. What is the larger share?', -0.4, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.ratios', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q018-o0')::uuid, qid, '240', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q018-o1')::uuid, qid, '360', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q018-o2')::uuid, qid, '300', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q018-o3')::uuid, qid, '400', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q019')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.number_system', 'What is the remainder when 2^10 is divided by 7?', 0.6, 60, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.number_system', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q019-o0')::uuid, qid, '1', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q019-o1')::uuid, qid, '2', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q019-o2')::uuid, qid, '4', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q019-o3')::uuid, qid, '0', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q020')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.number_system', 'How many factors does 36 have?', 0.2, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.number_system', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q020-o0')::uuid, qid, '6', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q020-o1')::uuid, qid, '9', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q020-o2')::uuid, qid, '12', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q020-o3')::uuid, qid, '8', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q021')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.number_system', 'What is the LCM of 12 and 18?', -0.6, 35, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.number_system', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q021-o0')::uuid, qid, '6', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q021-o1')::uuid, qid, '36', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q021-o2')::uuid, qid, '72', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q021-o3')::uuid, qid, '216', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q022')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.permutations', 'How many ways can 5 people be seated in a row?', -0.2, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.permutations', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q022-o0')::uuid, qid, '25', false, 'apt.m06', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q022-o1')::uuid, qid, '120', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q022-o2')::uuid, qid, '5', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q022-o3')::uuid, qid, '10', false, 'apt.m06', 3) on conflict (option_id) do nothing;

  qid := md5('x3-q023')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.permutations', 'How many ways can 3 people be chosen from 8?', 0.2, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.permutations', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q023-o0')::uuid, qid, '336', false, 'apt.m06', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q023-o1')::uuid, qid, '56', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q023-o2')::uuid, qid, '24', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q023-o3')::uuid, qid, '512', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q024')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.permutations', 'How many 3-letter words can be formed from the letters of DELHI without repetition?', 0.4, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.permutations', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q024-o0')::uuid, qid, '10', false, 'apt.m06', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q024-o1')::uuid, qid, '60', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q024-o2')::uuid, qid, '125', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q024-o3')::uuid, qid, '15', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q025')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.probability', 'Two dice are rolled. What is the probability the sum is 7?', 0.3, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.probability', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q025-o0')::uuid, qid, '1/12', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q025-o1')::uuid, qid, '1/6', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q025-o2')::uuid, qid, '7/36', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q025-o3')::uuid, qid, '1/9', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q026')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.probability', 'A card is drawn from a standard deck. P(king or heart)?', 0.5, 60, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.probability', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q026-o0')::uuid, qid, '17/52', false, 'apt.m07', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q026-o1')::uuid, qid, '16/52', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q026-o2')::uuid, qid, '13/52', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q026-o3')::uuid, qid, '4/52', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q027')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'apt.probability', 'A bag has 3 red and 5 blue balls. Two are drawn without replacement. P(both red)?', 0.6, 65, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'apt.probability', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q027-o0')::uuid, qid, '9/64', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q027-o1')::uuid, qid, '3/28', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q027-o2')::uuid, qid, '1/4', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q027-o3')::uuid, qid, '6/56', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q028')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'lr.series', 'What comes next: 2, 6, 12, 20, 30, ?', 0.1, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'lr.series', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q028-o0')::uuid, qid, '40', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q028-o1')::uuid, qid, '42', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q028-o2')::uuid, qid, '36', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q028-o3')::uuid, qid, '44', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q029')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'lr.series', 'What comes next: 1, 4, 9, 16, 25, ?', -0.7, 30, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'lr.series', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q029-o0')::uuid, qid, '30', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q029-o1')::uuid, qid, '36', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q029-o2')::uuid, qid, '35', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q029-o3')::uuid, qid, '49', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q030')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'lr.series', 'What comes next: A, C, F, J, ?', 0.5, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'lr.series', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q030-o0')::uuid, qid, 'M', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q030-o1')::uuid, qid, 'O', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q030-o2')::uuid, qid, 'N', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q030-o3')::uuid, qid, 'P', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q031')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'lr.coding', 'If CAT is coded as DBU, how is DOG coded?', 0.0, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'lr.coding', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q031-o0')::uuid, qid, 'EPH', true, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q031-o1')::uuid, qid, 'CNF', false, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q031-o2')::uuid, qid, 'EPI', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q031-o3')::uuid, qid, 'DPH', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q032')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'lr.coding', 'If MONDAY is 123456, what is DAY?', -0.2, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'lr.coding', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q032-o0')::uuid, qid, '456', true, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q032-o1')::uuid, qid, '465', false, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q032-o2')::uuid, qid, '546', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q032-o3')::uuid, qid, '654', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q033')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'lr.blood_relations', 'Pointing to a man, a woman says "his mother is the only daughter of my mother". How is she related to him?', 0.5, 65, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'lr.blood_relations', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q033-o0')::uuid, qid, 'Sister', false, 'lr.m02', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q033-o1')::uuid, qid, 'Mother', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q033-o2')::uuid, qid, 'Aunt', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q033-o3')::uuid, qid, 'Grandmother', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q034')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'lr.blood_relations', 'A is B brother. B is C mother. What is A to C?', 0.1, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'lr.blood_relations', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q034-o0')::uuid, qid, 'Father', false, 'lr.m02', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q034-o1')::uuid, qid, 'Uncle', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q034-o2')::uuid, qid, 'Brother', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q034-o3')::uuid, qid, 'Cannot be determined', false, 'lr.m02', 3) on conflict (option_id) do nothing;

  qid := md5('x3-q035')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'lr.syllogism', 'All cats are animals. Some animals are wild. Does it follow that some cats are wild?', 0.4, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'lr.syllogism', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q035-o0')::uuid, qid, 'Yes, it follows', false, 'lr.m01', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q035-o1')::uuid, qid, 'No, it does not follow', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q035-o2')::uuid, qid, 'Only if all animals are wild', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q035-o3')::uuid, qid, 'It follows probabilistically', false, 'lr.m01', 3) on conflict (option_id) do nothing;

  qid := md5('x3-q036')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'lr.syllogism', 'All roses are flowers. All flowers need water. Does it follow that all roses need water?', -0.3, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'lr.syllogism', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q036-o0')::uuid, qid, 'No', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q036-o1')::uuid, qid, 'Yes', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q036-o2')::uuid, qid, 'Only some roses', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q036-o3')::uuid, qid, 'Cannot be determined', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q037')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'lr.data_suff', 'Is x greater than 5? (1) x is greater than 3. (2) x squared equals 49.', 0.6, 70, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'lr.data_suff', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q037-o0')::uuid, qid, 'Statement 1 alone is sufficient', false, 'lr.m03', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q037-o1')::uuid, qid, 'Statement 2 alone is sufficient', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q037-o2')::uuid, qid, 'Both together are needed', false, 'lr.m03', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q037-o3')::uuid, qid, 'Neither is sufficient', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q038')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'lr.seating', 'Five people sit in a row. A is at one end, B is next to A. How many positions can C take?', 0.5, 60, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'lr.seating', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q038-o0')::uuid, qid, '2', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q038-o1')::uuid, qid, '3', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q038-o2')::uuid, qid, '4', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q038-o3')::uuid, qid, '1', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q039')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.transactions', 'What does a dirty read mean?', 0.4, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.transactions', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q039-o0')::uuid, qid, 'Reading from a corrupted disk', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q039-o1')::uuid, qid, 'Reading data written by an uncommitted transaction', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q039-o2')::uuid, qid, 'Reading the same row twice', false, 'dbms.m06', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q039-o3')::uuid, qid, 'Reading a deleted row', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q040')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.indexing', 'Which index structure suits range queries best?', 0.4, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.indexing', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q040-o0')::uuid, qid, 'Hash index', false, 'dbms.m07', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q040-o1')::uuid, qid, 'B+ tree index', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q040-o2')::uuid, qid, 'Bitmap index', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q040-o3')::uuid, qid, 'No index', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q041')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.joins', 'What does a CROSS JOIN of a 4-row and 3-row table return?', 0.2, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.joins', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q041-o0')::uuid, qid, '7 rows', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q041-o1')::uuid, qid, '12 rows', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q041-o2')::uuid, qid, '4 rows', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q041-o3')::uuid, qid, '3 rows', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q042')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.keys', 'What does a composite key mean?', -0.2, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.keys', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q042-o0')::uuid, qid, 'A key copied from another table', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q042-o1')::uuid, qid, 'A primary key made of two or more attributes', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q042-o2')::uuid, qid, 'A key that can be null', false, 'dbms.m02', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q042-o3')::uuid, qid, 'An index on two columns', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q043')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.sql_aggregate', 'What does GROUP BY do before HAVING runs?', 0.2, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.sql_aggregate', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q043-o0')::uuid, qid, 'Sorts the rows', false, 'dbms.m09', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q043-o1')::uuid, qid, 'Partitions rows into groups', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q043-o2')::uuid, qid, 'Filters individual rows', false, 'dbms.m09', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q043-o3')::uuid, qid, 'Joins the tables', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q044')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.hashing', 'What does open addressing resolve?', 0.3, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.hashing', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q044-o0')::uuid, qid, 'Slow hashing', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q044-o1')::uuid, qid, 'Collisions, without a separate chain', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q044-o2')::uuid, qid, 'Memory leaks', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q044-o3')::uuid, qid, 'Poor hash functions', false, 'dsa.m08', 3) on conflict (option_id) do nothing;

  qid := md5('x3-q045')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.dp_1d', 'What is the time complexity of the standard 0/1 knapsack DP?', 0.5, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.dp_1d', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q045-o0')::uuid, qid, 'O(n)', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q045-o1')::uuid, qid, 'O(n * W)', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q045-o2')::uuid, qid, 'O(2^n)', false, 'dsa.m10', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q045-o3')::uuid, qid, 'O(n log n)', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q046')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.trees', 'How many nodes at most can a binary tree of height h have?', 0.3, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.trees', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q046-o0')::uuid, qid, '2h', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q046-o1')::uuid, qid, '2^(h+1) - 1', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q046-o2')::uuid, qid, 'h^2', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q046-o3')::uuid, qid, '2^h', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q047')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.bst', 'What does deleting a node with two children in a BST require?', 0.5, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.bst', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q047-o0')::uuid, qid, 'Deleting the whole subtree', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q047-o1')::uuid, qid, 'Replacing it with its in-order successor', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q047-o2')::uuid, qid, 'Replacing it with its parent', false, 'dsa.m11', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q047-o3')::uuid, qid, 'Nothing, BSTs cannot delete', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q048')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.sliding_window', 'What is the time complexity of the fixed-size sliding window maximum using a deque?', 0.6, 60, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.sliding_window', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q048-o0')::uuid, qid, 'O(n*k)', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q048-o1')::uuid, qid, 'O(n)', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q048-o2')::uuid, qid, 'O(n log n)', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q048-o3')::uuid, qid, 'O(k^2)', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q049')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.two_pointers', 'In the container-with-most-water problem, which pointer should move?', 0.6, 60, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.two_pointers', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q049-o0')::uuid, qid, 'Always the left pointer', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q049-o1')::uuid, qid, 'The one at the shorter line', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q049-o2')::uuid, qid, 'Always the right pointer', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q049-o3')::uuid, qid, 'Both simultaneously', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q050')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.http', 'What is the main improvement of HTTP/2 over HTTP/1.1?', 0.4, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.http', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q050-o0')::uuid, qid, 'Encryption by default', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q050-o1')::uuid, qid, 'Multiplexing over one connection', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q050-o2')::uuid, qid, 'Statefulness', false, 'cn.m08', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q050-o3')::uuid, qid, 'Larger headers', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q051')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.tcp_basics', 'What is the purpose of the TCP sequence number?', 0.2, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.tcp_basics', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q051-o0')::uuid, qid, 'Identify the sender', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q051-o1')::uuid, qid, 'Order bytes and detect loss', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q051-o2')::uuid, qid, 'Encrypt the payload', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q051-o3')::uuid, qid, 'Select the port', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q052')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.routing', 'What is the difference between a router and a switch?', 0.1, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.routing', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q052-o0')::uuid, qid, 'None, they are the same', false, 'cn.m06', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q052-o1')::uuid, qid, 'A router forwards between networks; a switch within one', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q052-o2')::uuid, qid, 'A switch is faster only', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q052-o3')::uuid, qid, 'A router works at layer 2', false, 'cn.m06', 3) on conflict (option_id) do nothing;

  qid := md5('x3-q053')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.dns', 'What is DNS recursion?', 0.5, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.dns', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q053-o0')::uuid, qid, 'A domain pointing to itself', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q053-o1')::uuid, qid, 'A resolver querying other servers on the client behalf', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q053-o2')::uuid, qid, 'Caching a record twice', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q053-o3')::uuid, qid, 'A loop in the zone file', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q054')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.subnetting', 'How many /28 subnets fit inside a /24?', 0.6, 65, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.subnetting', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q054-o0')::uuid, qid, '4', false, 'cn.m01', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q054-o1')::uuid, qid, '16', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q054-o2')::uuid, qid, '8', false, 'cn.m01', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q054-o3')::uuid, qid, '32', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q055')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.scheduling', 'What is convoy effect in FCFS scheduling?', 0.5, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.scheduling', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q055-o0')::uuid, qid, 'Processes arriving together', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q055-o1')::uuid, qid, 'Short processes waiting behind one long process', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q055-o2')::uuid, qid, 'Deadlock between two processes', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q055-o3')::uuid, qid, 'Excessive context switching', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q056')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.sync', 'What problem does the producer-consumer pattern illustrate?', 0.3, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.sync', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q056-o0')::uuid, qid, 'CPU scheduling', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q056-o1')::uuid, qid, 'Bounded-buffer synchronization', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q056-o2')::uuid, qid, 'Memory paging', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q056-o3')::uuid, qid, 'Disk scheduling', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q057')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.memory', 'What is the difference between internal and external fragmentation?', 0.4, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.memory', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q057-o0')::uuid, qid, 'They are the same', false, 'os.m05', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q057-o1')::uuid, qid, 'Internal is unused space inside an allocation; external is between them', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q057-o2')::uuid, qid, 'Internal happens only in segmentation', false, 'os.m05', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q057-o3')::uuid, qid, 'External occurs only with paging', false, 'os.m05', 3) on conflict (option_id) do nothing;

  qid := md5('x3-q058')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.filesystem', 'What is a hard link?', 0.4, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.filesystem', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q058-o0')::uuid, qid, 'A shortcut file containing a path', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q058-o1')::uuid, qid, 'A second directory entry pointing at the same inode', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q058-o2')::uuid, qid, 'A backup copy', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q058-o3')::uuid, qid, 'A symbolic reference across filesystems', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x3-q059')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.process', 'What does fork() return in the child process?', 0.3, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.process', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q059-o0')::uuid, qid, 'The child PID', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q059-o1')::uuid, qid, 'Zero', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q059-o2')::uuid, qid, 'Negative one', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x3-q059-o3')::uuid, qid, 'The parent PID', false, null, 3) on conflict (option_id) do nothing;

end $$;

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, signature, language, language_label) values
  ('cp.fizzbuzz', 'apt.number_system', 'FizzBuzz Count', 'Return how many numbers from 1 to n are divisible by 3 or 5.', E'int solve(int n) {
    // your code here
}', -0.7, 'ints->int', 'cpp', 'C++')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.fizzbuzz', '[15]', '7', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.fizzbuzz' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.fizzbuzz', '[1]', '0', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.fizzbuzz' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.fizzbuzz', '[100]', '47', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.fizzbuzz' and ordinal=2);
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.fizzbuzz', 'cpp', 'C++', E'int solve(int n) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.fizzbuzz')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.fizzbuzz', 'java', 'Java', E'static int solve(int n) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.fizzbuzz')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.fizzbuzz', 'python', 'Python', E'def solve(n):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.fizzbuzz')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, signature, language, language_label) values
  ('cp.gcd', 'apt.number_system', 'Greatest Common Divisor', 'Return the GCD of a and b using the Euclidean algorithm.', E'int solve(int a, int b) {
    // your code here
}', -0.4, 'int,int->int', 'cpp', 'C++')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.gcd', '[12,18]', '6', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.gcd' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.gcd', '[7,13]', '1', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.gcd' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.gcd', '[100,75]', '25', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.gcd' and ordinal=2);
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.gcd', 'cpp', 'C++', E'int solve(int a, int b) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.gcd')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.gcd', 'java', 'Java', E'static int solve(int a, int b) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.gcd')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.gcd', 'python', 'Python', E'def solve(a, b):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.gcd')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, signature, language, language_label) values
  ('cp.prime_count', 'apt.number_system', 'Count Primes', 'Return how many primes are strictly less than n. Sieve of Eratosthenes runs in O(n log log n).', E'int solve(int n) {
    // your code here
}', 0.3, 'int->int', 'cpp', 'C++')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.prime_count', '[10]', '4', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.prime_count' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.prime_count', '[2]', '0', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.prime_count' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.prime_count', '[100]', '25', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.prime_count' and ordinal=2);
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.prime_count', 'cpp', 'C++', E'int solve(int n) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.prime_count')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.prime_count', 'java', 'Java', E'static int solve(int n) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.prime_count')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.prime_count', 'python', 'Python', E'def solve(n):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.prime_count')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, signature, language, language_label) values
  ('cp.second_largest', 'dsa.arrays', 'Second Largest', 'Return the second largest distinct value in nums, or -1 if there is none.', E'int solve(vector<int>& nums) {
    // your code here
}', -0.2, 'ints->int', 'cpp', 'C++')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.second_largest', '[[3,1,4,1,5]]', '4', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.second_largest' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.second_largest', '[[2,2]]', '-1', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.second_largest' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.second_largest', '[[9,8,7]]', '8', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.second_largest' and ordinal=2);
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.second_largest', 'cpp', 'C++', E'int solve(vector<int>& nums) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.second_largest')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.second_largest', 'java', 'Java', E'static int solve(int[] nums) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.second_largest')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.second_largest', 'python', 'Python', E'def solve(nums):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.second_largest')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, signature, language, language_label) values
  ('cp.rotate_array', 'dsa.arrays', 'Rotate Array', 'Rotate nums right by k steps and return it.', E'vector<int> solve(vector<int>& nums, int k) {
    // your code here
}', 0.2, 'ints,int->ints', 'cpp', 'C++')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.rotate_array', '[[1,2,3,4,5],2]', '[4,5,1,2,3]', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.rotate_array' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.rotate_array', '[[1],3]', '[1]', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.rotate_array' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.rotate_array', '[[1,2],1]', '[2,1]', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.rotate_array' and ordinal=2);
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.rotate_array', 'cpp', 'C++', E'vector<int> solve(vector<int>& nums, int k) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.rotate_array')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.rotate_array', 'java', 'Java', E'static int[] solve(int[] nums, int k) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.rotate_array')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.rotate_array', 'python', 'Python', E'def solve(nums, k):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.rotate_array')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, signature, language, language_label) values
  ('cp.majority', 'dsa.hashing', 'Majority Element', 'Return the element appearing more than n/2 times. It is guaranteed to exist.', E'int solve(vector<int>& nums) {
    // your code here
}', 0.1, 'ints->int', 'cpp', 'C++')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.majority', '[[3,2,3]]', '3', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.majority' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.majority', '[[1]]', '1', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.majority' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.majority', '[[2,2,1,1,1,2,2]]', '2', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.majority' and ordinal=2);
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.majority', 'cpp', 'C++', E'int solve(vector<int>& nums) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.majority')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.majority', 'java', 'Java', E'static int solve(int[] nums) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.majority')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.majority', 'python', 'Python', E'def solve(nums):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.majority')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, signature, language, language_label) values
  ('cp.anagram', 'dsa.hashing', 'Valid Anagram', 'Return true if t is an anagram of s.', E'bool solve(string& s, string& t) {
    // your code here
}', -0.3, 'str,str->bool', 'cpp', 'C++')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.anagram', '["anagram","nagaram"]', 'true', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.anagram' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.anagram', '["rat","car"]', 'false', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.anagram' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.anagram', '["a","a"]', 'true', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.anagram' and ordinal=2);
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.anagram', 'cpp', 'C++', E'bool solve(string& s, string& t) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.anagram')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.anagram', 'java', 'Java', E'static boolean solve(String s, String t) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.anagram')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.anagram', 'python', 'Python', E'def solve(s, t):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.anagram')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, signature, language, language_label) values
  ('cp.longest_unique', 'dsa.sliding_window', 'Longest Unique Substring', 'Return the length of the longest substring without repeating characters.', E'int solve(string& s) {
    // your code here
}', 0.5, 'str->int', 'cpp', 'C++')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.longest_unique', '["abcabcbb"]', '3', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.longest_unique' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.longest_unique', '["bbbbb"]', '1', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.longest_unique' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.longest_unique', '["pwwkew"]', '3', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.longest_unique' and ordinal=2);
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.longest_unique', 'cpp', 'C++', E'int solve(string& s) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.longest_unique')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.longest_unique', 'java', 'Java', E'static int solve(String s) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.longest_unique')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.longest_unique', 'python', 'Python', E'def solve(s):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.longest_unique')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, signature, language, language_label) values
  ('cp.climb_stairs', 'dsa.dp_1d', 'Climbing Stairs', 'You can climb 1 or 2 steps at a time. Return the number of distinct ways to reach step n.', E'int solve(int n) {
    // your code here
}', 0.0, 'int->int', 'cpp', 'C++')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.climb_stairs', '[3]', '3', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.climb_stairs' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.climb_stairs', '[1]', '1', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.climb_stairs' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.climb_stairs', '[10]', '89', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.climb_stairs' and ordinal=2);
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.climb_stairs', 'cpp', 'C++', E'int solve(int n) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.climb_stairs')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.climb_stairs', 'java', 'Java', E'static int solve(int n) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.climb_stairs')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.climb_stairs', 'python', 'Python', E'def solve(n):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.climb_stairs')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, signature, language, language_label) values
  ('cp.coin_change', 'dsa.dp_1d', 'Coin Change', 'Return the fewest coins summing to amount, or -1 if impossible.', E'int solve(vector<int>& coins, int amount) {
    // your code here
}', 0.7, 'ints,int->int', 'cpp', 'C++')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.coin_change', '[[1,2,5],11]', '3', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.coin_change' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.coin_change', '[[2],3]', '-1', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.coin_change' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.coin_change', '[[1],0]', '0', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.coin_change' and ordinal=2);
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.coin_change', 'cpp', 'C++', E'int solve(vector<int>& coins, int amount) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.coin_change')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.coin_change', 'java', 'Java', E'static int solve(int[] coins, int amount) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.coin_change')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.coin_change', 'python', 'Python', E'def solve(coins, amount):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.coin_change')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, signature, language, language_label) values
  ('cp.matrix_spiral', 'dsa.arrays', 'Row Sums', 'Given a flat array representing an n by n matrix in row-major order, return the sum of each row.', E'vector<int> solve(vector<int>& flat, int n) {
    // your code here
}', 0.3, 'ints,int->ints', 'cpp', 'C++')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.matrix_spiral', '[[1,2,3,4],2]', '[3,7]', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.matrix_spiral' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.matrix_spiral', '[[5],1]', '[5]', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.matrix_spiral' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.matrix_spiral', '[[1,1,1,1,1,1,1,1,1],3]', '[3,3,3]', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.matrix_spiral' and ordinal=2);
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.matrix_spiral', 'cpp', 'C++', E'vector<int> solve(vector<int>& flat, int n) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.matrix_spiral')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.matrix_spiral', 'java', 'Java', E'static int[] solve(int[] flat, int n) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.matrix_spiral')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.matrix_spiral', 'python', 'Python', E'def solve(flat, n):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.matrix_spiral')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, signature, language, language_label) values
  ('cp.balanced_split', 'dsa.two_pointers', 'Equilibrium Index', 'Return the smallest index where the sum of elements to the left equals the sum to the right, or -1.', E'int solve(vector<int>& nums) {
    // your code here
}', 0.4, 'ints->int', 'cpp', 'C++')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.balanced_split', '[[1,7,3,6,5,6]]', '3', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.balanced_split' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.balanced_split', '[[1,2,3]]', '-1', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.balanced_split' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.balanced_split', '[[1]]', '0', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.balanced_split' and ordinal=2);
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.balanced_split', 'cpp', 'C++', E'int solve(vector<int>& nums) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.balanced_split')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.balanced_split', 'java', 'Java', E'static int solve(int[] nums) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.balanced_split')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.balanced_split', 'python', 'Python', E'def solve(nums):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.balanced_split')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code;