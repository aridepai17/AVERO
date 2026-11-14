import { auth } from "@clerk/nextjs/server";

export default async function DashboardPage() {
    const { sessionClaims } = await auth();

    // Read off the token, never fetched from Clerk. If the claim is missing the
    // session token hasn't been customised yet, and that should be obvious.
    const orgName = sessionClaims?.org_name;
    if (!orgName) {
        throw new Error(
            'Session token has no org_name claim. Add "org_name": "{{org.name}}" in Clerk → Sessions → Customize session token.',
        );
    }

    return (
        <div className="flex h-full flex-col">
            <div className="flex h-9 shrink-0 items-center gap-4 border-b border-line px-3">
                <h1 className="text-[13px] font-semibold">{orgName}</h1>
                <span className="text-xs text-fg-muted tabular-nums">
                    0 analyses
                </span>
            </div>

            <div className="px-3 py-10 text-xs text-fg-muted">
                <p className="text-fg">No analyses yet.</p>
                <p className="mt-1">
                    Paste a public GitHub repository above to map it.
                </p>
            </div>
        </div>
    );
}
