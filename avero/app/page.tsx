export default function Home() {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-zinc-50 dark:bg-black">
      <h1 className="text-2xl font-semibold text-zinc-800 dark:text-zinc-200">
        Avero
      </h1>
      <p className="mt-2 text-sm text-zinc-500 dark:text-zinc-400">
        Dependency maps of public GitHub repositories
      </p>
    </div>
  );
}
