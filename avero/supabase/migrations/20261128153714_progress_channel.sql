-- Live progress. Each analysis has a private broadcast channel,
-- "analysis:<id>", and the database publishes to it when a run moves.
-- The channel pattern is declared here, before anything publishes to it: a
-- private channel with no select policy on realtime.messages accepts the
-- broadcast and delivers it to nobody, silently. This is also who may
-- subscribe. The subquery on analyses runs under that table's own policy, so
-- the topic of another organization's analysis matches no row and the join
-- is refused, exactly as its rows aren't selectable. Topics are compared as
-- text so a malformed topic is refused rather than failing a uuid cast.
CREATE POLICY "members receive their organization's analysis progress" ON realtime.messages FOR
SELECT
    TO authenticated USING (
        realtime.messages.extension = 'broadcast'
        AND EXISTS (
            SELECT
                1
            FROM
                public.analyses a
            WHERE
                'analysis:' || a.id::text = (
                    SELECT
                        realtime.topic ()
                )
        )
    );

-- No insert policy: browsers listen on these channels and never send. Only
-- the trigger below publishes.
-- The stage and its message, not the row. On failure the message is the
-- reason, so a subscriber shows what arrives without interpreting it.
-- Security definer because it runs inside the pipeline's writes, and
-- publishing is the database's act, not the writer's.
CREATE FUNCTION public.publish_analysis_progress () RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET
    search_path = '' AS $$
begin
  perform realtime.send(
    jsonb_build_object(
      'status', new.status,
      'stage', new.stage,
      'message', case when new.status = 'failed' then new.error else new.stage_message end
    ),
    'progress',
    'analysis:' || new.id::text,
    true
  );
  return null;
end;
$$;

REVOKE
EXECUTE ON FUNCTION public.publish_analysis_progress ()
FROM
    public,
    anon,
    authenticated;

-- On our own table, never on the realtime machinery.
CREATE TRIGGER publish_progress
AFTER UPDATE OF status,
stage,
stage_message,
error ON public.analyses FOR EACH ROW WHEN (
    OLD.status IS DISTINCT FROM NEW.status
    OR OLD.stage IS DISTINCT FROM NEW.stage
    OR OLD.stage_message IS DISTINCT FROM NEW.stage_message
)
EXECUTE FUNCTION public.publish_analysis_progress ();
