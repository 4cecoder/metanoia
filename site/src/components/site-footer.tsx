import Link from "next/link";

export function SiteFooter() {
  return (
    <footer className="border-t py-8 text-sm text-muted-foreground">
      <div className="mx-auto max-w-6xl px-5 sm:px-6 lg:px-8 flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
        <p>
          Metanoia — Septuagint-first study.{" "}
          <Link href="/history" className="underline underline-offset-4 hover:text-foreground">
            Why LXX first?
          </Link>
        </p>
        <p className="flex flex-wrap gap-4">
          <a href="https://github.com/4cecoder/metanoia" className="hover:text-foreground">GitHub</a>
          <a href="https://github.com/4cecoder/ui-kit" className="hover:text-foreground">ui-kit</a>
          <a href="https://github.com/4cecoder/septcheck" className="hover:text-foreground">septcheck</a>
          <a
            href="https://cybertech99.github.io/FedoraBible/"
            target="_blank"
            rel="noreferrer"
            className="hover:text-foreground"
          >
            FedoraBible by cybertech99
          </a>
        </p>
      </div>
    </footer>
  );
}
