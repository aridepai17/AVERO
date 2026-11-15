import type { Enums } from '../supabase/database.types';

export type Status = Enums<'analysis_status'>;

export const STALE_AFTER_MS = 5 * 60 * 1000;

export function isStale(row: { status: Status; created_at: string }, now: number): boolean {
    if (row.status === 'queued' || row.status === 'parsing') {
        return now - Date.parse(row.created_at) > STALE_AFTER_MS;
    }
    return false;
}
