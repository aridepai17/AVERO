import { StateMark } from '@/components/state-mark';
import { STALE_AFTER_MS, type Status } from '@/lib/pipeline/stages';

export type RowData = {
    id: string;
    repository: { owner: string; name: string } | null;
    commitSha: string | null;
    status: Status;
    error: string | null;
    stale: boolean;
    // Formatted by the server, so the browser renders the same text it was sent.
    created: { iso: string; ago: string };
    finished: { iso: string; ago: string } | null;
};

export function AnalysisRow({ row }: { row: RowData }) {
    const note = row.status === 'failed' ? row.error : null;

    return (
        <tr className="border-b border-line align-top hover:bg-raised">
            <td className="truncate px-3 py-1.5 font-mono">
                {row.repository ? (
                    <>
                        <span className="text-fg-muted">{row.repository.owner}/</span>
                        {row.repository.name}
                    </>
                ) : (
                    <span className="text-fg-muted">—</span>
                )}
                {(note || row.stale) && (
                    <span
                        className="mt-0.5 block truncate font-sans text-fg-muted"
                        title={note ?? undefined}
                    >
                        {row.stale
                            ? `No progress for over ${STALE_AFTER_MS / 60000} minutes${note ? ` — ${note}` : ''}`
                            : note}
                    </span>
                )}
            </td>
            <td className="px-3 py-1.5">
                <span
                    className={`flex items-center gap-1.5 ${row.status === 'queued' ? 'text-fg-muted' : 'text-fg'}`}
                >
                    <StateMark status={row.status} stale={row.stale} />
                    {row.stale ? 'stale' : row.status}
                </span>
            </td>
            <td className="hidden px-3 py-1.5 font-mono text-fg-muted sm:table-cell">
                {row.commitSha ? (
                    <span title={row.commitSha}>{row.commitSha.slice(0, 7)}</span>
                ) : (
                    '—'
                )}
            </td>
            <td className="px-3 py-1.5 text-right text-fg-muted tabular-nums">
                <time dateTime={row.created.iso} title={row.created.iso}>
                    {row.created.ago}
                </time>
            </td>
            <td className="hidden px-3 py-1.5 text-right text-fg-muted tabular-nums sm:table-cell">
                {row.finished ? (
                    <time dateTime={row.finished.iso} title={row.finished.iso}>
                        {row.finished.ago}
                    </time>
                ) : (
                    '—'
                )}
            </td>
        </tr>
    );
}
