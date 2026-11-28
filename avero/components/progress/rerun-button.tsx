'use client';

import { useState, useTransition } from 'react';
import { rerunAnalysis } from '@/app/(workspace)/actions';

export function RerunButton({
    analysisId,
    onStarted,
    label = 'Re-run',
}: {
    analysisId: string;
    onStarted: () => void;
    label?: string;
}) {
    const [pending, startTransition] = useTransition();
    const [error, setError] = useState<string | null>(null);
    return (
        <span className="flex items-center gap-2">
            {error && <span className="text-fg-muted text-xs">{error}</span>}
            <button
                type="button"
                disabled={pending}
                onClick={() =>
                    startTransition(async () => {
                        const result = await rerunAnalysis(analysisId);
                        setError(result.error);
                        if (!result.error) onStarted();
                    })
                }
                className="border-line hover:bg-raised disabled:text-fg-muted h-6 rounded border px-2 text-xs"
            >
                {pending ? 'Starting…' : label}
            </button>
        </span>
    );
}
