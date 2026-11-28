import type { SupabaseClient } from '@supabase/supabase-js';
import type { Coverage, ParseResult } from '../parser/index.ts';
import type { Database, Json } from '../supabase/database.types.ts';
import { SupersededError } from './run.ts';

type Db = SupabaseClient<Database>;

// Each request stays well inside PostgREST's statement timeout. Chunks aren't
// one transaction, but each write locks the analysis row and verifies
// started_at atomically, nothing reads as complete until the final update, and
// a failure part-way marks the run failed.
const FILE_CHUNK = 1000;
const EDGE_CHUNK = 2000;

// The skipped-file list lives in the files table; storing it twice would let
// the two disagree.
export type StoredCoverage = Omit<Coverage, 'files'> & {
    files: Omit<Coverage['files'], 'skippedFiles'>;
};

function isSupersededError(error: { code?: string; message?: string }): boolean {
    return error.code === 'P0002' || Boolean(error.message?.includes('SUPERSEDED:'));
}

export async function storeResult(
    db: Db,
    analysis: { id: string; organizationId: string; claimedStartedAt: string },
    result: ParseResult,
): Promise<void> {
    await assertOwnsRun(db, analysis);

    // A re-run replaces what the last run stored; edges go with their files.
    const cleared = await db.rpc('clear_analysis_files_for_run', {
        p_analysis_id: analysis.id,
        p_claimed_started_at: analysis.claimedStartedAt,
    });
    if (cleared.error) {
        if (isSupersededError(cleared.error)) {
            throw new SupersededError(`Analysis ${analysis.id} was taken over by a newer run`);
        }
        throw new Error(`Clearing the previous run's files failed: ${cleared.error.message}`);
    }

    const rows: Database['public']['Tables']['files']['Insert'][] = [
        ...result.files.map((f) => ({
            organization_id: analysis.organizationId,
            analysis_id: analysis.id,
            path: f.path,
            module: f.module,
            lines: f.lines,
            bytes: f.bytes,
            hash: f.hash,
            fan_in: f.fanIn,
            fan_out: f.fanOut,
        })),
        ...result.coverage.files.skippedFiles.map((f) => ({
            organization_id: analysis.organizationId,
            analysis_id: analysis.id,
            path: f.path,
            skip_reason: f.reason,
            skip_detail: f.detail,
        })),
    ];

    for (let i = 0; i < rows.length; i += FILE_CHUNK) {
        const { error } = await db.rpc('insert_analysis_files_for_run', {
            p_analysis_id: analysis.id,
            p_claimed_started_at: analysis.claimedStartedAt,
            p_rows: rows.slice(i, i + FILE_CHUNK) as unknown as Json,
        });
        if (error) {
            if (isSupersededError(error)) {
                throw new SupersededError(`Analysis ${analysis.id} was taken over by a newer run`);
            }
            if (error.code === '23505') await assertOwnsRun(db, analysis);
            throw new Error(`Storing files failed: ${error.message}`);
        }
    }

    // Ends are matched to stored files by path in the database, which refuses
    // the whole chunk if any edge doesn't match.
    const edges = result.edges.map((e) => ({
        source: e.source,
        target: e.target,
        kind: e.kind,
        specifier: e.specifier,
        type_only: e.typeOnly,
        line: e.line,
    }));

    for (let i = 0; i < edges.length; i += EDGE_CHUNK) {
        const { error } = await db.rpc('insert_edges', {
            p_analysis_id: analysis.id,
            p_claimed_started_at: analysis.claimedStartedAt,
            p_edges: edges.slice(i, i + EDGE_CHUNK),
        });
        if (error) {
            if (isSupersededError(error)) {
                throw new SupersededError(`Analysis ${analysis.id} was taken over by a newer run`);
            }
            throw new Error(`Storing edges failed: ${error.message}`);
        }
    }
}

async function assertOwnsRun(
    db: Db,
    analysis: { id: string; claimedStartedAt: string },
): Promise<void> {
    const { data, error } = await db
        .from('analyses')
        .select('id')
        .eq('id', analysis.id)
        .eq('started_at', analysis.claimedStartedAt)
        .maybeSingle();
    if (error)
        throw new Error(`Verifying analysis ${analysis.id} ownership failed: ${error.message}`);
    if (!data) throw new SupersededError(`Analysis ${analysis.id} was taken over by a newer run`);
}

export function storedCoverage(coverage: Coverage): Json {
    const { found, parsed, skipped, excludedDirectories } = coverage.files;
    const stored: StoredCoverage = {
        ...coverage,
        files: { found, parsed, skipped, excludedDirectories },
    };
    return stored;
}
