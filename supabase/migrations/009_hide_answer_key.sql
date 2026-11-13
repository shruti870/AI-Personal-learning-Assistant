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
