"use client";

import { type KeyboardEvent, useRef, useState } from "react";
import { THEME_COOKIE, THEMES, type Theme } from "@/lib/theme";

function applyTheme(theme: Theme) {
    document.documentElement.dataset.theme = theme;
    document.cookie = `${THEME_COOKIE}=${theme}; path=/; max-age=31536000; samesite=lax`;
}

export function ThemeControl({ initial }: { initial: Theme }) {
    const [theme, setTheme] = useState<Theme>(initial);
    const buttonRefs = useRef<Array<HTMLButtonElement | null>>([]);

    function choose(next: Theme) {
        setTheme(next);
        applyTheme(next);
    }

    function handleKeyDown(e: KeyboardEvent<HTMLButtonElement>, index: number) {
        let delta = 0;
        if (e.key === "ArrowRight" || e.key === "ArrowDown") delta = 1;
        else if (e.key === "ArrowLeft" || e.key === "ArrowUp") delta = -1;
        else return;

        e.preventDefault();
        const nextIndex = (index + delta + THEMES.length) % THEMES.length;
        const nextTheme = THEMES[nextIndex];
        choose(nextTheme);
        buttonRefs.current[nextIndex]?.focus();
    }

    return (
        <div
            role="radiogroup"
            aria-label="Theme"
            className="flex h-6 items-center rounded border border-line text-[0.6875rem]"
        >
            {THEMES.map((t, index) => {
                const selected = theme === t;
                return (
                    <button
                        key={t}
                        ref={(el) => {
                            buttonRefs.current[index] = el;
                        }}
                        type="button"
                        role="radio"
                        aria-checked={selected}
                        tabIndex={selected ? 0 : -1}
                        onClick={() => choose(t)}
                        onKeyDown={(e) => handleKeyDown(e, index)}
                        className={`h-full px-2 first:rounded-l last:rounded-r ${
                            selected
                                ? "bg-raised text-fg"
                                : "text-fg-muted hover:text-fg"
                        }`}
                    >
                        {t}
                    </button>
                );
            })}
        </div>
    );
}
