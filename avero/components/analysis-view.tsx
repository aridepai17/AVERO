'use client';

import { useCallback, useMemo, useState } from 'react';
import { CategoryRail } from '@/components/category-rail';
import { CoverageBanner } from '@/components/coverage-banner';
import { DetailPane, type RepositoryFacts, type Tab } from '@/components/detail-pane';
import { DependencyMap } from '@/components/map/dependency-map';
import { Shell } from '@/components/shell';
import { foldDirectories } from '@/lib/graph/fold';
import type { Selection } from '@/lib/graph/highlight';
import type { Direction } from '@/lib/graph/reach';
import { clampOffset, groupId, MAX_ROWS, rankGroupFiles } from '@/lib/graph/view';
import type { Coverage, Edge, ParsedFile } from '@/lib/parser/types';

export function AnalysisView({
    files,
    edges,
    coverage,
    repository,
}: {
    files: ParsedFile[];
    edges: Edge[];
    coverage: Coverage;
    repository: RepositoryFacts;
}) {
    const folding = useMemo(() => foldDirectories(files), [files]);
    const byPath = useMemo(() => new Map(files.map((f) => [f.path, f])), [files]);
    const [open, setOpen] = useState<Map<string, number>>(() => new Map());
    const [selection, setSelection] = useState<Selection>(null);
    const [hover, setHover] = useState<Selection>(null);
    const [tab, setTab] = useState<Tab>('structure');
    const [walk, setWalk] = useState<Direction | null>(null);
    const [insightsOpen, setInsightsOpen] = useState(false);
    const [category, setCategory] = useState<string | null>(null);
    const [refit, setRefit] = useState(0);

    const handleToggleCategory = useCallback(
        (c: string) => setCategory((prev) => (prev === c ? null : c)),
        [],
    );

    const handleOpen = useCallback((id: string) => {
        setOpen((prev) => new Map(prev).set(id, 0));
        setSelection({ kind: 'group', id });
        setRefit((r) => r + 1);
    }, []);

    const handleClose = useCallback(
        (id: string) => {
            setOpen((prev) => {
                const next = new Map(prev);
                next.delete(id);
                return next;
            });
            setSelection((prev) => {
                if (prev?.kind === 'group') return prev.id === id ? null : prev;
                if (prev?.kind === 'file') {
                    const dir = folding.groupOf.get(prev.path);
                    return dir !== undefined && groupId(dir) === id ? null : prev;
                }
                return prev;
            });
        },
        [folding],
    );

    const handleSelectFile = useCallback((path: string) => {
        setSelection((prev) =>
            prev?.kind === 'file' && prev.path === path ? null : { kind: 'file', path },
        );
    }, []);

    const handleReveal = useCallback(
        (path: string) => {
            setSelection({ kind: 'file', path });
            setHover(null);

            const dir = folding.groupOf.get(path);
            if (dir === undefined) return;
            const group = folding.groups.find((g) => g.dir === dir);
            if (!group) return;

            const id = groupId(dir);
            const ranked = rankGroupFiles(group, byPath);
            const index = ranked.indexOf(path);
            const targetOffset =
                index === -1 ? 0 : clampOffset(index - Math.floor(MAX_ROWS / 2), ranked.length);

            setOpen((prev) => {
                const current = prev.get(id);
                if (current === undefined) {
                    setRefit((r) => r + 1);
                    return new Map(prev).set(id, targetOffset);
                }
                if (index !== -1 && (index < current || index >= current + MAX_ROWS)) {
                    return new Map(prev).set(id, targetOffset);
                }
                return prev;
            });
        },
        [folding, byPath],
    );

    const handleScroll = useCallback((id: string, offset: number) => {
        setOpen((prev) => (prev.has(id) ? new Map(prev).set(id, offset) : prev));
    }, []);

    const handleDeselect = useCallback(() => setSelection(null), []);

    return (
        <Shell
            rail={<CategoryRail files={files} active={category} onToggle={handleToggleCategory} />}
            map={
                <div className="absolute inset-0 flex flex-col">
                    <CoverageBanner coverage={coverage} />
                    <div className="relative min-h-0 flex-1">
                        <DependencyMap
                            files={files}
                            edges={edges}
                            folding={folding}
                            open={open}
                            selection={selection}
                            hover={hover}
                            refit={refit}
                            category={category}
                            onOpen={handleOpen}
                            onClose={handleClose}
                            onSelectFile={handleSelectFile}
                            onScroll={handleScroll}
                            onHover={setHover}
                            onDeselect={handleDeselect}
                        />
                    </div>
                </div>
            }
            detail={
                <DetailPane
                    files={files}
                    byPath={byPath}
                    edges={edges}
                    folding={folding}
                    repository={repository}
                    selection={selection}
                    hover={hover}
                    tab={tab}
                    onTab={setTab}
                    walk={walk}
                    onWalk={setWalk}
                    insightsOpen={insightsOpen}
                    onInsightsOpen={setInsightsOpen}
                    onReveal={handleReveal}
                    onHover={setHover}
                />
            }
        />
    );
}
