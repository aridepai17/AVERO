import { categoryLabel, countByCategory } from '@/lib/graph/categories';
import type { ParsedFile } from '@/lib/parser/types';
import { CategorySwatch } from './map/swatch';

export function CategoryRail({
    files,
    active,
    onToggle,
}: {
    files: readonly ParsedFile[];
    active: string | null;
    onToggle: (category: string) => void;
}) {
    const categories = countByCategory(files.map((f) => f.path));

    return (
        <div className="py-2">
            <h2 className="text-fg-muted px-3 pb-1 text-[11px]">
                Categories <span className="tabular-nums">· {files.length} files</span>
            </h2>
            <ul>
                {categories.map(({ category, count }) => {
                    const on = active === category;
                    return (
                        <li key={category}>
                            <button
                                type="button"
                                aria-pressed={on}
                                onClick={() => onToggle(category)}
                                className={`flex h-6 w-full items-center gap-2 px-3 text-left text-xs ${
                                    on
                                        ? 'bg-accent/15 shadow-[inset_2px_0_0_var(--accent)]'
                                        : active
                                          ? 'text-fg-muted hover:bg-raised'
                                          : 'hover:bg-raised'
                                }`}
                            >
                                <CategorySwatch category={category} />
                                <span className="flex-1 truncate font-mono text-[11px]">
                                    {categoryLabel(category)}
                                </span>
                                <span className="text-fg-muted tabular-nums">{count}</span>
                            </button>
                        </li>
                    );
                })}
            </ul>
        </div>
    );
}
