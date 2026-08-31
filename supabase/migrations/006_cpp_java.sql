-- =====================================================================
-- 006_cpp_java.sql
-- Replaces JavaScript with C++ and Java, the languages actually used in
-- placement rounds. Python stays because it runs client-side via Pyodide
-- and therefore still works without a network connection.
--
-- C++ and Java execute through a remote judge, so each problem now
-- carries a type signature the harness generator uses to build main().
-- Idempotent.
-- =====================================================================

alter table coding_problems add column if not exists signature text;

-- Type signatures, used to generate the driver for compiled languages.
update coding_problems set signature = 'ints,int->ints' where problem_id = 'cp.two_sum';
update coding_problems set signature = 'ints,int->int' where problem_id = 'cp.binary_search';
update coding_problems set signature = 'ints,int->int' where problem_id = 'cp.kth_largest';
update coding_problems set signature = 'str->str' where problem_id = 'cp.reverse_string';
update coding_problems set signature = 'ints->int' where problem_id = 'cp.max_subarray';
update coding_problems set signature = 'str->bool' where problem_id = 'cp.valid_parens';
update coding_problems set signature = 'str->int' where problem_id = 'cp.first_unique';
update coding_problems set signature = 'ints->ints' where problem_id = 'cp.move_zeroes';
update coding_problems set signature = 'ints,int->int' where problem_id = 'cp.max_window_sum';
update coding_problems set signature = 'int->int' where problem_id = 'cp.fib_memo';
update coding_problems set signature = 'ints,ints->ints' where problem_id = 'cp.merge_sorted';
update coding_problems set signature = 'ints->bool' where problem_id = 'cp.bst_valid';

-- JavaScript is no longer offered.
delete from problem_starters where language = 'javascript';

insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.two_sum', 'cpp', 'C++', E'vector<int> solve(vector<int>& nums, int target) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.two_sum')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.two_sum', 'java', 'Java', E'static int[] solve(int[] nums, int target) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.two_sum')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.two_sum', 'python', 'Python', E'def solve(nums, target):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.two_sum')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;

insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.binary_search', 'cpp', 'C++', E'int solve(vector<int>& nums, int target) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.binary_search')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.binary_search', 'java', 'Java', E'static int solve(int[] nums, int target) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.binary_search')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.binary_search', 'python', 'Python', E'def solve(nums, target):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.binary_search')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;

insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.kth_largest', 'cpp', 'C++', E'int solve(vector<int>& nums, int k) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.kth_largest')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.kth_largest', 'java', 'Java', E'static int solve(int[] nums, int k) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.kth_largest')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.kth_largest', 'python', 'Python', E'def solve(nums, k):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.kth_largest')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;

insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.reverse_string', 'cpp', 'C++', E'string solve(string& s) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.reverse_string')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.reverse_string', 'java', 'Java', E'static String solve(String s) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.reverse_string')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.reverse_string', 'python', 'Python', E'def solve(s):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.reverse_string')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;

insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.max_subarray', 'cpp', 'C++', E'int solve(vector<int>& nums) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.max_subarray')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.max_subarray', 'java', 'Java', E'static int solve(int[] nums) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.max_subarray')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.max_subarray', 'python', 'Python', E'def solve(nums):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.max_subarray')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;

insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.valid_parens', 'cpp', 'C++', E'bool solve(string& s) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.valid_parens')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.valid_parens', 'java', 'Java', E'static boolean solve(String s) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.valid_parens')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.valid_parens', 'python', 'Python', E'def solve(s):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.valid_parens')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;

insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.first_unique', 'cpp', 'C++', E'int solve(string& s) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.first_unique')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.first_unique', 'java', 'Java', E'static int solve(String s) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.first_unique')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.first_unique', 'python', 'Python', E'def solve(s):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.first_unique')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;

insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.move_zeroes', 'cpp', 'C++', E'vector<int> solve(vector<int>& nums) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.move_zeroes')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.move_zeroes', 'java', 'Java', E'static int[] solve(int[] nums) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.move_zeroes')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.move_zeroes', 'python', 'Python', E'def solve(nums):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.move_zeroes')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;

insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.max_window_sum', 'cpp', 'C++', E'int solve(vector<int>& nums, int k) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.max_window_sum')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.max_window_sum', 'java', 'Java', E'static int solve(int[] nums, int k) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.max_window_sum')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.max_window_sum', 'python', 'Python', E'def solve(nums, k):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.max_window_sum')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;

insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.fib_memo', 'cpp', 'C++', E'int solve(int n) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.fib_memo')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.fib_memo', 'java', 'Java', E'static int solve(int n) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.fib_memo')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.fib_memo', 'python', 'Python', E'def solve(n):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.fib_memo')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;

insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.merge_sorted', 'cpp', 'C++', E'vector<int> solve(vector<int>& a, vector<int>& b) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.merge_sorted')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.merge_sorted', 'java', 'Java', E'static int[] solve(int[] a, int[] b) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.merge_sorted')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.merge_sorted', 'python', 'Python', E'def solve(a, b):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.merge_sorted')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;

insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.bst_valid', 'cpp', 'C++', E'bool solve(vector<int>& inorder) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.bst_valid')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.bst_valid', 'java', 'Java', E'static boolean solve(int[] inorder) {
    // your code here
}', true
  where exists (select 1 from coding_problems where problem_id = 'cp.bst_valid')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.bst_valid', 'python', 'Python', E'def solve(inorder):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.bst_valid')
on conflict (problem_id, language) do update set starter_code = excluded.starter_code, label = excluded.label;

update coding_problems set language = 'cpp', language_label = 'C++';