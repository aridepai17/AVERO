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

-- Deduplicate per project if multiple rows exist before adding UNIQUE (project_id).
DELETE FROM public.analyses a USING public.analyses b
WHERE
    a.project_id = b.project_id
    AND (a.created_at, a.id) < (b.created_at, b.id);

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
-- without fabricating parsed file metrics; legacy edges lack line/type_only data.
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

DELETE FROM public.edges;

ALTER TABLE public.edges
ADD COLUMN type_only boolean NOT NULL,
ADD COLUMN line integer NOT NULL,
ADD CONSTRAINT edges_unique_key UNIQUE (analysis_id, source_file_id, target_file_id, kind);

-- Edges arrive keyed by path; this resolves both ends against the files
-- already stored for the analysis. An edge whose end isn't a stored file is
-- a bug upstream, so it aborts the call rather than being dropped.
CREATE FUNCTION public.insert_edges (p_analysis_id uuid, p_edges jsonb) RETURNS integer LANGUAGE plpgsql
SET
    search_path = '' AS $$
declare
  expected integer := jsonb_array_length(p_edges);
  inserted integer;
begin
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

-- Only the pipeline's writer calls this.
REVOKE
EXECUTE ON FUNCTION public.insert_edges (uuid, jsonb)
FROM
    public,
    anon,
    authenticated;

GRANT
EXECUTE ON FUNCTION public.insert_edges (uuid, jsonb) TO service_role;
