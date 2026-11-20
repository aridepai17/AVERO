import { readFileSync } from 'node:fs';
import { basename, join } from 'node:path';
import type { RepositoryFacts } from '@/components/detail-pane';
import { deserializeParseResult } from '@/lib/parser/contract';
import { PreviewCanvas } from './preview-canvas';

export default function PreviewPage() {
    const raw = readFileSync(join(process.cwd(), 'app/preview/analysis.json'), 'utf8');
    const analysis = deserializeParseResult(raw);

    const rootName = basename(analysis.root);
    const repository: RepositoryFacts = {
        name: rootName && rootName !== '.' ? rootName : 'Repository',
        projects: analysis.projects,
        skipped: analysis.coverage.files.skipped,
        unresolved: analysis.coverage.imports.total.unresolved,
        routes: 0,
    };

    return (
        <div className="flex h-screen flex-col">
            <PreviewCanvas files={analysis.files} edges={analysis.edges} repository={repository} />
        </div>
    );
}
