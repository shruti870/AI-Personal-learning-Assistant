-- =====================================================================
-- 002_seed_starter_content.sql
-- 16 concepts, 18 DAG edges, 12 misconceptions, 20 tagged questions.
-- Enough to run a real placement test before the full bank exists.
-- Safe to re-run: every insert is idempotent.
-- =====================================================================

insert into subjects (subject_id, name, description, is_authored) values
  ('dbms', 'Database Management Systems', 'Relational model through normalization', true),
  ('dsa', 'Data Structures and Algorithms', 'Arrays through shortest paths', true)
on conflict (subject_id) do nothing;

insert into concepts (concept_id, subject_id, name, level) values
  ('dbms.relational_model', 'dbms', 'Relational model', 0),
  ('dbms.keys', 'dbms', 'Keys', 1),
  ('dbms.functional_dependency', 'dbms', 'Functional dependency', 2),
  ('dbms.normalization_2nf', 'dbms', 'Second normal form', 3),
  ('dbms.normalization_3nf', 'dbms', 'Third normal form', 4),
  ('dbms.joins', 'dbms', 'SQL joins', 2),
  ('dsa.arrays', 'dsa', 'Arrays and indexing', 0),
  ('dsa.complexity', 'dsa', 'Time complexity', 0),
  ('dsa.sorting', 'dsa', 'Sorting basics', 1),
  ('dsa.recursion', 'dsa', 'Recursion', 1),
  ('dsa.binary_search', 'dsa', 'Binary search', 2),
  ('dsa.heaps', 'dsa', 'Heaps and priority queues', 2),
  ('dsa.graph_repr', 'dsa', 'Graph representation', 2),
  ('dsa.bfs', 'dsa', 'BFS', 3),
  ('dsa.dfs', 'dsa', 'DFS', 3),
  ('dsa.dijkstra', 'dsa', 'Dijkstra', 4)
on conflict (concept_id) do nothing;

insert into prerequisites (parent_id, child_id, weight) values
  ('dbms.relational_model', 'dbms.keys', 0.9),
  ('dbms.keys', 'dbms.functional_dependency', 0.8),
  ('dbms.keys', 'dbms.joins', 0.7),
  ('dbms.functional_dependency', 'dbms.normalization_2nf', 0.9),
  ('dbms.normalization_2nf', 'dbms.normalization_3nf', 0.9),
  ('dbms.functional_dependency', 'dbms.normalization_3nf', 0.7),
  ('dsa.arrays', 'dsa.sorting', 0.8),
  ('dsa.complexity', 'dsa.sorting', 0.7),
  ('dsa.arrays', 'dsa.binary_search', 0.6),
  ('dsa.sorting', 'dsa.binary_search', 0.8),
  ('dsa.sorting', 'dsa.heaps', 0.85),
  ('dsa.arrays', 'dsa.graph_repr', 0.6),
  ('dsa.recursion', 'dsa.dfs', 0.9),
  ('dsa.graph_repr', 'dsa.bfs', 0.8),
  ('dsa.graph_repr', 'dsa.dfs', 0.8),
  ('dsa.heaps', 'dsa.dijkstra', 0.9),
  ('dsa.bfs', 'dsa.dijkstra', 0.7),
  ('dsa.graph_repr', 'dsa.dijkstra', 0.6)
on conflict (parent_id, child_id) do nothing;

insert into misconceptions (misconception_id, concept_id, label, remediation_note) values
  ('dbms.m01', 'dbms.keys', 'Believes a foreign key must be unique', 'Show a one-to-many example where the FK repeats across many rows.'),
  ('dbms.m02', 'dbms.keys', 'Treats primary and candidate key as interchangeable', 'A relation may have several candidate keys; exactly one is chosen as primary.'),
  ('dbms.m03', 'dbms.normalization_3nf', 'Confuses transitive with partial dependency', 'Partial needs a composite key. Transitive works through a non-key attribute.'),
  ('dbms.m04', 'dbms.normalization_2nf', 'Thinks 2NF applies with a single-attribute key', 'With an atomic key there is no proper subset, so 2NF cannot be violated.'),
  ('dbms.m05', 'dbms.joins', 'Expects LEFT JOIN to drop unmatched left rows', 'LEFT JOIN keeps every left row and pads the right side with NULL.'),
  ('dsa.m01', 'dsa.complexity', 'Reads nested loops as automatically quadratic', 'The inner bound matters. A halving inner loop gives n log n, not n squared.'),
  ('dsa.m02', 'dsa.heaps', 'Assumes heapify is repeated insertion', 'Bottom-up heapify is O(n); n successive insertions is O(n log n).'),
  ('dsa.m03', 'dsa.binary_search', 'Forgets the sorted-input precondition', 'Binary search on unsorted data is not slow, it is wrong.'),
  ('dsa.m04', 'dsa.bfs', 'Uses a stack for BFS', 'BFS needs FIFO. A stack turns it into DFS.'),
  ('dsa.m05', 'dsa.dijkstra', 'Believes Dijkstra handles negative weights', 'Once a node is settled it is never revisited, which negative edges break.'),
  ('dsa.m06', 'dsa.sorting', 'Thinks quicksort is always O(n log n)', 'Worst case is quadratic when pivots split badly.'),
  ('dsa.m07', 'dsa.recursion', 'Omits the base case from the cost', 'Every recursive call must reduce toward a terminating case.')
on conflict (misconception_id) do nothing;

-- Default BKT parameters. The Python service refits these once data exists.
insert into bkt_params (concept_id, p_init, p_transit, p_slip, p_guess)
select concept_id, 0.15, 0.15, 0.10, 0.25 from concepts
on conflict (concept_id) do nothing;

-- Questions and options. Deterministic UUIDs so re-running does not duplicate.
do $$
declare qid uuid;
begin
  qid := md5('seed-q001')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.keys', 'Which of the following may contain duplicate values in a relation?', -0.8, 40, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.keys', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q001-o0')::uuid, qid, 'Primary key', false, 'dbms.m02', 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q001-o1')::uuid, qid, 'Foreign key', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q001-o2')::uuid, qid, 'Candidate key', false, 'dbms.m02', 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q001-o3')::uuid, qid, 'Super key', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q002')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.keys', 'A relation has candidate keys {A} and {B, C}. How many primary keys does it have?', -0.3, 45, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.keys', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q002-o0')::uuid, qid, 'Two', false, 'dbms.m02', 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q002-o1')::uuid, qid, 'One', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q002-o2')::uuid, qid, 'Three', false, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q002-o3')::uuid, qid, 'None until declared', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q003')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.functional_dependency', 'Given A -> B and B -> C, which dependency follows by transitivity?', -0.5, 40, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.functional_dependency', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q003-o0')::uuid, qid, 'B -> A', false, null, 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q003-o1')::uuid, qid, 'A -> C', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q003-o2')::uuid, qid, 'C -> A', false, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q003-o3')::uuid, qid, 'AC -> B', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q004')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.normalization_2nf', 'R(A, B, C) has the single candidate key A. Can R violate 2NF?', 0.4, 55, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.normalization_2nf', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q004-o0')::uuid, qid, 'Yes, if A -> B -> C', false, 'dbms.m04', 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q004-o1')::uuid, qid, 'No, an atomic key has no proper subset', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q004-o2')::uuid, qid, 'Yes, whenever a non-key attribute exists', false, 'dbms.m04', 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q004-o3')::uuid, qid, 'Only if C is multivalued', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q005')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.normalization_3nf', 'R(A, B, C) has A as the only candidate key, with A -> B and B -> C. Which normal form does R violate?', 0.3, 55, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.normalization_3nf', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q005-o0')::uuid, qid, 'First normal form', false, null, 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q005-o1')::uuid, qid, 'Second normal form', false, 'dbms.m03', 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q005-o2')::uuid, qid, 'Third normal form', true, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q005-o3')::uuid, qid, 'No violation', false, 'dbms.m03', 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q006')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.normalization_3nf', 'Which condition is required for a transitive dependency to exist?', 0.5, 50, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.normalization_3nf', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q006-o0')::uuid, qid, 'A composite primary key', false, 'dbms.m03', 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q006-o1')::uuid, qid, 'A non-key attribute determining another non-key attribute', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q006-o2')::uuid, qid, 'A multivalued attribute', false, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q006-o3')::uuid, qid, 'At least two relations', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q007')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.joins', 'Table A has 5 rows, table B has 3, and only 2 rows match on the join key. How many rows does A LEFT JOIN B return?', 0.0, 50, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.joins', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q007-o0')::uuid, qid, '2', false, 'dbms.m05', 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q007-o1')::uuid, qid, '5', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q007-o2')::uuid, qid, '3', false, 'dbms.m05', 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q007-o3')::uuid, qid, '15', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q008')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.joins', 'Which join returns only rows present in both tables?', -0.9, 30, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.joins', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q008-o0')::uuid, qid, 'LEFT JOIN', false, 'dbms.m05', 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q008-o1')::uuid, qid, 'INNER JOIN', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q008-o2')::uuid, qid, 'FULL OUTER JOIN', false, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q008-o3')::uuid, qid, 'CROSS JOIN', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q009')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.relational_model', 'In the relational model, what does a tuple correspond to?', -1.0, 30, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.relational_model', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q009-o0')::uuid, qid, 'A column', false, null, 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q009-o1')::uuid, qid, 'A row', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q009-o2')::uuid, qid, 'A table', false, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q009-o3')::uuid, qid, 'A constraint', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q010')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.complexity', 'for (i=0;i<n;i++) for (j=1;j<n;j*=2) â€” what is the time complexity?', 0.2, 50, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.complexity', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q010-o0')::uuid, qid, 'O(n^2)', false, 'dsa.m01', 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q010-o1')::uuid, qid, 'O(n log n)', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q010-o2')::uuid, qid, 'O(n)', false, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q010-o3')::uuid, qid, 'O(log n)', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q011')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.complexity', 'What is the time complexity of accessing an element by index in an array?', -1.1, 25, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.complexity', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q011-o0')::uuid, qid, 'O(n)', false, null, 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q011-o1')::uuid, qid, 'O(1)', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q011-o2')::uuid, qid, 'O(log n)', false, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q011-o3')::uuid, qid, 'O(n log n)', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q012')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.sorting', 'What is the worst-case time complexity of quicksort?', -0.2, 35, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.sorting', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q012-o0')::uuid, qid, 'O(n log n)', false, 'dsa.m06', 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q012-o1')::uuid, qid, 'O(n^2)', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q012-o2')::uuid, qid, 'O(n)', false, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q012-o3')::uuid, qid, 'O(log n)', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q013')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.sorting', 'Which sorting algorithm guarantees O(n log n) in the worst case?', -0.1, 35, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.sorting', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q013-o0')::uuid, qid, 'Quicksort', false, 'dsa.m06', 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q013-o1')::uuid, qid, 'Merge sort', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q013-o2')::uuid, qid, 'Insertion sort', false, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q013-o3')::uuid, qid, 'Bubble sort', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q014')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.heaps', 'What is the time complexity of building a heap from an unsorted array of n elements?', 0.6, 45, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.heaps', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q014-o0')::uuid, qid, 'O(n log n)', false, 'dsa.m02', 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q014-o1')::uuid, qid, 'O(n)', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q014-o2')::uuid, qid, 'O(log n)', false, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q014-o3')::uuid, qid, 'O(n^2)', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q015')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.heaps', 'What does peek() return on a min-heap?', -0.9, 25, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.heaps', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q015-o0')::uuid, qid, 'The largest element', false, null, 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q015-o1')::uuid, qid, 'The smallest element', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q015-o2')::uuid, qid, 'The median element', false, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q015-o3')::uuid, qid, 'The most recently inserted element', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q016')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.binary_search', 'Binary search is run on an unsorted array. What happens?', -0.4, 40, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.binary_search', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q016-o0')::uuid, qid, 'It still works, just slower', false, 'dsa.m03', 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q016-o1')::uuid, qid, 'It may return a wrong result', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q016-o2')::uuid, qid, 'It throws an error', false, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q016-o3')::uuid, qid, 'It degrades to O(n)', false, 'dsa.m03', 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q017')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.bfs', 'Which data structure does BFS use to hold the frontier?', -0.6, 30, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.bfs', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q017-o0')::uuid, qid, 'Stack', false, 'dsa.m04', 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q017-o1')::uuid, qid, 'Queue', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q017-o2')::uuid, qid, 'Priority queue', false, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q017-o3')::uuid, qid, 'Hash set', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q018')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.dfs', 'Recursive DFS implicitly uses which structure?', -0.3, 35, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.dfs', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q018-o0')::uuid, qid, 'The heap', false, null, 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q018-o1')::uuid, qid, 'The call stack', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q018-o2')::uuid, qid, 'A queue', false, 'dsa.m04', 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q018-o3')::uuid, qid, 'A set', false, null, 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q019')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.dijkstra', 'Why does Dijkstra fail on graphs with negative edge weights?', 0.7, 60, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.dijkstra', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q019-o0')::uuid, qid, 'It cannot represent negative numbers', false, 'dsa.m05', 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q019-o1')::uuid, qid, 'A settled node is never revisited, so a later cheaper path is missed', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q019-o2')::uuid, qid, 'The priority queue overflows', false, null, 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q019-o3')::uuid, qid, 'It does not fail; it is simply slower', false, 'dsa.m05', 3)
  on conflict (option_id) do nothing;

  qid := md5('seed-q020')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.recursion', 'What happens when a recursive function has no reachable base case?', -0.7, 30, 'authored')
  on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.recursion', 1.0)
  on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q020-o0')::uuid, qid, 'It returns zero', false, 'dsa.m07', 0)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q020-o1')::uuid, qid, 'It recurses until the stack overflows', true, null, 1)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q020-o2')::uuid, qid, 'The compiler rejects it', false, 'dsa.m07', 2)
  on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('seed-q020-o3')::uuid, qid, 'It runs in constant time', false, null, 3)
  on conflict (option_id) do nothing;

end $$;

insert into exam_profiles (exam_id, name, description) values
  ('tcs_nqt', 'TCS NQT', 'National Qualifier Test'),
  ('infosys_se', 'Infosys SE', 'Systems Engineer'),
  ('amazon_sde1', 'Amazon SDE-1', 'Software Development Engineer I')
on conflict (exam_id) do nothing;