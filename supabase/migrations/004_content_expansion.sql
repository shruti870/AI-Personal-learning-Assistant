-- =====================================================================
-- 004_content_expansion.sql
-- Fixes literal \n in starter_code (Postgres needs E-strings), adds a
-- language column, and expands the bank:
--   +32 concepts, +32 edges, +23 misconceptions,
--   +53 questions, +9 coding problems.
-- Idempotent: safe to re-run.
-- =====================================================================

insert into subjects (subject_id, name, description, is_authored) values
  ('cn', 'Computer Networks', 'OSI model through HTTP', true),
  ('os', 'Operating Systems', 'Processes through file systems', true)
on conflict (subject_id) do nothing;

insert into concepts (concept_id, subject_id, name, level) values
  ('cn.osi_model', 'cn', 'OSI model', 0),
  ('cn.ip_addressing', 'cn', 'IP addressing', 0),
  ('cn.subnetting', 'cn', 'Subnetting', 1),
  ('cn.switching', 'cn', 'Switching and MAC', 1),
  ('cn.routing', 'cn', 'Routing basics', 2),
  ('cn.transport', 'cn', 'Transport layer', 1),
  ('cn.tcp_basics', 'cn', 'TCP fundamentals', 2),
  ('cn.udp', 'cn', 'UDP', 2),
  ('cn.tcp_flow', 'cn', 'TCP flow control', 3),
  ('cn.tcp_congestion', 'cn', 'TCP congestion control', 3),
  ('cn.dns', 'cn', 'DNS', 2),
  ('cn.http', 'cn', 'HTTP', 3),
  ('os.process', 'os', 'Processes', 0),
  ('os.thread', 'os', 'Threads', 1),
  ('os.scheduling', 'os', 'CPU scheduling', 2),
  ('os.sync', 'os', 'Synchronization', 2),
  ('os.deadlock', 'os', 'Deadlock', 3),
  ('os.memory', 'os', 'Memory management', 1),
  ('os.paging', 'os', 'Paging', 2),
  ('os.virtual_memory', 'os', 'Virtual memory', 3),
  ('os.page_replacement', 'os', 'Page replacement', 4),
  ('os.filesystem', 'os', 'File systems', 2),
  ('dsa.hashing', 'dsa', 'Hashing', 1),
  ('dsa.two_pointers', 'dsa', 'Two pointers', 2),
  ('dsa.sliding_window', 'dsa', 'Sliding window', 3),
  ('dsa.dp_1d', 'dsa', 'Dynamic programming (1D)', 4),
  ('dsa.trees', 'dsa', 'Trees', 3),
  ('dsa.bst', 'dsa', 'Binary search trees', 4),
  ('dbms.transactions', 'dbms', 'Transactions and ACID', 3),
  ('dbms.indexing', 'dbms', 'Indexing', 3),
  ('dbms.bcnf', 'dbms', 'BCNF', 5),
  ('dbms.sql_aggregate', 'dbms', 'SQL aggregation', 2)
on conflict (concept_id) do nothing;

insert into prerequisites (parent_id, child_id, weight) values
  ('cn.osi_model', 'cn.transport', 0.8),
  ('cn.ip_addressing', 'cn.subnetting', 0.9),
  ('cn.ip_addressing', 'cn.routing', 0.8),
  ('cn.osi_model', 'cn.switching', 0.6),
  ('cn.switching', 'cn.routing', 0.6),
  ('cn.transport', 'cn.tcp_basics', 0.9),
  ('cn.transport', 'cn.udp', 0.8),
  ('cn.tcp_basics', 'cn.tcp_flow', 0.9),
  ('cn.tcp_flow', 'cn.tcp_congestion', 0.85),
  ('cn.tcp_basics', 'cn.tcp_congestion', 0.7),
  ('cn.ip_addressing', 'cn.dns', 0.6),
  ('cn.tcp_basics', 'cn.http', 0.7),
  ('cn.dns', 'cn.http', 0.5),
  ('os.process', 'os.thread', 0.9),
  ('os.process', 'os.scheduling', 0.8),
  ('os.thread', 'os.sync', 0.9),
  ('os.sync', 'os.deadlock', 0.85),
  ('os.memory', 'os.paging', 0.9),
  ('os.paging', 'os.virtual_memory', 0.9),
  ('os.virtual_memory', 'os.page_replacement', 0.9),
  ('os.memory', 'os.filesystem', 0.5),
  ('dsa.arrays', 'dsa.hashing', 0.7),
  ('dsa.arrays', 'dsa.two_pointers', 0.8),
  ('dsa.two_pointers', 'dsa.sliding_window', 0.85),
  ('dsa.recursion', 'dsa.dp_1d', 0.85),
  ('dsa.recursion', 'dsa.trees', 0.8),
  ('dsa.trees', 'dsa.bst', 0.9),
  ('dsa.sorting', 'dsa.bst', 0.5),
  ('dbms.relational_model', 'dbms.transactions', 0.6),
  ('dbms.keys', 'dbms.indexing', 0.7),
  ('dbms.normalization_3nf', 'dbms.bcnf', 0.9),
  ('dbms.joins', 'dbms.sql_aggregate', 0.7)
on conflict (parent_id, child_id) do nothing;

insert into misconceptions (misconception_id, concept_id, label, remediation_note) values
  ('cn.m01', 'cn.subnetting', 'Counts host bits from the wrong end', 'Host bits are the low-order bits. /26 leaves 6 host bits, so 62 usable addresses.'),
  ('cn.m02', 'cn.subnetting', 'Forgets network and broadcast are unreserved', 'Usable hosts are 2^h minus 2, never 2^h.'),
  ('cn.m03', 'cn.tcp_flow', 'Confuses flow control with congestion control', 'Flow control protects the receiver. Congestion control protects the network.'),
  ('cn.m04', 'cn.tcp_congestion', 'Thinks slow start is linear', 'Slow start doubles cwnd per RTT. It is exponential despite the name.'),
  ('cn.m05', 'cn.udp', 'Believes UDP guarantees ordering', 'UDP has no ordering, no retransmission, and no delivery guarantee.'),
  ('cn.m06', 'cn.osi_model', 'Places TCP at the network layer', 'TCP is layer 4. IP is layer 3.'),
  ('cn.m07', 'cn.dns', 'Thinks DNS runs only over TCP', 'DNS uses UDP for standard queries and TCP for zone transfers or large responses.'),
  ('cn.m08', 'cn.http', 'Assumes HTTP is stateful', 'HTTP is stateless. State comes from cookies, tokens, or sessions layered on top.'),
  ('os.m01', 'os.thread', 'Thinks threads have separate address spaces', 'Threads share the address space. Processes do not.'),
  ('os.m02', 'os.scheduling', 'Believes SJF is always optimal in practice', 'SJF minimises average waiting time but requires knowing burst lengths in advance.'),
  ('os.m03', 'os.deadlock', 'Thinks removing any one condition is impossible', 'Breaking any one of the four Coffman conditions prevents deadlock.'),
  ('os.m04', 'os.sync', 'Confuses a mutex with a semaphore', 'A mutex has ownership. A counting semaphore does not.'),
  ('os.m05', 'os.paging', 'Believes paging causes external fragmentation', 'Paging eliminates external fragmentation and introduces internal fragmentation.'),
  ('os.m06', 'os.page_replacement', 'Assumes more frames always mean fewer faults', 'Belady anomaly: FIFO can fault more with more frames.'),
  ('os.m07', 'os.virtual_memory', 'Thinks thrashing means the disk has failed', 'Thrashing is excessive paging because the working set exceeds available frames.'),
  ('dsa.m08', 'dsa.hashing', 'Assumes hash lookup is always O(1)', 'Worst case is O(n) when every key collides into one bucket.'),
  ('dsa.m09', 'dsa.sliding_window', 'Applies the window to arrays with negatives', 'A shrinking window needs monotonic sums, which negatives break.'),
  ('dsa.m10', 'dsa.dp_1d', 'Confuses memoization with tabulation', 'Both cache subproblems; one is top-down recursive, the other bottom-up iterative.'),
  ('dsa.m11', 'dsa.bst', 'Thinks BST operations are always O(log n)', 'Unbalanced BSTs degrade to O(n). Only balanced trees guarantee log n.'),
  ('dbms.m06', 'dbms.transactions', 'Thinks isolation prevents all anomalies by default', 'Isolation level decides which anomalies are prevented. READ COMMITTED still allows non-repeatable reads.'),
  ('dbms.m07', 'dbms.indexing', 'Believes an index always speeds up a query', 'Indexes cost writes and are ignored when selectivity is poor.'),
  ('dbms.m08', 'dbms.bcnf', 'Thinks 3NF and BCNF are the same', 'They differ only when candidate keys overlap.'),
  ('dbms.m09', 'dbms.sql_aggregate', 'Uses WHERE to filter aggregates', 'WHERE filters rows before grouping. HAVING filters after.')
on conflict (misconception_id) do nothing;

insert into bkt_params (concept_id, p_init, p_transit, p_slip, p_guess)
select concept_id, 0.15, 0.15, 0.10, 0.25 from concepts
on conflict (concept_id) do nothing;

do $$
declare qid uuid;
begin
  qid := md5('x2-q001')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.osi_model', 'At which OSI layer does TCP operate?', -0.6, 30, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.osi_model', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q001-o0')::uuid, qid, 'Layer 3, network', false, 'cn.m06', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q001-o1')::uuid, qid, 'Layer 4, transport', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q001-o2')::uuid, qid, 'Layer 5, session', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q001-o3')::uuid, qid, 'Layer 2, data link', false, 'cn.m06', 3) on conflict (option_id) do nothing;

  qid := md5('x2-q002')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.osi_model', 'Which layer is responsible for routing packets between networks?', -0.5, 32, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.osi_model', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q002-o0')::uuid, qid, 'Transport', false, 'cn.m06', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q002-o1')::uuid, qid, 'Network', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q002-o2')::uuid, qid, 'Data link', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q002-o3')::uuid, qid, 'Session', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q003')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.ip_addressing', 'How many bits are in an IPv4 address?', -1.1, 20, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.ip_addressing', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q003-o0')::uuid, qid, '64', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q003-o1')::uuid, qid, '32', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q003-o2')::uuid, qid, '128', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q003-o3')::uuid, qid, '16', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q004')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.subnetting', 'How many usable host addresses does a /26 subnet provide?', 0.3, 60, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.subnetting', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q004-o0')::uuid, qid, '64', false, 'cn.m02', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q004-o1')::uuid, qid, '62', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q004-o2')::uuid, qid, '30', false, 'cn.m01', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q004-o3')::uuid, qid, '126', false, 'cn.m01', 3) on conflict (option_id) do nothing;

  qid := md5('x2-q005')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.subnetting', 'What is the subnet mask for a /27 network?', 0.2, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.subnetting', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q005-o0')::uuid, qid, '255.255.255.192', false, 'cn.m01', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q005-o1')::uuid, qid, '255.255.255.224', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q005-o2')::uuid, qid, '255.255.255.240', false, 'cn.m01', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q005-o3')::uuid, qid, '255.255.255.128', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q006')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.subnetting', 'A /30 subnet is commonly used for point-to-point links. Why?', 0.5, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.subnetting', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q006-o0')::uuid, qid, 'It provides 4 usable addresses', false, 'cn.m02', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q006-o1')::uuid, qid, 'It provides exactly 2 usable addresses', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q006-o2')::uuid, qid, 'It provides 8 usable addresses', false, 'cn.m02', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q006-o3')::uuid, qid, 'It has no broadcast address', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q007')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.tcp_basics', 'How many messages are exchanged in the TCP three-way handshake?', -0.7, 25, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.tcp_basics', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q007-o0')::uuid, qid, 'Two', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q007-o1')::uuid, qid, 'Three', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q007-o2')::uuid, qid, 'Four', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q007-o3')::uuid, qid, 'One', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q008')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.tcp_basics', 'Which TCP mechanism detects a lost segment without waiting for a timeout?', 0.4, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.tcp_basics', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q008-o0')::uuid, qid, 'Slow start', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q008-o1')::uuid, qid, 'Three duplicate ACKs', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q008-o2')::uuid, qid, 'Nagle algorithm', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q008-o3')::uuid, qid, 'Window scaling', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q009')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.tcp_flow', 'What does the TCP receive window advertise?', 0.2, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.tcp_flow', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q009-o0')::uuid, qid, 'How congested the network path is', false, 'cn.m03', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q009-o1')::uuid, qid, 'How much buffer space the receiver has free', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q009-o2')::uuid, qid, 'The maximum segment size', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q009-o3')::uuid, qid, 'The round-trip time estimate', false, 'cn.m03', 3) on conflict (option_id) do nothing;

  qid := md5('x2-q010')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.tcp_flow', 'Flow control exists to protect which party?', 0.0, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.tcp_flow', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q010-o0')::uuid, qid, 'The intermediate routers', false, 'cn.m03', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q010-o1')::uuid, qid, 'The receiver', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q010-o2')::uuid, qid, 'The sender', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q010-o3')::uuid, qid, 'The DNS resolver', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q011')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.tcp_congestion', 'How does the congestion window grow during slow start?', 0.5, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.tcp_congestion', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q011-o0')::uuid, qid, 'Linearly, one MSS per RTT', false, 'cn.m04', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q011-o1')::uuid, qid, 'Exponentially, doubling each RTT', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q011-o2')::uuid, qid, 'It stays constant', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q011-o3')::uuid, qid, 'It halves each RTT', false, 'cn.m04', 3) on conflict (option_id) do nothing;

  qid := md5('x2-q012')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.tcp_congestion', 'What happens to cwnd on a timeout in TCP Reno?', 0.7, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.tcp_congestion', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q012-o0')::uuid, qid, 'It doubles', false, 'cn.m04', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q012-o1')::uuid, qid, 'It drops to one MSS and slow start restarts', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q012-o2')::uuid, qid, 'It stays the same', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q012-o3')::uuid, qid, 'It grows linearly', false, 'cn.m04', 3) on conflict (option_id) do nothing;

  qid := md5('x2-q013')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.udp', 'Which guarantee does UDP provide?', -0.4, 35, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.udp', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q013-o0')::uuid, qid, 'In-order delivery', false, 'cn.m05', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q013-o1')::uuid, qid, 'None of these', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q013-o2')::uuid, qid, 'Retransmission of lost packets', false, 'cn.m05', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q013-o3')::uuid, qid, 'Flow control', false, 'cn.m05', 3) on conflict (option_id) do nothing;

  qid := md5('x2-q014')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.udp', 'Why is UDP preferred for live video streaming?', 0.1, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.udp', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q014-o0')::uuid, qid, 'It guarantees ordering', false, 'cn.m05', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q014-o1')::uuid, qid, 'Retransmitting a late frame is worse than dropping it', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q014-o2')::uuid, qid, 'It encrypts by default', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q014-o3')::uuid, qid, 'It uses fewer ports', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q015')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.dns', 'Which transport protocol does a standard DNS query use?', 0.0, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.dns', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q015-o0')::uuid, qid, 'TCP only', false, 'cn.m07', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q015-o1')::uuid, qid, 'UDP, falling back to TCP for large responses', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q015-o2')::uuid, qid, 'ICMP', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q015-o3')::uuid, qid, 'HTTP', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q016')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.dns', 'What does a DNS A record map?', -0.8, 25, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.dns', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q016-o0')::uuid, qid, 'A domain to a mail server', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q016-o1')::uuid, qid, 'A domain to an IPv4 address', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q016-o2')::uuid, qid, 'A domain to another domain', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q016-o3')::uuid, qid, 'A domain to an IPv6 address', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q017')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.http', 'Why is HTTP described as stateless?', 0.1, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.http', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q017-o0')::uuid, qid, 'It cannot send data', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q017-o1')::uuid, qid, 'Each request is independent; the server keeps no inherent memory of prior ones', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q017-o2')::uuid, qid, 'It has no status codes', false, 'cn.m08', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q017-o3')::uuid, qid, 'It requires cookies to function', false, 'cn.m08', 3) on conflict (option_id) do nothing;

  qid := md5('x2-q018')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.http', 'Which HTTP status code family indicates a client error?', -0.6, 30, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.http', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q018-o0')::uuid, qid, '3xx', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q018-o1')::uuid, qid, '4xx', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q018-o2')::uuid, qid, '5xx', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q018-o3')::uuid, qid, '2xx', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q019')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.routing', 'What does a routing table entry with the longest prefix match determine?', 0.4, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.routing', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q019-o0')::uuid, qid, 'The slowest path', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q019-o1')::uuid, qid, 'The most specific matching route', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q019-o2')::uuid, qid, 'The default gateway only', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q019-o3')::uuid, qid, 'The MAC address', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q020')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'cn.switching', 'At which layer does an Ethernet switch primarily operate?', -0.3, 30, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'cn.switching', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q020-o0')::uuid, qid, 'Layer 3', false, 'cn.m06', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q020-o1')::uuid, qid, 'Layer 2', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q020-o2')::uuid, qid, 'Layer 4', false, 'cn.m06', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q020-o3')::uuid, qid, 'Layer 1', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q021')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.process', 'What is the main difference between a process and a program?', -0.7, 35, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.process', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q021-o0')::uuid, qid, 'There is none', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q021-o1')::uuid, qid, 'A process is a program in execution with its own state', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q021-o2')::uuid, qid, 'A program is faster', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q021-o3')::uuid, qid, 'A process has no memory', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q022')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.thread', 'Which resource is shared between threads of the same process?', -0.2, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.thread', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q022-o0')::uuid, qid, 'The stack', false, 'os.m01', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q022-o1')::uuid, qid, 'The heap and address space', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q022-o2')::uuid, qid, 'The program counter', false, 'os.m01', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q022-o3')::uuid, qid, 'The register set', false, 'os.m01', 3) on conflict (option_id) do nothing;

  qid := md5('x2-q023')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.thread', 'What is the main advantage of threads over processes for concurrency?', 0.0, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.thread', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q023-o0')::uuid, qid, 'Threads have isolated memory', false, 'os.m01', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q023-o1')::uuid, qid, 'Context switching and communication are cheaper', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q023-o2')::uuid, qid, 'Threads cannot deadlock', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q023-o3')::uuid, qid, 'Threads never share data', false, 'os.m01', 3) on conflict (option_id) do nothing;

  qid := md5('x2-q024')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.scheduling', 'Which scheduling algorithm minimises average waiting time in theory?', 0.2, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.scheduling', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q024-o0')::uuid, qid, 'First come first served', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q024-o1')::uuid, qid, 'Shortest job first', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q024-o2')::uuid, qid, 'Round robin', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q024-o3')::uuid, qid, 'Priority with aging', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q025')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.scheduling', 'Why is SJF hard to use in a real operating system?', 0.5, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.scheduling', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q025-o0')::uuid, qid, 'It is too slow to compute', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q025-o1')::uuid, qid, 'Future burst lengths are not known in advance', true, 'os.m02', 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q025-o2')::uuid, qid, 'It causes deadlock', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q025-o3')::uuid, qid, 'It requires more memory', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q026')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.scheduling', 'What problem does a very small round-robin time quantum cause?', 0.4, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.scheduling', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q026-o0')::uuid, qid, 'Starvation of short jobs', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q026-o1')::uuid, qid, 'Excessive context-switch overhead', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q026-o2')::uuid, qid, 'Deadlock', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q026-o3')::uuid, qid, 'Memory fragmentation', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q027')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.deadlock', 'How many Coffman conditions must hold simultaneously for deadlock?', -0.1, 35, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.deadlock', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q027-o0')::uuid, qid, 'Two', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q027-o1')::uuid, qid, 'Four', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q027-o2')::uuid, qid, 'Three', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q027-o3')::uuid, qid, 'Five', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q028')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.deadlock', 'Which is NOT one of the four necessary conditions for deadlock?', 0.3, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.deadlock', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q028-o0')::uuid, qid, 'Mutual exclusion', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q028-o1')::uuid, qid, 'Preemption of held resources', true, 'os.m03', 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q028-o2')::uuid, qid, 'Hold and wait', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q028-o3')::uuid, qid, 'Circular wait', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q029')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.sync', 'What distinguishes a mutex from a binary semaphore?', 0.4, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.sync', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q029-o0')::uuid, qid, 'Nothing, they are identical', false, 'os.m04', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q029-o1')::uuid, qid, 'A mutex has an owner and only the owner may release it', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q029-o2')::uuid, qid, 'A mutex counts to more than one', false, 'os.m04', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q029-o3')::uuid, qid, 'A semaphore cannot block', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q030')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.sync', 'What is a race condition?', -0.3, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.sync', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q030-o0')::uuid, qid, 'Two processes competing for CPU time', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q030-o1')::uuid, qid, 'Output depending on the unpredictable ordering of concurrent accesses', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q030-o2')::uuid, qid, 'A deadlock between two threads', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q030-o3')::uuid, qid, 'A scheduling algorithm', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q031')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.paging', 'Which type of fragmentation does paging introduce?', 0.2, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.paging', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q031-o0')::uuid, qid, 'External fragmentation', false, 'os.m05', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q031-o1')::uuid, qid, 'Internal fragmentation', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q031-o2')::uuid, qid, 'Both equally', false, 'os.m05', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q031-o3')::uuid, qid, 'Neither', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q032')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.paging', 'What does the TLB cache?', 0.3, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.paging', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q032-o0')::uuid, qid, 'Recently used data blocks', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q032-o1')::uuid, qid, 'Recent page-number to frame-number translations', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q032-o2')::uuid, qid, 'Free frame lists', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q032-o3')::uuid, qid, 'Disk sectors', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q033')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.virtual_memory', 'What is thrashing?', 0.4, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.virtual_memory', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q033-o0')::uuid, qid, 'A failing disk drive', false, 'os.m07', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q033-o1')::uuid, qid, 'Spending more time paging than executing', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q033-o2')::uuid, qid, 'A deadlock in the page table', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q033-o3')::uuid, qid, 'Excessive context switching', false, 'os.m07', 3) on conflict (option_id) do nothing;

  qid := md5('x2-q034')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.page_replacement', 'Which algorithm can exhibit Belady anomaly?', 0.6, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.page_replacement', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q034-o0')::uuid, qid, 'LRU', false, 'os.m06', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q034-o1')::uuid, qid, 'FIFO', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q034-o2')::uuid, qid, 'Optimal', false, 'os.m06', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q034-o3')::uuid, qid, 'Clock', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q035')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.page_replacement', 'What does the optimal page replacement algorithm require?', 0.5, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.page_replacement', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q035-o0')::uuid, qid, 'The least recently used page', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q035-o1')::uuid, qid, 'Knowledge of future references', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q035-o2')::uuid, qid, 'A larger TLB', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q035-o3')::uuid, qid, 'More frames', false, 'os.m06', 3) on conflict (option_id) do nothing;

  qid := md5('x2-q036')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'os.filesystem', 'What does an inode store?', 0.1, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'os.filesystem', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q036-o0')::uuid, qid, 'The file name', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q036-o1')::uuid, qid, 'File metadata and pointers to data blocks', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q036-o2')::uuid, qid, 'The directory tree', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q036-o3')::uuid, qid, 'The file contents only', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q037')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.hashing', 'What is the worst-case lookup time in a hash table with chaining?', 0.4, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.hashing', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q037-o0')::uuid, qid, 'O(1) always', false, 'dsa.m08', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q037-o1')::uuid, qid, 'O(n)', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q037-o2')::uuid, qid, 'O(log n)', false, 'dsa.m08', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q037-o3')::uuid, qid, 'O(n log n)', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q038')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.hashing', 'What is a load factor in a hash table?', 0.0, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.hashing', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q038-o0')::uuid, qid, 'The number of collisions', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q038-o1')::uuid, qid, 'Entries divided by buckets', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q038-o2')::uuid, qid, 'The size of each key', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q038-o3')::uuid, qid, 'The rehash threshold only', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q039')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.two_pointers', 'On which kind of input does the two-pointer technique for pair sums require sorted data?', 0.2, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.two_pointers', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q039-o0')::uuid, qid, 'Only on linked lists', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q039-o1')::uuid, qid, 'On arrays where pointers converge from both ends', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q039-o2')::uuid, qid, 'Never', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q039-o3')::uuid, qid, 'Only on trees', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q040')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.sliding_window', 'Why does the shrinking sliding window fail on arrays containing negatives?', 0.7, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.sliding_window', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q040-o0')::uuid, qid, 'Negatives cannot be summed', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q040-o1')::uuid, qid, 'The window sum is no longer monotonic as the window grows', true, 'dsa.m09', 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q040-o2')::uuid, qid, 'It becomes O(n^2)', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q040-o3')::uuid, qid, 'It requires sorting first', false, 'dsa.m09', 3) on conflict (option_id) do nothing;

  qid := md5('x2-q041')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.dp_1d', 'What distinguishes memoization from tabulation?', 0.3, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.dp_1d', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q041-o0')::uuid, qid, 'Nothing, they are the same', false, 'dsa.m10', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q041-o1')::uuid, qid, 'Memoization is top-down recursive; tabulation is bottom-up iterative', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q041-o2')::uuid, qid, 'Memoization uses less memory always', false, 'dsa.m10', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q041-o3')::uuid, qid, 'Tabulation cannot handle overlapping subproblems', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q042')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.dp_1d', 'What are the two properties a problem needs for dynamic programming?', 0.4, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.dp_1d', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q042-o0')::uuid, qid, 'Sorting and searching', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q042-o1')::uuid, qid, 'Optimal substructure and overlapping subproblems', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q042-o2')::uuid, qid, 'Recursion and iteration', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q042-o3')::uuid, qid, 'Greedy choice and sorting', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q043')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.trees', 'What is the height of a complete binary tree with n nodes?', 0.3, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.trees', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q043-o0')::uuid, qid, 'O(n)', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q043-o1')::uuid, qid, 'O(log n)', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q043-o2')::uuid, qid, 'O(n log n)', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q043-o3')::uuid, qid, 'O(1)', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q044')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.bst', 'What is the worst-case time for search in an unbalanced BST?', 0.2, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.bst', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q044-o0')::uuid, qid, 'O(log n)', false, 'dsa.m11', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q044-o1')::uuid, qid, 'O(n)', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q044-o2')::uuid, qid, 'O(1)', false, 'dsa.m11', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q044-o3')::uuid, qid, 'O(n log n)', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q045')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dsa.bst', 'An in-order traversal of a BST produces what?', -0.4, 35, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dsa.bst', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q045-o0')::uuid, qid, 'Nodes in insertion order', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q045-o1')::uuid, qid, 'Nodes in sorted ascending order', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q045-o2')::uuid, qid, 'Nodes in reverse order', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q045-o3')::uuid, qid, 'Nodes level by level', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q046')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.transactions', 'What does the I in ACID stand for?', -0.8, 25, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.transactions', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q046-o0')::uuid, qid, 'Integrity', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q046-o1')::uuid, qid, 'Isolation', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q046-o2')::uuid, qid, 'Indexing', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q046-o3')::uuid, qid, 'Immutability', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q047')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.transactions', 'Which anomaly does READ COMMITTED still permit?', 0.6, 55, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.transactions', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q047-o0')::uuid, qid, 'Dirty reads', false, 'dbms.m06', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q047-o1')::uuid, qid, 'Non-repeatable reads', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q047-o2')::uuid, qid, 'None of them', false, 'dbms.m06', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q047-o3')::uuid, qid, 'Lost updates only', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q048')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.indexing', 'When is an index likely to be ignored by the query planner?', 0.5, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.indexing', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q048-o0')::uuid, qid, 'When the table is small or selectivity is poor', true, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q048-o1')::uuid, qid, 'When the column is a primary key', false, 'dbms.m07', 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q048-o2')::uuid, qid, 'When the table has many rows', false, 'dbms.m07', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q048-o3')::uuid, qid, 'When the index is unique', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q049')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.indexing', 'What is the main cost of adding an index?', 0.3, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.indexing', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q049-o0')::uuid, qid, 'Slower reads', false, 'dbms.m07', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q049-o1')::uuid, qid, 'Slower writes and extra storage', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q049-o2')::uuid, qid, 'Loss of referential integrity', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q049-o3')::uuid, qid, 'It breaks joins', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q050')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.bcnf', 'When does a relation in 3NF fail to be in BCNF?', 0.8, 60, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.bcnf', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q050-o0')::uuid, qid, 'When it has a single candidate key', false, 'dbms.m08', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q050-o1')::uuid, qid, 'When a non-trivial FD has a determinant that is not a superkey', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q050-o2')::uuid, qid, 'Never; they are equivalent', false, 'dbms.m08', 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q050-o3')::uuid, qid, 'When it has no foreign keys', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q051')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.sql_aggregate', 'Which clause filters rows AFTER grouping?', 0.0, 40, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.sql_aggregate', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q051-o0')::uuid, qid, 'WHERE', false, 'dbms.m09', 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q051-o1')::uuid, qid, 'HAVING', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q051-o2')::uuid, qid, 'ORDER BY', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q051-o3')::uuid, qid, 'LIMIT', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q052')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.sql_aggregate', 'What does COUNT(column) ignore that COUNT(*) does not?', 0.3, 45, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.sql_aggregate', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q052-o0')::uuid, qid, 'Duplicate values', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q052-o1')::uuid, qid, 'NULL values in that column', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q052-o2')::uuid, qid, 'Zero values', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q052-o3')::uuid, qid, 'Empty strings', false, null, 3) on conflict (option_id) do nothing;

  qid := md5('x2-q053')::uuid;
  insert into questions (question_id, primary_concept_id, stem, difficulty, median_time_sec, source)
  values (qid, 'dbms.sql_aggregate', 'A query groups by department and selects employee_name without aggregation. What happens in strict SQL?', 0.5, 50, 'authored') on conflict (question_id) do nothing;
  insert into question_concepts (question_id, concept_id, weight) values (qid, 'dbms.sql_aggregate', 1.0) on conflict do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q053-o0')::uuid, qid, 'It returns the first name per group', false, null, 0) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q053-o1')::uuid, qid, 'It is rejected because the column is neither grouped nor aggregated', true, null, 1) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q053-o2')::uuid, qid, 'It returns NULL', false, null, 2) on conflict (option_id) do nothing;
  insert into options (option_id, question_id, body, is_correct, misconception_id, ordinal)
  values (md5('x2-q053-o3')::uuid, qid, 'It groups by name too', false, 'dbms.m09', 3) on conflict (option_id) do nothing;

end $$;

-- Language column, so the editor can state what it executes.
alter table coding_problems add column if not exists language_label text not null default 'JavaScript';

-- Fix the existing rows: standard SQL literals stored a literal backslash-n.
update coding_problems set starter_code = replace(starter_code, '\n', chr(10)) where starter_code like '%\n%';

-- New problems. E-strings interpret \n as a real newline.
insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, language, language_label) values
  ('cp.reverse_string', 'dsa.arrays', 'Reverse a String', 'Return the input string reversed.', E'function solve(s) {
  // your code here
}', -0.8, 'javascript', 'JavaScript')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.reverse_string', '["hello"]', '"olleh"', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.reverse_string' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.reverse_string', '["a"]', '"a"', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.reverse_string' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.reverse_string', '[""]', '""', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.reverse_string' and ordinal=2);

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, language, language_label) values
  ('cp.max_subarray', 'dsa.dp_1d', 'Maximum Subarray', 'Return the largest sum of any contiguous subarray. Kadane algorithm runs in O(n).', E'function solve(nums) {
  // your code here
}', 0.4, 'javascript', 'JavaScript')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.max_subarray', '[[-2,1,-3,4,-1,2,1,-5,4]]', '6', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.max_subarray' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.max_subarray', '[[1]]', '1', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.max_subarray' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.max_subarray', '[[-1,-2,-3]]', '-1', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.max_subarray' and ordinal=2);

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, language, language_label) values
  ('cp.valid_parens', 'dsa.recursion', 'Valid Parentheses', 'Return true if every bracket in s is closed by the same type in the correct order.', E'function solve(s) {
  // your code here
}', 0.0, 'javascript', 'JavaScript')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.valid_parens', '["()[]{}"]', 'true', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.valid_parens' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.valid_parens', '["(]"]', 'false', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.valid_parens' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.valid_parens', '["([)]"]', 'false', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.valid_parens' and ordinal=2);

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, language, language_label) values
  ('cp.first_unique', 'dsa.hashing', 'First Unique Character', 'Return the index of the first non-repeating character in s, or -1 if none exists.', E'function solve(s) {
  // your code here
}', 0.1, 'javascript', 'JavaScript')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.first_unique', '["leetcode"]', '0', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.first_unique' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.first_unique', '["loveleetcode"]', '2', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.first_unique' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.first_unique', '["aabb"]', '-1', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.first_unique' and ordinal=2);

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, language, language_label) values
  ('cp.move_zeroes', 'dsa.two_pointers', 'Move Zeroes', 'Move all zeroes to the end of nums while keeping the relative order of the other elements. Return the array.', E'function solve(nums) {
  // your code here
}', 0.0, 'javascript', 'JavaScript')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.move_zeroes', '[[0,1,0,3,12]]', '[1,3,12,0,0]', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.move_zeroes' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.move_zeroes', '[[0]]', '[0]', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.move_zeroes' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.move_zeroes', '[[1,2,3]]', '[1,2,3]', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.move_zeroes' and ordinal=2);

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, language, language_label) values
  ('cp.max_window_sum', 'dsa.sliding_window', 'Maximum Window Sum', 'Return the maximum sum of any contiguous subarray of exactly length k.', E'function solve(nums, k) {
  // your code here
}', 0.3, 'javascript', 'JavaScript')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.max_window_sum', '[[2,1,5,1,3,2],3]', '9', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.max_window_sum' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.max_window_sum', '[[1,2],2]', '3', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.max_window_sum' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.max_window_sum', '[[5,5,5],1]', '5', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.max_window_sum' and ordinal=2);

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, language, language_label) values
  ('cp.fib_memo', 'dsa.dp_1d', 'Fibonacci with Memoization', 'Return the nth Fibonacci number with fib(0)=0 and fib(1)=1. Naive recursion will time out for large n.', E'function solve(n) {
  // your code here
}', 0.2, 'javascript', 'JavaScript')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.fib_memo', '[10]', '55', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.fib_memo' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.fib_memo', '[0]', '0', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.fib_memo' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.fib_memo', '[30]', '832040', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.fib_memo' and ordinal=2);

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, language, language_label) values
  ('cp.merge_sorted', 'dsa.sorting', 'Merge Two Sorted Arrays', 'Merge two sorted arrays into one sorted array. Do it in O(n+m) without calling sort.', E'function solve(a, b) {
  // your code here
}', 0.1, 'javascript', 'JavaScript')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.merge_sorted', '[[1,3,5],[2,4,6]]', '[1,2,3,4,5,6]', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.merge_sorted' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.merge_sorted', '[[],[1]]', '[1]', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.merge_sorted' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.merge_sorted', '[[1,1],[1]]', '[1,1,1]', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.merge_sorted' and ordinal=2);

insert into coding_problems (problem_id, concept_id, title, prompt, starter_code, difficulty, language, language_label) values
  ('cp.bst_valid', 'dsa.bst', 'Validate BST Array', 'Given the in-order traversal of a tree as an array, return true if it could come from a valid BST (strictly increasing).', E'function solve(inorder) {
  // your code here
}', 0.3, 'javascript', 'JavaScript')
on conflict (problem_id) do nothing;
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.bst_valid', '[[1,2,3,4]]', 'true', false, 0
  where not exists (select 1 from coding_tests where problem_id='cp.bst_valid' and ordinal=0);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.bst_valid', '[[1,3,2]]', 'false', false, 1
  where not exists (select 1 from coding_tests where problem_id='cp.bst_valid' and ordinal=1);
insert into coding_tests (problem_id, input_json, expect_json, is_hidden, ordinal)
  select 'cp.bst_valid', '[[5]]', 'true', true, 2
  where not exists (select 1 from coding_tests where problem_id='cp.bst_valid' and ordinal=2);