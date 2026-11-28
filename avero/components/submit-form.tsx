'use client';

import { useActionState } from 'react';
import { submitAnalysis, type FormState } from '@/app/(workspace)/actions';

const INITIAL: FormState = { error: null };

export function SubmitForm() {
    const [state, action, pending] = useActionState(submitAnalysis, INITIAL);
    return (
        <form action={action} className="flex min-w-0 items-center gap-2">
            <input
                name="url"
                required
                autoComplete="off"
                spellCheck={false}
                placeholder="github.com/owner/repo"
                aria-label="Public GitHub repository URL"
                aria-invalid={state.error ? true : undefined}
                className="border-line bg-canvas placeholder:text-fg-muted focus:border-accent h-6 w-72 min-w-0 rounded border px-2 font-mono text-xs outline-none"
            />
            <button
                type="submit"
                disabled={pending}
                className="bg-accent text-accent-fg h-6 shrink-0 rounded px-2 text-xs disabled:opacity-60"
            >
                {pending ? 'Starting…' : 'Analyse'}
            </button>
            {state.error && (
                <span role="alert" className="text-fg truncate text-xs">
                    {state.error}
                </span>
            )}
        </form>
    );
}
