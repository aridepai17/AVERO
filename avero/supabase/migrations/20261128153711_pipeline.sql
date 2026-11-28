-- The pipeline: analyses become real runs with named stages, and files and
-- edges carry everything the parser reports about them.
-- "parsing" was the name for any unfinished run. Which step it's on is the
-- stage's job now, so the status just says it's running.
ALTER TYPE public.analysis_status
RENAME VALUE 'parsing' TO 'running';

CREATE TYPE public.analysis_stage AS enum('fetch', 'select', 'parse', 'store');

ALTER TABLE public.analyses
-- Last stage entered. On a failed run, the stage it failed in.
ADD COLUMN stage public.analysis_stage,
ADD COLUMN stage_message text,
-- Set when a run (or re-run) begins; staleness is measured from here.
ADD COLUMN started_at timestamptz,
-- The parser's coverage report, minus the skipped-file list (that's the
-- files table), and the projects its adapters detected.
ADD COLUMN coverage jsonb,
ADD COLUMN detected_projects jsonb,
ADD COLUMN schema_version integer;

-- Backfill existing non-queued analyses before enforcing stage/start/complete checks.
UPDATE public.analyses
SET
    started_at = COALESCE(started_at, created_at),
    stage = COALESCE(
        stage,
        CASE
            WHEN status = 'complete' THEN 'store'::public.analysis_stage
            ELSE 'fetch'::public.analysis_stage
        END
    )
WHERE
    status <> 'queued';

UPDATE public.analyses
SET
    status = 'failed',
    error = COALESCE(
        error,
        'Analysis predates required pipeline metadata; re-run to generate map'
    ),
    finished_at = COALESCE(finished_at, now())
WHERE
    status = 'complete'
    AND (
        coverage IS NULL
        OR detected_projects IS NULL
        OR commit_sha IS NULL
        OR schema_version IS NULL
    );

-- A parsed file has its measurements; a skipped one has a reason and detail
-- and nothing else, so it can never be mistaken for a file with no imports.
ALTER TABLE public.files
ADD COLUMN skip_detail text,
ADD COLUMN module text,
ADD COLUMN lines integer,
ADD COLUMN bytes integer,
ADD COLUMN hash text,
ADD COLUMN fan_in integer,
ADD COLUMN fan_out integer;

-- Mark pre-existing files as skipped with detail so they pass the check constraint
-- without fabricating parsed file metrics.
UPDATE public.files
SET
    skip_reason = COALESCE(skip_reason, 'legacy'),
    skip_detail = COALESCE(
        skip_detail,
        'Migrated prior to parser v2; re-run analysis to populate metrics'
    )
WHERE
    skip_reason IS NOT NULL
    OR module IS NULL
    OR lines IS NULL
    OR bytes IS NULL
    OR hash IS NULL
    OR fan_in IS NULL
    OR fan_out IS NULL;

ALTER TABLE public.files
ADD CONSTRAINT files_parsed_or_skipped_check CHECK (
    CASE
        WHEN skip_reason IS NULL THEN skip_detail IS NULL
        AND module IS NOT NULL
        AND lines IS NOT NULL
        AND bytes IS NOT NULL
        AND hash IS NOT NULL
        AND fan_in IS NOT NULL
        AND fan_out IS NOT NULL
        ELSE skip_detail IS NOT NULL
        AND module IS NULL
        AND lines IS NULL
        AND bytes IS NULL
        AND hash IS NULL
        AND fan_in IS NULL
        AND fan_out IS NULL
    END
);

-- Archive existing edges before clearing public.edges for NOT NULL type_only/line columns.
CREATE TABLE IF NOT EXISTS public.edges_legacy_archive (
    LIKE public.edges INCLUDING DEFAULTS INCLUDING CONSTRAINTS,
    archived_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO
    public.edges_legacy_archive
SELECT
    e.*,
    now()
FROM
    public.edges e;

DELETE FROM public.edges;

ALTER TABLE public.edges
ADD COLUMN type_only boolean NOT NULL,
ADD COLUMN line integer NOT NULL,
ADD CONSTRAINT edges_unique_key UNIQUE (analysis_id, source_file_id, target_file_id, kind);

-- Create archive tables for duplicate analyses and their child records before
-- deleting non-latest analyses per project_id so cascading foreign keys do
-- not wipe child rows prior to archival.
CREATE TABLE IF NOT EXISTS public.analyses_archived_duplicates (
    LIKE public.analyses INCLUDING DEFAULTS INCLUDING CONSTRAINTS,
    archived_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT analyses_archived_duplicates_id_key UNIQUE (id)
);

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

ALTER TABLE public.analyses_archived_duplicates ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.files_archived_duplicates ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.edges_archived_duplicates ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.routes_archived_duplicates ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.insights_archived_duplicates ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
    tbl text;
    pol_name text := 'members read their organization''s rows';
BEGIN
    FOREACH tbl IN ARRAY ARRAY[
        'analyses_archived_duplicates',
        'files_archived_duplicates',
        'edges_archived_duplicates',
        'routes_archived_duplicates',
        'insights_archived_duplicates'
    ]
    LOOP
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

ALTER TABLE public.analyses
ADD CONSTRAINT analyses_project_id_key UNIQUE (project_id),
ADD CONSTRAINT analyses_stage_check CHECK ((status = 'queued') = (stage IS NULL)),
ADD CONSTRAINT analyses_started_check CHECK ((status = 'queued') = (started_at IS NULL)),
ADD CONSTRAINT analyses_complete_check CHECK (
    (status = 'complete') = (
        coverage IS NOT NULL
        AND detected_projects IS NOT NULL
        AND commit_sha IS NOT NULL
        AND schema_version IS NOT NULL
    )
);

-- The unique constraint's index serves lookups by project; this one is redundant.
DROP INDEX public.analyses_project_id_organization_id_idx;

-- Lock the analysis row and verify run ownership atomically before clearing files.
CREATE FUNCTION public.clear_analysis_files_for_run (
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

-- Lock the analysis row and verify run ownership atomically before inserting a file chunk.
CREATE FUNCTION public.insert_analysis_files_for_run (
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

-- Edges arrive keyed by path; this resolves both ends against the files
-- already stored for the analysis while holding the analysis lock and verifying
-- run ownership. An edge whose end isn't a stored file is a bug upstream, so
-- it aborts the call rather than being dropped.
CREATE FUNCTION public.insert_edges (
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

-- Only the pipeline's writer calls these.
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
EXECUTE ON FUNCTION public.claim_analysis (uuid, timestamptz)
FROM
    public,
    anon,
    authenticated;

GRANT
EXECUTE ON FUNCTION public.claim_analysis (uuid, timestamptz) TO service_role;
