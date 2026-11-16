-- =====================================================================
-- 009 - Hide the answer key from students
--
-- Until now any signed-in student could read options.is_correct (and
-- misconception_id, which marks the wrong options) straight from the
-- Supabase API, e.g. supabase.from('options').select('*'). The policy in
-- 001 is row-level only; it cannot hide a column.
--
-- Column privileges can. Students keep the columns the question player
-- needs; is_correct and misconception_id are readable only by the
-- service_role key, which the web server uses for grading
-- (app/api/attempt), the AI tutor (app/api/explain) and the dashboard's
-- misconception list (lib/analytics.ts).
--
-- After running this, SUPABASE_SERVICE_ROLE_KEY must be set in the web
-- app's environment, or answering a question fails.
--
-- Safe to re-run.
-- =====================================================================

revoke select on public.options from anon, authenticated;
grant select (option_id, question_id, body, ordinal) on public.options to authenticated;

-- ---------------------------------------------------------------------
-- Attempts are graded by the server, so only the server writes them.
--
-- own_attempts (001) allowed students INSERT/UPDATE/DELETE on their own
-- rows, so a student could post is_correct = true straight through the
-- Supabase API (the BKT trigger then raised their mastery), or post fake
-- wrong attempts to learn which options are tagged misconceptions.
-- Students keep read access to their own attempts; /api/attempt inserts
-- with the service-role key after grading.
-- ---------------------------------------------------------------------
drop policy if exists own_attempts on public.attempts;
drop policy if exists read_own_attempts on public.attempts;
create policy read_own_attempts on public.attempts
  for select to authenticated using (student_id = auth.uid());

-- The display view runs with its owner's rights; nobody signed out needs it.
revoke select on public.options_for_display from anon;
