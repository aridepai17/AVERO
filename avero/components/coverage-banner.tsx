'use client';

import { useState } from 'react';
import type { Coverage, UnresolvedReason } from '@/lib/parser/types';

const REASON_LABELS: Record<UnresolvedReason, string> = {
    'non-literal-dynamic-import': 'non-literal dynamic import',
    'file-not-found': 'file not found',
    'directory-without-index': 'directory without index',
    'alias-target-not-found': 'alias target not found',
    'workspace-package-not-linked': 'workspace package not linked',
    'subpath-import-not-found': 'subpath import not found',
};

export function CoverageBanner({ coverage }: { coverage: Coverage }) {
    const [open, setOpen] = useState(false);

    const { found, parsed, skipped, skippedFiles } = coverage.files;
    const { seen, unresolved } = coverage.imports.total;

    if (skipped === 0 && unresolved === 0) return null;

    const totalUnits = found + seen;
    const resolvedUnits = parsed + (seen - unresolved);
    const rawPercent = totalUnits > 0 ? Math.floor((resolvedUnits / totalUnits) * 100) : 100;
    // A partial graph must never read 100%.
    const percent = Math.min(99, rawPercent);

    const parts: string[] = [];
    if (unresolved > 0) {
        parts.push(
            `${unresolved.toLocaleString('en')} of ${seen.toLocaleString('en')} imports unresolved`,
        );
    }
    if (skipped > 0) {
        parts.push(
            `${skipped.toLocaleString('en')} of ${found.toLocaleString('en')} files skipped`,
        );
    }

    const reasonEntries = Object.entries(coverage.imports.unresolvedByReason) as [
        UnresolvedReason,
        number,
    ][];

    return (
        <div role="status" className="border-line bg-surface shrink-0 border-b text-xs">
            <button
                type="button"
                aria-expanded={open}
                onClick={() => setOpen((v) => !v)}
                className="hover:bg-raised flex h-7 w-full items-center gap-2 px-3 text-left"
            >
                <span className="text-fg-muted w-2">{open ? '▾' : '▸'}</span>
                <span className="font-medium tabular-nums">
                    Partial graph · {percent}% coverage
                </span>
                <span className="text-fg-muted truncate tabular-nums">({parts.join(' · ')})</span>
                <span className="text-fg-muted ml-auto shrink-0 text-[11px]">
                    {open ? 'Hide details' : 'Details'}
                </span>
            </button>

            {open && (
                <div className="border-line text-fg-muted grid gap-3 border-t px-3 py-2 text-[11px] sm:grid-cols-2">
                    {unresolved > 0 && (
                        <div>
                            <p className="text-fg font-medium">
                                Unresolved imports ({unresolved.toLocaleString('en')})
                            </p>
                            <ul className="mt-1 space-y-0.5 tabular-nums">
                                {reasonEntries.map(([reason, count]) => (
                                    <li key={reason} className="flex justify-between gap-2">
                                        <span>{REASON_LABELS[reason] ?? reason}</span>
                                        <span>{count.toLocaleString('en')}</span>
                                    </li>
                                ))}
                            </ul>
                        </div>
                    )}
                    {skipped > 0 && (
                        <div>
                            <p className="text-fg font-medium">
                                Skipped files ({skipped.toLocaleString('en')})
                            </p>
                            <ul className="mt-1 space-y-0.5 font-mono">
                                {skippedFiles.slice(0, 6).map((f) => (
                                    <li key={f.path} className="truncate" title={f.detail}>
                                        {f.path}{' '}
                                        <span className="text-fg-muted font-sans">
                                            ({f.reason})
                                        </span>
                                    </li>
                                ))}
                                {skippedFiles.length > 6 && (
                                    <li className="font-sans tabular-nums">
                                        +{skippedFiles.length - 6} more skipped
                                    </li>
                                )}
                            </ul>
                        </div>
                    )}
                </div>
            )}
        </div>
    );
}
