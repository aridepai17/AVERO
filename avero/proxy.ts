import { clerkMiddleware } from "@clerk/nextjs/server";

const PUBLIC_PREFIXES = ["/sign-in", "/sign-up"];

function isPublicRoute(pathname: string): boolean {
    if (pathname === "/") return true;
    return PUBLIC_PREFIXES.some(
        (prefix) => pathname === prefix || pathname.startsWith(`${prefix}/`),
    );
}

export default clerkMiddleware(async (auth, req) => {
    if (!isPublicRoute(req.nextUrl.pathname)) {
        await auth.protect();
    }
});

export const config = {
    matcher: [
        "/((?!_next|[^?]*\\.(?:html?|css|js(?!on)|jpe?g|webp|png|gif|svg|ttf|woff2?|ico|csv|docx?|xlsx?|zip|webmanifest)).*)",
        "/(api|trpc)(.*)",
    ],
};
