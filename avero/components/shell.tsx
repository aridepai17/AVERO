import type { ReactNode } from 'react';

export function Shell({
    rail,
    map,
    detail,
}: {
    rail?: ReactNode;
    map?: ReactNode;
    detail?: ReactNode;
}) {
    const hasRail = rail != null && rail !== false;
    const hasDetail = detail != null && detail !== false;

    const cols =
        hasRail && hasDetail
            ? 'grid-cols-[minmax(0,1fr)] md:grid-cols-[11rem_minmax(0,1fr)] lg:grid-cols-[11rem_minmax(0,1fr)_20rem]'
            : hasRail
              ? 'grid-cols-[minmax(0,1fr)] md:grid-cols-[11rem_minmax(0,1fr)]'
              : hasDetail
                ? 'grid-cols-[minmax(0,1fr)] md:grid-cols-[minmax(0,1fr)_20rem]'
                : 'grid-cols-[minmax(0,1fr)]';

    return (
        <div className={`grid min-h-0 flex-1 ${cols}`}>
            {hasRail && (
                <nav
                    aria-label="Categories"
                    className="hidden min-h-0 overflow-y-auto border-r border-line bg-surface md:block"
                >
                    {rail}
                </nav>
            )}
            <section aria-label="Map" className="relative min-h-0 min-w-0 bg-canvas">
                {map}
            </section>
            {hasDetail && (
                <aside
                    aria-label="Details"
                    className={`hidden min-h-0 overflow-y-auto border-l border-line bg-surface ${hasRail ? 'lg:block' : 'md:block'}`}
                >
                    {detail}
                </aside>
            )}
        </div>
    );
}
