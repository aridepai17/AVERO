import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { deserializeParseResult } from '@/lib/parser/contract';
import { PreviewCanvas } from './preview-canvas';

export default function PreviewPage() {
    const raw = readFileSync(join(process.cwd(), 'app/preview/analysis.json'), 'utf8');
    const { files, edges } = deserializeParseResult(raw);

    return (
        <div className="flex h-screen flex-col">
            <PreviewCanvas files={files} edges={edges} />
        </div>
    );
}
