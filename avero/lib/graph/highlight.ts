import type { Edge } from '../parser/types.ts';
import type { MapView } from './view.ts';

// What stays at full strength for a selection: the selected thing, its edges,
// and whatever those edges end on. Pure arithmetic over the view and the edge
// list, so it's instant.

export type Selection = { kind: 'group'; id: string } | { kind: 'file'; path: string } | null;

export type Highlight = {
    /** Endpoint keys (see endpointKey) that stay bright. */
    endpoints: ReadonlySet<string>;
    /** Objects shown bright in full, every row included. */
    objects: ReadonlySet<string>;
    /** Drawn edges into the selection. */
    incoming: ReadonlySet<string>;
    /** Drawn edges out of the selection. */
    outgoing: ReadonlySet<string>;
};

/** A folded node has one endpoint (handle ""); a panel has one per row, plus above and below. */
export function endpointKey(object: string, handle: string | null): string {
    return `${object}|${handle ?? ''}`;
}

export function highlight(
    view: MapView,
    edges: readonly Edge[],
    selection: Selection,
): Highlight | null {
    if (!selection) return null;
    const incoming = new Set<string>();
    const outgoing = new Set<string>();
    const endpoints = new Set<string>();

    if (selection.kind === 'group') {
        for (const e of view.edges) {
            if (e.target === selection.id) {
                incoming.add(e.id);
                endpoints.add(endpointKey(e.source, e.sourceHandle));
            }
            if (e.source === selection.id) {
                outgoing.add(e.id);
                endpoints.add(endpointKey(e.target, e.targetHandle));
            }
        }
        return { endpoints, objects: new Set([selection.id]), incoming, outgoing };
    }

    const key = (path: string) => {
        const at = view.endpointOf.get(path);
        return at ? endpointKey(at.object, at.handle) : undefined;
    };
    const self = key(selection.path);
    if (!self) return null;
    endpoints.add(self);

    // Neighbours and matching endpoints come from the file edges rather than
    // shared handles alone, so folded/overflow siblings don't light up
    // unrelated edges and same-panel neighbours still brighten.
    const incomingSources = new Set<string>();
    const outgoingTargets = new Set<string>();
    for (const e of edges) {
        if (e.source === selection.path) {
            const at = key(e.target);
            if (at) {
                endpoints.add(at);
                outgoingTargets.add(at);
            }
        }
        if (e.target === selection.path) {
            const at = key(e.source);
            if (at) {
                endpoints.add(at);
                incomingSources.add(at);
            }
        }
    }
    for (const e of view.edges) {
        const source = endpointKey(e.source, e.sourceHandle);
        const target = endpointKey(e.target, e.targetHandle);
        if (target === self && incomingSources.has(source)) incoming.add(e.id);
        if (source === self && outgoingTargets.has(target)) outgoing.add(e.id);
    }
    return { endpoints, objects: new Set(), incoming, outgoing };
}

/**
 * The one endpoint on the canvas that stands for a hovered file or group: its
 * row, the above/below row it's scrolled into, or the folded node holding it.
 */
export function hoverEndpoint(view: MapView, hover: Selection): string | null {
    if (!hover) return null;
    if (hover.kind === 'group') return endpointKey(hover.id, null);
    const at = view.endpointOf.get(hover.path);
    return at ? endpointKey(at.object, at.handle) : null;
}

export type CategoryFocus = {
    /** Endpoint keys standing for at least one file in the category. */
    endpoints: ReadonlySet<string>;
    /** Per canvas object, how many of its files are in the category. */
    counts: ReadonlyMap<string, number>;
};

// What a rail category leaves bright. Every file is counted once, against
// whatever stands for it on the canvas, so the objects' counts always add up
// to the rail's.
export function categoryFocus(
    view: MapView,
    category: string | null,
    /** Each file's rail category. */
    categoryOf: ReadonlyMap<string, string>,
): CategoryFocus | null {
    if (category === null) return null;
    const endpoints = new Set<string>();
    const counts = new Map<string, number>();
    for (const [path, at] of view.endpointOf) {
        if (categoryOf.get(path) !== category) continue;
        endpoints.add(endpointKey(at.object, at.handle));
        counts.set(at.object, (counts.get(at.object) ?? 0) + 1);
    }
    return { endpoints, counts };
}
