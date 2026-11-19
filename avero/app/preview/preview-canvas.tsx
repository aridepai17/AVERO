'use client';

import { useCallback, useMemo, useState } from 'react';
import { CategoryRail } from '@/components/category-rail';
import { DependencyMap } from '@/components/map/dependency-map';
import { Shell } from '@/components/shell';
import { foldDirectories } from '@/lib/graph/fold';
import type { Selection } from '@/lib/graph/highlight';
import type { Edge, ParsedFile } from '@/lib/parser/types';

export function PreviewCanvas({ files, edges }: { files: ParsedFile[]; edges: Edge[] }) {
    const folding = useMemo(() => foldDirectories(files), [files]);
    const [open, setOpen] = useState<Map<string, number>>(() => new Map());
    const [selection, setSelection] = useState<Selection>(null);
    const [hover, setHover] = useState<Selection>(null);
    const [refit, setRefit] = useState(0);

    const handleOpen = useCallback((id: string) => {
        setOpen((prev) => new Map(prev).set(id, 0));
        setRefit((r) => r + 1);
    }, []);

    const handleClose = useCallback((id: string) => {
        setOpen((prev) => {
            const next = new Map(prev);
            next.delete(id);
            return next;
        });
        setSelection((prev) => (prev?.kind === 'group' && prev.id === id ? null : prev));
    }, []);

    const handleSelectFile = useCallback((path: string) => {
        setSelection((prev) =>
            prev?.kind === 'file' && prev.path === path ? null : { kind: 'file', path },
        );
    }, []);

    const handleScroll = useCallback((id: string, offset: number) => {
        setOpen((prev) => (prev.has(id) ? new Map(prev).set(id, offset) : prev));
    }, []);

    const handleDeselect = useCallback(() => setSelection(null), []);

    return (
        <Shell
            rail={<CategoryRail files={files} />}
            map={
                <DependencyMap
                    files={files}
                    edges={edges}
                    folding={folding}
                    open={open}
                    selection={selection}
                    hover={hover}
                    refit={refit}
                    onOpen={handleOpen}
                    onClose={handleClose}
                    onSelectFile={handleSelectFile}
                    onScroll={handleScroll}
                    onHover={setHover}
                    onDeselect={handleDeselect}
                />
            }
        />
    );
}
