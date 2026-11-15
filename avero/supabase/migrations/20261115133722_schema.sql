-- Row-level security is on by default, not per table. A table that forgot to
-- enable it returns every organization's rows silently; this trigger makes
-- that impossible for anything created in public. It replaces the version the
-- Supabase dashboard installs, which logs and carries on if enabling fails.
-- Here a failure aborts the CREATE TABLE.
CREATE OR REPLACE FUNCTION public.rls_auto_enable () returns event_trigger language plpgsql security definer
SET
    search_path = pg_catalog AS $$
declare
  cmd record;
begin
  for cmd in
    select * from pg_event_trigger_ddl_commands()
    where command_tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      and object_type in ('table', 'partitioned table')
      and schema_name = 'public'
  loop
    execute format('alter table %s enable row level security', cmd.object_identity);
  end loop;
end;
$$;

DO $$
begin
  if not exists (select 1 from pg_event_trigger where evtname = 'ensure_rls') then
    create event trigger ensure_rls on ddl_command_end
      execute function public.rls_auto_enable();
  end if;
end;
$$;

-- Organizations live in Clerk. This row exists so everything else has a real
-- foreign key to cascade from: deleting it deletes the organization's data.
CREATE TABLE public.organizations (
    id text PRIMARY KEY, -- Clerk organization id, as it appears on the token
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.projects (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id text NOT NULL REFERENCES public.organizations (id) ON DELETE CASCADE,
    repo_owner text NOT NULL,
    repo_name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (organization_id, repo_owner, repo_name),
    UNIQUE (id, organization_id)
);

CREATE TYPE public.analysis_status AS enum('queued', 'parsing', 'complete', 'failed');

-- Children reference their parent by (id, organization_id), so a row can
-- never belong to a different organization than the thing it hangs off.
CREATE TABLE public.analyses (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id text NOT NULL REFERENCES public.organizations (id) ON DELETE CASCADE,
    project_id uuid NOT NULL,
    status public.analysis_status NOT NULL DEFAULT 'queued',
    commit_sha text,
    error text,
    created_at timestamptz NOT NULL DEFAULT now(),
    finished_at timestamptz,
    UNIQUE (id, organization_id),
    FOREIGN key (project_id, organization_id) REFERENCES public.projects (id, organization_id) ON DELETE CASCADE,
    CHECK ((status = 'failed') = (error IS NOT NULL)),
    CHECK (
        (status IN ('complete', 'failed')) = (finished_at IS NOT NULL)
    )
);

CREATE TABLE public.files (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id text NOT NULL REFERENCES public.organizations (id) ON DELETE CASCADE,
    analysis_id uuid NOT NULL,
    path text NOT NULL,
    -- Null means parsed. Anything skipped says why, so coverage can count it.
    skip_reason text,
    UNIQUE (analysis_id, path),
    UNIQUE (id, organization_id),
    UNIQUE (id, analysis_id, organization_id),
    FOREIGN key (analysis_id, organization_id) REFERENCES public.analyses (id, organization_id) ON DELETE CASCADE
);

-- Only resolved imports are edges; both ends are real files.
CREATE TABLE public.edges (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id text NOT NULL REFERENCES public.organizations (id) ON DELETE CASCADE,
    analysis_id uuid NOT NULL,
    source_file_id uuid NOT NULL,
    target_file_id uuid NOT NULL,
    kind text NOT NULL CHECK (
        kind IN (
            'import',
            're-export',
            'dynamic-import',
            'require'
        )
    ),
    specifier text NOT NULL,
    FOREIGN key (analysis_id, organization_id) REFERENCES public.analyses (id, organization_id) ON DELETE CASCADE,
    FOREIGN key (source_file_id, analysis_id, organization_id) REFERENCES public.files (id, analysis_id, organization_id) ON DELETE CASCADE,
    FOREIGN key (target_file_id, analysis_id, organization_id) REFERENCES public.files (id, analysis_id, organization_id) ON DELETE CASCADE
);

CREATE TABLE public.routes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id text NOT NULL REFERENCES public.organizations (id) ON DELETE CASCADE,
    analysis_id uuid NOT NULL,
    file_id uuid NOT NULL,
    method text NOT NULL,
    path text NOT NULL,
    FOREIGN key (analysis_id, organization_id) REFERENCES public.analyses (id, organization_id) ON DELETE CASCADE,
    FOREIGN key (file_id, analysis_id, organization_id) REFERENCES public.files (id, analysis_id, organization_id) ON DELETE CASCADE
);

CREATE TABLE public.explanations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id text NOT NULL REFERENCES public.organizations (id) ON DELETE CASCADE,
    file_id uuid NOT NULL,
    model text NOT NULL,
    body text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN key (file_id, organization_id) REFERENCES public.files (id, organization_id) ON DELETE CASCADE
);

CREATE TABLE public.file_roles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id text NOT NULL REFERENCES public.organizations (id) ON DELETE CASCADE,
    file_id uuid NOT NULL UNIQUE,
    role text NOT NULL,
    -- A role from convention is fact; one from the model is labelled as such.
    source text NOT NULL CHECK (source IN ('convention', 'model')),
    FOREIGN key (file_id, organization_id) REFERENCES public.files (id, organization_id) ON DELETE CASCADE
);

CREATE TABLE public.insights (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id text NOT NULL REFERENCES public.organizations (id) ON DELETE CASCADE,
    analysis_id uuid NOT NULL,
    body text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN key (analysis_id, organization_id) REFERENCES public.analyses (id, organization_id) ON DELETE CASCADE
);

-- Foreign keys aren't indexed automatically; cascades and joins need these.
-- Leading with organization_id also serves the policy predicate.
CREATE INDEX ON public.analyses (organization_id, created_at DESC);

CREATE INDEX ON public.analyses (project_id, organization_id);

CREATE INDEX ON public.files (analysis_id, organization_id);

CREATE INDEX ON public.files (organization_id);

CREATE INDEX ON public.edges (analysis_id, organization_id);

CREATE INDEX ON public.edges (source_file_id, organization_id);

CREATE INDEX ON public.edges (target_file_id, organization_id);

CREATE INDEX ON public.edges (organization_id);

CREATE INDEX ON public.routes (analysis_id, organization_id);

CREATE INDEX ON public.routes (file_id, organization_id);

CREATE INDEX ON public.routes (organization_id);

CREATE INDEX ON public.explanations (file_id, organization_id);

CREATE INDEX ON public.explanations (organization_id);

CREATE INDEX ON public.file_roles (file_id, organization_id);

CREATE INDEX ON public.file_roles (organization_id);

CREATE INDEX ON public.insights (analysis_id, organization_id);

CREATE INDEX ON public.insights (organization_id);

CREATE INDEX ON public.projects (organization_id);

-- The whole authorization layer: a row is visible when its organization is
-- the one on the Clerk session token. Clerk's v2 token carries it as o.id,
-- v1 as org_id. Read-only for now; nothing in the app writes yet, so there
-- are no write grants or write policies.
REVOKE ALL ON public.organizations,
public.projects,
public.analyses,
public.files,
public.edges,
public.routes,
public.explanations,
public.file_roles,
public.insights
FROM
    anon,
    authenticated;

GRANT
SELECT
    ON public.organizations,
    public.projects,
    public.analyses,
    public.files,
    public.edges,
    public.routes,
    public.explanations,
    public.file_roles,
    public.insights TO authenticated;

CREATE POLICY "members read their organization" ON public.organizations FOR
SELECT
    TO authenticated USING (
        id = (
            SELECT
                coalesce(
                    auth.jwt () -> 'o' ->> 'id',
                    auth.jwt () ->> 'org_id'
                )
        )
    );

CREATE POLICY "members read their organization's rows" ON public.projects FOR
SELECT
    TO authenticated USING (
        organization_id = (
            SELECT
                coalesce(
                    auth.jwt () -> 'o' ->> 'id',
                    auth.jwt () ->> 'org_id'
                )
        )
    );

CREATE POLICY "members read their organization's rows" ON public.analyses FOR
SELECT
    TO authenticated USING (
        organization_id = (
            SELECT
                coalesce(
                    auth.jwt () -> 'o' ->> 'id',
                    auth.jwt () ->> 'org_id'
                )
        )
    );

CREATE POLICY "members read their organization's rows" ON public.files FOR
SELECT
    TO authenticated USING (
        organization_id = (
            SELECT
                coalesce(
                    auth.jwt () -> 'o' ->> 'id',
                    auth.jwt () ->> 'org_id'
                )
        )
    );

CREATE POLICY "members read their organization's rows" ON public.edges FOR
SELECT
    TO authenticated USING (
        organization_id = (
            SELECT
                coalesce(
                    auth.jwt () -> 'o' ->> 'id',
                    auth.jwt () ->> 'org_id'
                )
        )
    );

CREATE POLICY "members read their organization's rows" ON public.routes FOR
SELECT
    TO authenticated USING (
        organization_id = (
            SELECT
                coalesce(
                    auth.jwt () -> 'o' ->> 'id',
                    auth.jwt () ->> 'org_id'
                )
        )
    );

CREATE POLICY "members read their organization's rows" ON public.explanations FOR
SELECT
    TO authenticated USING (
        organization_id = (
            SELECT
                coalesce(
                    auth.jwt () -> 'o' ->> 'id',
                    auth.jwt () ->> 'org_id'
                )
        )
    );

CREATE POLICY "members read their organization's rows" ON public.file_roles FOR
SELECT
    TO authenticated USING (
        organization_id = (
            SELECT
                coalesce(
                    auth.jwt () -> 'o' ->> 'id',
                    auth.jwt () ->> 'org_id'
                )
        )
    );

CREATE POLICY "members read their organization's rows" ON public.insights FOR
SELECT
    TO authenticated USING (
        organization_id = (
            SELECT
                coalesce(
                    auth.jwt () -> 'o' ->> 'id',
                    auth.jwt () ->> 'org_id'
                )
        )
    );

-- Fail the migration, loudly, if any table in public ended up without RLS.
DO $$
declare
  missing text;
begin
  select string_agg(c.relname, ', ') into missing
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity;
  if missing is not null then
    raise exception 'Row-level security is not enabled on: %', missing;
  end if;
end;
$$;
