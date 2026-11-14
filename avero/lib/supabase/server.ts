import { auth } from "@clerk/nextjs/server";
import { createClient } from "@supabase/supabase-js";
import { env } from "../env";

// Single session system: Clerk owns authentication, and Supabase receives the
// signed-in user's Clerk session JWT via `accessToken` so Postgres RLS policies
// can enforce `auth.jwt() ->> 'org_id'` without a second cookie session.
export function createServerSupabaseClient() {
    return createClient(
        env("NEXT_PUBLIC_SUPABASE_URL"),
        env("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY"),
        {
            accessToken: async () => {
                const { getToken } = await auth();
                return (await getToken()) ?? null;
            },
        },
    );
}
