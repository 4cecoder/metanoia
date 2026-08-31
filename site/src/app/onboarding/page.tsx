import Link from "next/link";
import { Badge, Button, Card, CardContent, CardDescription, CardHeader, CardTitle } from "@bytecats/ui-kit";
import { Breadcrumbs, PageNav } from "@/components/page-nav";

export default function OnboardingPage() {
  return (
    <div className="space-y-8 max-w-3xl">
      <Breadcrumbs
        items={[{ label: "Home", href: "/" }, { label: "Build" }, { label: "Onboarding" }]}
      />
      <header className="space-y-3">
        <Badge>Build — 5 min</Badge>
        <h1 className="text-3xl font-semibold tracking-tight">Onboarding</h1>
        <p className="text-muted-foreground">
          One topic: get from clone to running app. No architecture dump here — that&apos;s next page.
        </p>
      </header>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Prerequisites</CardTitle>
          <CardDescription>Same across macOS / Linux — Zig nightly, not stable</CardDescription>
        </CardHeader>
        <CardContent className="space-y-3 text-sm">
          <div className="rounded bg-muted p-3 font-mono text-xs">
            zig env  # check std_dir — should be master nightly<br />
            # if `zig` points at Homebrew stable, grab https://ziglang.org/download nightly
          </div>
          <ul className="list-disc pl-5 text-muted-foreground space-y-1">
            <li>macOS: <code>brew install gtk4 pango cairo glib sqlite3</code></li>
            <li>Debian/Ubuntu: <code>sudo apt install libgtk-4-dev libsqlite3-dev</code></li>
            <li>Fedora: <code>sudo dnf install gtk4-devel sqlite-devel</code></li>
          </ul>
          <p className="text-xs text-muted-foreground">
            See <code>docs/GEMINI.md</code> for Zig 0.16+ IO migration and <code>docs/ZIG_DISCOVERIES.md</code> for nightly gotchas.
          </p>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Run it</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <pre className="rounded bg-muted p-3 text-xs overflow-auto">{`git clone https://github.com/4cecoder/metanoia
cd metanoia
zig build run         # desktop
# or
./mobile/gradlew assembleDebug   # Android (Android Studio)
`}</pre>
          <p className="text-xs text-muted-foreground">
            First run seeds <code>data/bible.db</code> (118 MB LXXE+NKJV+interlinear) — tracked via <code>.gitignore: !data/bible.db</code>.
          </p>
        </CardContent>
      </Card>

      <div className="grid gap-4 sm:grid-cols-2">
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-sm">Next: Architecture</CardTitle></CardHeader>
          <CardContent className="text-xs text-muted-foreground">Kit (12 files), bible_db split, aikit sidecars</CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-sm">Stuck?</CardTitle></CardHeader>
          <CardContent className="text-xs text-muted-foreground">Check <Link href="/docs" className="underline">Docs</Link> or open an issue with <code>zig env</code> + <code>build.zig.zon:minimum_zig_version</code></CardContent>
        </Card>
      </div>

      <PageNav
        prev={{ href: "/learn/english", label: "Back: English rendering" }}
        next={{ href: "/docs/architecture", label: "Next: Docs — Architecture" }}
      />
    </div>
  );
}
