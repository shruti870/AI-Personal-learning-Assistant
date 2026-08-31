-- =====================================================================
-- 005_multi_language.sql
-- Per-language starter code, so the editor can offer a real choice.
-- JavaScript runs in-browser via Function; Python runs via Pyodide,
-- loaded on demand from a CDN the first time it is selected.
-- Idempotent.
-- =====================================================================

create table if not exists problem_starters (
  problem_id   text not null references coding_problems(problem_id) on delete cascade,
  language     text not null,          -- javascript | python
  label        text not null,          -- JavaScript | Python
  starter_code text not null,
  is_runnable  boolean not null default true,
  primary key (problem_id, language)
);

alter table problem_starters enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'problem_starters') then
    create policy read_starters on problem_starters for select to authenticated using (true);
  end if;
end $$;

-- JavaScript starters come from the existing rows.
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
select problem_id, 'javascript', 'JavaScript',
       replace(starter_code, '\n', chr(10)), true
  from coding_problems
on conflict (problem_id, language) do nothing;

-- Python starters.
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.two_sum', 'python', 'Python', E'def solve(nums, target):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.two_sum')
on conflict (problem_id, language) do nothing;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.binary_search', 'python', 'Python', E'def solve(nums, target):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.binary_search')
on conflict (problem_id, language) do nothing;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.kth_largest', 'python', 'Python', E'def solve(nums, k):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.kth_largest')
on conflict (problem_id, language) do nothing;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.reverse_string', 'python', 'Python', E'def solve(s):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.reverse_string')
on conflict (problem_id, language) do nothing;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.max_subarray', 'python', 'Python', E'def solve(nums):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.max_subarray')
on conflict (problem_id, language) do nothing;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.valid_parens', 'python', 'Python', E'def solve(s):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.valid_parens')
on conflict (problem_id, language) do nothing;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.first_unique', 'python', 'Python', E'def solve(s):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.first_unique')
on conflict (problem_id, language) do nothing;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.move_zeroes', 'python', 'Python', E'def solve(nums):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.move_zeroes')
on conflict (problem_id, language) do nothing;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.max_window_sum', 'python', 'Python', E'def solve(nums, k):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.max_window_sum')
on conflict (problem_id, language) do nothing;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.fib_memo', 'python', 'Python', E'def solve(n):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.fib_memo')
on conflict (problem_id, language) do nothing;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.merge_sorted', 'python', 'Python', E'def solve(a, b):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.merge_sorted')
on conflict (problem_id, language) do nothing;
insert into problem_starters (problem_id, language, label, starter_code, is_runnable)
  select 'cp.bst_valid', 'python', 'Python', E'def solve(inorder):
    # your code here
    pass', true
  where exists (select 1 from coding_problems where problem_id = 'cp.bst_valid')
on conflict (problem_id, language) do nothing;

-- Repair any remaining literal backslash-n.
update problem_starters set starter_code = replace(starter_code, '\n', chr(10))
  where starter_code like '%\n%';