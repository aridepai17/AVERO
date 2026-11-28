-- A. Archive tables for child records of duplicate analyses.
-- LIKE ... INCLUDING CONSTRAINTS omits foreign keys, preventing cascade deletes
-- when active analyses rows are removed.
CREATE TABLE IF NOT EXISTS public.files_archived_duplicates (
    LIKE public.files INCLUDING DEFAULTS INCLUDING CONSTRAINTS,
    archived_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT files_archived_duplicates_id_key UNIQUE (id)
);

CREATE TABLE IF NOT EXISTS public.edges_archived_duplicates (
    LIKE public.edges INCLUDING DEFAULTS INCLUDING CONSTRAINTS,
    archived_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT edges_archived_duplicates_id_key UNIQUE (id)
);

CREATE TABLE IF NOT EXISTS public.routes_archived_duplicates (
    LIKE public.routes INCLUDING DEFAULTS INCLUDING CONSTRAINTS,
    archived_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT routes_archived_duplicates_id_key UNIQUE (id)
);

CREATE TABLE IF NOT EXISTS public.insights_archived_duplicates (
    LIKE public.insights INCLUDING DEFAULTS INCLUDING CONSTRAINTS,
    archived_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT insights_archived_duplicates_id_key UNIQUE (id)
);

-- Ensure parent duplicate archive table also has a unique constraint on id for idempotency.
CREATE TABLE IF NOT EXISTS public.analyses_archived_duplicates (
    LIKE public.analyses INCLUDING DEFAULTS INCLUDING CONSTRAINTS,
    archived_at timestamptz NOT NULL DEFAULT now()
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'analyses_archived_duplicates_id_key'
          AND conrelid = 'public.analyses_archived_duplicates'::regclass
    ) THEN
        ALTER TABLE public.analyses_archived_duplicates
            ADD CONSTRAINT analyses_archived_duplicates_id_key UNIQUE (id);
    END IF;
END
$$;

-- Enable RLS and enforce organization isolation on all archive tables using the
-- same JWT organization claim expression as the base tables.
ALTER TABLE public.analyses_archived_duplicates ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.files_archived_duplicates ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.edges_archived_duplicates ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.routes_archived_duplicates ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.insights_archived_duplicates ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
    tbl text;
    pol_name text;
BEGIN
    FOREACH tbl IN ARRAY ARRAY[
        'analyses_archived_duplicates',
        'files_archived_duplicates',
        'edges_archived_duplicates',
        'routes_archived_duplicates',
        'insights_archived_duplicates'
    ]
    LOOP
        pol_name := 'members read their organization''s rows';
        IF NOT EXISTS (
            SELECT 1
            FROM pg_policies
            WHERE schemaname = 'public'
              AND tablename = tbl
              AND policyname = pol_name
        ) THEN
            EXECUTE format(
                'CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (
                    organization_id = (
                        SELECT coalesce(
                            auth.jwt() -> ''o'' ->> ''id'',
                            auth.jwt() ->> ''org_id''
                        )
                    )
                )',
                pol_name,
                tbl
            );
        END IF;
    END LOOP;
END
$$;

-- Archive any remaining duplicate analyses (rn > 1 per project_id) and all of
-- their child records atomically before deleting duplicate parent rows.
-- Latest analysis (rn = 1) and its children are untouched.
WITH
    ranked_analyses AS (
        SELECT
            id,
            ROW_NUMBER() OVER (
                PARTITION BY
                    project_id
                ORDER BY
                    created_at DESC,
                    id DESC
            ) AS rn
        FROM
            public.analyses
    ),
    duplicate_ids AS (
        SELECT
            id
        FROM
            ranked_analyses
        WHERE
            rn > 1
    ),
    archived_files AS (
        INSERT INTO
            public.files_archived_duplicates
        SELECT
            f.*,
            now()
        FROM
            public.files f
            JOIN duplicate_ids d ON f.analysis_id = d.id
        ON CONFLICT (id) DO NOTHING
        RETURNING
            id
    ),
    archived_edges AS (
        INSERT INTO
            public.edges_archived_duplicates
        SELECT
            e.*,
            now()
        FROM
            public.edges e
            JOIN duplicate_ids d ON e.analysis_id = d.id
        ON CONFLICT (id) DO NOTHING
        RETURNING
            id
    ),
    archived_routes AS (
        INSERT INTO
            public.routes_archived_duplicates
        SELECT
            r.*,
            now()
        FROM
            public.routes r
            JOIN duplicate_ids d ON r.analysis_id = d.id
        ON CONFLICT (id) DO NOTHING
        RETURNING
            id
    ),
    archived_insights AS (
        INSERT INTO
            public.insights_archived_duplicates
        SELECT
            i.*,
            now()
        FROM
            public.insights i
            JOIN duplicate_ids d ON i.analysis_id = d.id
        ON CONFLICT (id) DO NOTHING
        RETURNING
            id
    ),
    archived_parents AS (
        INSERT INTO
            public.analyses_archived_duplicates
        SELECT
            a.*,
            now()
        FROM
            public.analyses a
            JOIN duplicate_ids d ON a.id = d.id
        ON CONFLICT (id) DO NOTHING
        RETURNING
            id
    )
DELETE FROM public.analyses a USING archived_parents ap
WHERE
    a.id = ap.id;

-- B. Idempotent RPC function definitions with preserved signatures,
-- search_path = '', and explicit REVOKE / GRANT for service_role.
CREATE OR REPLACE FUNCTION public.clear_analysis_files_for_run (
    p_analysis_id uuid,
    p_claimed_started_at timestamptz
) RETURNS void LANGUAGE plpgsql
SET
    search_path = '' AS $$
declare
  v_owned boolean;
begin
  select exists (
    select 1
    from public.analyses
    where id = p_analysis_id
      and started_at = p_claimed_started_at
    for update
  ) into v_owned;

  if not v_owned then
    raise exception 'SUPERSEDED: Analysis % was taken over by a newer run', p_analysis_id
      using errcode = 'P0002';
  end if;

  delete from public.files
  where analysis_id = p_analysis_id;
end;
$$;

CREATE OR REPLACE FUNCTION public.insert_analysis_files_for_run (
    p_analysis_id uuid,
    p_claimed_started_at timestamptz,
    p_rows jsonb
) RETURNS void LANGUAGE plpgsql
SET
    search_path = '' AS $$
declare
  v_owned boolean;
begin
  select exists (
    select 1
    from public.analyses
    where id = p_analysis_id
      and started_at = p_claimed_started_at
    for update
  ) into v_owned;

  if not v_owned then
    raise exception 'SUPERSEDED: Analysis % was taken over by a newer run', p_analysis_id
      using errcode = 'P0002';
  end if;

  insert into public.files (
    organization_id,
    analysis_id,
    path,
    module,
    lines,
    bytes,
    hash,
    fan_in,
    fan_out,
    skip_reason,
    skip_detail
  )
  select
    r->>'organization_id',
    p_analysis_id,
    r->>'path',
    nullif(r->>'module', '')::text,
    (r->>'lines')::integer,
    (r->>'bytes')::integer,
    r->>'hash',
    (r->>'fan_in')::integer,
    (r->>'fan_out')::integer,
    r->>'skip_reason',
    r->>'skip_detail'
  from jsonb_array_elements(p_rows) as r;
end;
$$;

CREATE OR REPLACE FUNCTION public.insert_edges (
    p_analysis_id uuid,
    p_claimed_started_at timestamptz,
    p_edges jsonb
) RETURNS integer LANGUAGE plpgsql
SET
    search_path = '' AS $$
declare
  v_owned boolean;
  expected integer := coalesce(jsonb_array_length(p_edges), 0);
  inserted integer;
begin
  select exists (
    select 1
    from public.analyses
    where id = p_analysis_id
      and started_at = p_claimed_started_at
    for update
  ) into v_owned;

  if not v_owned then
    raise exception 'SUPERSEDED: Analysis % was taken over by a newer run', p_analysis_id
      using errcode = 'P0002';
  end if;

  insert into public.edges
    (organization_id, analysis_id, source_file_id, target_file_id, kind, specifier, type_only, line)
  select s.organization_id, p_analysis_id, s.id, t.id, e.kind, e.specifier, e.type_only, e.line
  from jsonb_to_recordset(p_edges)
    as e (source text, target text, kind text, specifier text, type_only boolean, line integer)
  join public.files s on s.analysis_id = p_analysis_id and s.path = e.source and s.skip_reason is null
  join public.files t on t.analysis_id = p_analysis_id and t.path = e.target and t.skip_reason is null;

  get diagnostics inserted = row_count;
  if inserted <> expected then
    raise exception 'insert_edges: % of % edges matched stored files for analysis %', inserted, expected, p_analysis_id;
  end if;
  return inserted;
end;
$$;

-- C. Atomic run claiming with row-level lock on public.analyses.
DROP FUNCTION IF EXISTS public.claim_analysis (uuid, timestamptz);

CREATE OR REPLACE FUNCTION public.claim_analysis (p_analysis_id uuid, p_stale_before timestamptz) RETURNS TABLE (
    organization_id text,
    started_at timestamptz,
    repo_owner text,
    repo_name text
) LANGUAGE plpgsql
SET
    search_path = '' AS $$
declare
  v_row public.analyses%rowtype;
  v_now timestamptz := now();
  v_org_id text;
  v_started_at timestamptz;
  v_repo_owner text;
  v_repo_name text;
begin
  select *
  into v_row
  from public.analyses
  where id = p_analysis_id
  for update;

  if not found then
    return;
  end if;

  if v_row.status = 'running'
     and v_row.started_at is not null
     and v_row.started_at >= p_stale_before then
    return;
  end if;

  update public.analyses a
  set
    status = 'running',
    stage = 'fetch',
    stage_message = 'Starting',
    started_at = v_now,
    finished_at = null,
    error = null,
    coverage = null,
    detected_projects = null,
    schema_version = null
  where a.id = p_analysis_id
  returning a.organization_id, a.started_at into v_org_id, v_started_at;

  select p.repo_owner, p.repo_name
  into v_repo_owner, v_repo_name
  from public.projects p
  where p.id = v_row.project_id
    and p.organization_id = v_row.organization_id;

  organization_id := v_org_id;
  started_at := v_started_at;
  repo_owner := v_repo_owner;
  repo_name := v_repo_name;
  return next;
end;
$$;

REVOKE
EXECUTE ON FUNCTION public.clear_analysis_files_for_run (uuid, timestamptz)
FROM
    public,
    anon,
    authenticated;

GRANT
EXECUTE ON FUNCTION public.clear_analysis_files_for_run (uuid, timestamptz) TO service_role;

REVOKE
EXECUTE ON FUNCTION public.insert_analysis_files_for_run (uuid, timestamptz, jsonb)
FROM
    public,
    anon,
    authenticated;

GRANT
EXECUTE ON FUNCTION public.insert_analysis_files_for_run (uuid, timestamptz, jsonb) TO service_role;

REVOKE
EXECUTE ON FUNCTION public.insert_edges (uuid, timestamptz, jsonb)
FROM
    public,
    anon,
    authenticated;

GRANT
EXECUTE ON FUNCTION public.insert_edges (uuid, timestamptz, jsonb) TO service_role;

REVOKE
EXECUTE ON FUNCTION public.claim_analysis (uuid, timestamptz)
FROM
    public,
    anon,
    authenticated;

GRANT
EXECUTE ON FUNCTION public.claim_analysis (uuid, timestamptz) TO service_role;
