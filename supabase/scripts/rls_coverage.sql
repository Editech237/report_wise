-- =============================================================================
-- ReportWise — RLS coverage review (spec section 46)
--
-- Run inside the Supabase database (psql / supabase db) to produce a policy
-- matrix: every table with RLS enabled, its policies, and a flag for tenant
-- tables that have RLS enabled but NO policies (a security hole).
--
--   supabase db -f scripts/rls_coverage.sql   (or pipe to psql)
-- =============================================================================

with rls_tables as (
  select
    c.oid,
    n.nspname as schema,
    c.relname as table_name,
    c.relrowsecurity as rls_enabled
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind = 'r'
)
select
  t.schema,
  t.table_name,
  t.rls_enabled,
  count(p.policyname) as policy_count,
  case
    when t.rls_enabled and count(p.policyname) = 0 then '!! RLS ON, NO POLICIES'
    when not t.rls_enabled then '!! RLS DISABLED'
    else ''
  end as flag
from rls_tables t
left join pg_policies p on p.schemaname = t.schema and p.tablename = t.table_name
group by t.schema, t.table_name, t.rls_enabled
order by flag desc, t.table_name;

-- Per-policy detail for tenant tables.
select
  schemaname, tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public'
order by tablename, policyname;

-- -----------------------------------------------------------------------------
-- Manual role scenario checks (paste into a SQL test harness / api tests):
--   * teacher  may SELECT students/classes but cannot UPDATE a student
--     (students_update_admin policy -> denied).
--   * teacher  may edit mark_entries only when their book is DRAFT.
--   * teacher  may NOT move a book SUBMITTED -> APPROVED (trigger raises).
--   * admin    may LOCK a book; afterwards entry writes are denied
--     (can_edit_mark_book returns false on LOCKED).
--   * admin    may unlock via unlock_mark_book, which requires a reason and
--     writes an UNLOCKED mark_book_event.
--   * member of school A cannot read rows of school B (tenant isolation).
--   * a FINAL period_result cannot be updated or deleted.
-- =============================================================================