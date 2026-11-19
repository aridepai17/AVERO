import { categoryLabel, countByCategory } from '@/lib/graph/categories';
import type { ParsedFile } from '@/lib/parser/types';
import { CategorySwatch } from './map/swatch';

export function CategoryRail({ files }: { files: readonly ParsedFile[] }) {
    const categories = countByCategory(files.map((f) => f.path));

    return (
        <div className="py-2">
            <h2 className="px-3 pb-1 text-[11px] text-fg-muted">
                Categories <span className="tabular-nums">· {files.length} files</span>
            </h2>
            <ul>
                {categories.map(({ category, count }) => (
                    <li key={category} className="flex h-6 items-center gap-2 px-3 text-xs">
                        <CategorySwatch category={category} />
                        <span className="flex-1 truncate font-mono text-[11px]">
                            {categoryLabel(category)}
                        </span>
                        <span className="text-fg-muted tabular-nums">{count}</span>
                    </li>
                ))}
            </ul>
        </div>
    );
}
