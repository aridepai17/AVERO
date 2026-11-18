import { fallbackAdapter } from './fallback.ts';
import type { FrameworkAdapter, ProjectInfo } from './types.ts';

// Only the fallback adapter is registered in Phase 3. Framework-specific
// adapters are added in later phases while keeping the fallback last.
const ADAPTERS: readonly FrameworkAdapter[] = [fallbackAdapter];

export function selectAdapter(project: ProjectInfo): FrameworkAdapter {
    return ADAPTERS.find((adapter) => adapter.detect(project)) ?? fallbackAdapter;
}

export { fallbackAdapter };
export type { FrameworkAdapter, ProjectInfo };
