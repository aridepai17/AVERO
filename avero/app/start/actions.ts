"use server";

import { auth, clerkClient } from "@clerk/nextjs/server";

const inflight = new Map<string, Promise<string>>();

async function findOrCreateOrganization(userId: string): Promise<string> {
    const clerk = await clerkClient();
    const memberships = await clerk.users.getOrganizationMembershipList({
        userId,
        limit: 1,
    });
    const existing = memberships.data[0];
    if (existing) return existing.organization.id;

    const user = await clerk.users.getUser(userId);
    const who =
        user.firstName ??
        user.username ??
        user.primaryEmailAddress?.emailAddress.split("@")[0];
    const org = await clerk.organizations.createOrganization({
        name: who ? `${who}'s team` : "My team",
        createdBy: userId,
    });
    return org.id;
}

// The one place the app talks to Clerk's API, and only on the way in: a
// person with no active organization either joins one they already belong to
// (e.g. accepted an invitation) or gets one created for them. After this,
// everything reads the organization off the session token.
export async function resolveOrganization(): Promise<string> {
    const { userId } = await auth();
    if (!userId) throw new Error("Not signed in");

    const pending = inflight.get(userId);
    if (pending) return pending;

    const promise = findOrCreateOrganization(userId).finally(() => {
        if (inflight.get(userId) === promise) {
            inflight.delete(userId);
        }
    });
    inflight.set(userId, promise);
    return promise;
}
