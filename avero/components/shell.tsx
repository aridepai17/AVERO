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
                    className="border-line bg-surface hidden min-h-0 overflow-y-auto border-r md:block"
                >
                    {rail}
                </nav>
            )}
            <section aria-label="Map" className="bg-canvas relative min-h-0 min-w-0">
                {map}
            </section>
            {hasDetail && (
                <aside
                    aria-label="Details"
                    className={`border-line bg-surface hidden min-h-0 overflow-y-auto border-l ${hasRail ? 'lg:block' : 'md:block'}`}
                >
                    {detail}
                </aside>
            )}
        </div>
    );
}
