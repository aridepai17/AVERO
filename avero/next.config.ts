import type { NextConfig } from "next";
import { assertEnv } from "./lib/env";

if (!process.env.SKIP_ENV_VALIDATION) {
    assertEnv();
}

const nextConfig: NextConfig = {
    turbopack: {
        rules: {
            "*.css": {
                loaders: ["@tailwindcss/turbopack"],
                as: "*.css",
            },
        },
    },
};

export default nextConfig;
