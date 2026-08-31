import Link from "next/link";
import {
  Badge,
  Button,
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@bytecats/ui-kit";
import {
  BookOpen,
  Boxes,
  ExternalLink,
  Github,
  Hash,
  Heart,
  Languages,
  Link2,
  ScrollText,
  Search,
  Terminal,
} from "lucide-react";

function CopyButton({ text }: { text: string }) {
  // Client islands are small — inline handler avoids extra component boundary.
  return (
    <button
      onClick={() => navigator.clipboard.writeText(text)}
      className="rounded-md border bg-background px-2 py-1 text-xs hover:bg-accent"
      aria-label="Copy"
    >
      Copy
    </button>
  );
}

export default function Home() {
  return (
    <div className="space-y-16">
      {/* Hero — Septuagint-first framing (inverse Logos). */}
      <section className="space-y-6 py-6">
        <div className="flex flex-wrap gap-2">
          <Badge variant="secondary">LXX + GNT as primary roots</Badge>
          <Badge variant="outline">Masoretic as comparison — buried, not deleted</Badge>
          <Badge>Zig + GTK4 · Kotlin · Swift</Badge>
        </div>
        <h1 className="text-balance text-4xl font-semibold tracking-tight sm:text-5xl">
          Study the Bible the disciples read.
        </h1>
        <p className="max-w-2xl text-pretty text-lg text-muted-foreground">
          Metanoia is Septuagint-first by default — Brenton&apos;s LXX English (LXXE) + Greek
          interlinear (LXX/Apostolic) paired with the Greek New Testament (GNT). Hebrew
          Masoretic stays available as a comparison text, tucked in <em>Advanced — Bible Tradition</em>{" "}
          (<code className="rounded bg-muted px-1 py-0.5">src/models/config.zig:86-96</code>) — the
          inverse of Logos, which buries LXX under MT.
        </p>
        <div className="flex flex-wrap gap-3">
          <Button asChild>
            <Link href="/onboarding">Onboard in 5 min</Link>
          </Button>
          <Button variant="outline" asChild>
            <Link href="/history">Why LXX first? — timeline</Link>
          </Button>
          <Button variant="ghost" asChild>
            <a href="https://github.com/4cecoder/metanoia" target="_blank" rel="noreferrer">
              <Github className="mr-2 size-4" /> View source
            </a>
          </Button>
        </div>
        <div className="rounded-lg border bg-card p-3 text-sm">
          <div className="font-medium">One-liner for new devs (Fedora-style `npm run setup`)</div>
          <pre className="mt-2 overflow-auto rounded bg-muted p-3 text-xs">
            {`brew install gtk4 pango cairo glib sqlite3   # macOS — or apt/dnf on Linux
# Zig: use master nightly from ziglang.org/download (Homebrew zig is too old — see docs/GEMINI.md)
git clone https://github.com/4cecoder/metanoia && cd metanoia
zig build run`}
          </pre>
        </div>
      </section>

      {/* How it works — teaser -> links to dedicated page */}
      <section className="space-y-4">
        <h2 className="text-2xl font-semibold tracking-tight">How links work</h2>
        <p className="max-w-2xl text-muted-foreground">
          Two shapes, same engine — <code>src/main.zig:load_chapter_into_study</code>. Full deep-link
          reference lives on its own page so the homepage stays clean.
        </p>
        <div className="grid gap-4 md:grid-cols-3">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-base">
                <Link2 className="size-4" /> HTTPS
              </CardTitle>
              <CardDescription>Verified App Link</CardDescription>
            </CardHeader>
            <CardContent>
              <pre className="rounded bg-muted p-2 text-xs">https://metanoia.bytecats.codes/bible/John/3/16</pre>
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-base">
                <Hash className="size-4" /> metanoia://
              </CardTitle>
              <CardDescription>Direct intent</CardDescription>
            </CardHeader>
            <CardContent>
              <pre className="rounded bg-muted p-2 text-xs">metanoia://bible/John/3/16</pre>
            </CardContent>
          </Card>
          <Card className="flex flex-col justify-between">
            <CardHeader>
              <CardTitle className="text-base">See all patterns →</CardTitle>
              <CardDescription>Abbreviations, ADB, testing</CardDescription>
            </CardHeader>
            <CardContent>
              <Button asChild size="sm" className="w-full">
                <Link href="/docs/api">Deep-link docs →</Link>
              </Button>
            </CardContent>
          </Card>
        </div>
      </section>

      {/* Included translations — minimal teaser -> full page */}
      <section className="space-y-4">
        <h2 className="text-2xl font-semibold tracking-tight">What&apos;s inside</h2>
        <p className="max-w-2xl text-muted-foreground">
          82 books, LXX + GNT primary. Details live on their own page — homepage just shows the shape.
        </p>
        <div className="grid gap-3 sm:grid-cols-3">
          <Card>
            <CardHeader className="pb-2"><CardTitle className="text-sm">LXXE + LXX + GNT</CardTitle></CardHeader>
            <CardContent className="text-xs text-muted-foreground">Primary Greek roots · Brenton + Apostolic + SBLGNT</CardContent>
          </Card>
          <Card>
            <CardHeader className="pb-2"><CardTitle className="text-sm">MT / NKJV</CardTitle></CardHeader>
            <CardContent className="text-xs text-muted-foreground">Comparison only · buried in Advanced</CardContent>
          </Card>
          <Card className="border-dashed">
            <CardHeader className="pb-2"><CardTitle className="text-sm">See full table →</CardTitle></CardHeader>
            <CardContent><Button asChild size="sm" variant="secondary" className="w-full"><Link href="/learn/canon">Canon & translations →</Link></Button></CardContent>
          </Card>
        </div>
      </section>

      {/* Shout-out — cybertech99 / FedoraBible */}
      <section className="relative overflow-hidden rounded-xl border bg-gradient-to-br from-card via-card to-muted/40 p-6 sm:p-7">
        <div className="pointer-events-none absolute -right-10 -top-10 h-40 w-40 rounded-full bg-primary/5 blur-2xl" />
        <div className="relative flex flex-col gap-5 lg:flex-row lg:items-center lg:justify-between">
          <div className="space-y-3 max-w-2xl">
            <div className="flex flex-wrap items-center gap-2">
              <Badge className="gap-1.5">
                <Heart className="size-3.5" /> Friends of Metanoia
              </Badge>
              <Badge variant="outline">Septuagint-first fellowship</Badge>
            </div>
            <h2 className="text-xl font-semibold tracking-tight sm:text-2xl">
              Shout-out to my buddy Roger — cybertech99 &amp; FedoraBible
            </h2>
            <p className="text-sm leading-relaxed text-muted-foreground">
              Roger&apos;s{" "}
              <a
                href="https://cybertech99.github.io/FedoraBible/"
                target="_blank"
                rel="noreferrer"
                className="font-medium text-foreground underline underline-offset-4 hover:text-primary"
              >
                FedoraBible
              </a>{" "}
              is a full-featured, offline PWA with 9 translations (KJV, TR, WLC, LXXE Brenton + LXXG Swete,
              Peshitta Syriac, Coptic Sahidic, Van Dyck Arabic), FTS5 search, linked parallel tabs, and a
              gorgeous parchment/manuscript/ink design system. His{" "}
              <a
                href="https://github.com/cybertech99/FedoraBible/blob/main/data/sources/SOURCE.md"
                target="_blank"
                rel="noreferrer"
                className="underline underline-offset-4 hover:text-foreground"
              >
                SOURCE.md
              </a>{" "}
              licensing table and <code className="rounded bg-muted px-1 py-0.5 text-xs">import-swete.js</code>{" "}
              pipeline taught us how to do interesting sources right — we&apos;re stealing the best parts
              (with attribution) to make Metanoia&apos;s LXX story even stronger.
            </p>
            <p className="text-xs text-muted-foreground">
              If you love Metanoia&apos;s Septuagint-first approach, you&apos;ll feel at home in FedoraBible&apos;s
              multi-translation depth. Try his live site, then come back and compare notes — both projects are
              better for the conversation.
            </p>
          </div>
          <div className="flex shrink-0 flex-col gap-2 sm:flex-row lg:flex-col">
            <Button asChild>
              <a
                href="https://cybertech99.github.io/FedoraBible/"
                target="_blank"
                rel="noreferrer"
              >
                <ExternalLink className="mr-2 size-4" /> Open FedoraBible
              </a>
            </Button>
            <Button variant="outline" asChild>
              <a
                href="https://github.com/cybertech99/FedoraBible"
                target="_blank"
                rel="noreferrer"
              >
                <Github className="mr-2 size-4" /> github/cybertech99/FedoraBible
              </a>
            </Button>
            <div className="text-center text-xs text-muted-foreground">
              MIT · offline · ~55 MB WASM SQLite
            </div>
          </div>
        </div>
      </section>

      {/* Learn → Build → Docs path — the intuitive flow */}
      <section className="space-y-4">
        <h2 className="text-2xl font-semibold tracking-tight">Learn → Build → Docs</h2>
        <p className="max-w-2xl text-muted-foreground text-sm">
          Educational material first, developer docs one tap away — never overloaded. Each page does one job.
        </p>
        <div className="grid gap-4 md:grid-cols-3">
          <Card className="border-primary/20">
            <CardHeader>
              <CardTitle className="text-base flex items-center gap-2"><span className="flex h-6 w-6 items-center justify-center rounded-full bg-primary text-primary-foreground text-xs">1</span> Learn</CardTitle>
              <CardDescription>Why LXX first, vs MT, canon</CardDescription>
            </CardHeader>
            <CardContent className="space-y-2">
              <Button asChild size="sm" className="w-full"><Link href="/learn">Start learning →</Link></Button>
              <p className="text-xs text-muted-foreground text-center">3 short pages · 2 min each</p>
            </CardContent>
          </Card>
          <Card className="border-primary/20">
            <CardHeader>
              <CardTitle className="text-base flex items-center gap-2"><span className="flex h-6 w-6 items-center justify-center rounded-full bg-primary text-primary-foreground text-xs">2</span> Build</CardTitle>
              <CardDescription>5-min onboarding → running app</CardDescription>
            </CardHeader>
            <CardContent className="space-y-2">
              <Button asChild size="sm" className="w-full"><Link href="/onboarding">Get started →</Link></Button>
              <p className="text-xs text-muted-foreground text-center">Zig nightly + one command</p>
            </CardContent>
          </Card>
          <Card className="border-primary/20">
            <CardHeader>
              <CardTitle className="text-base flex items-center gap-2"><span className="flex h-6 w-6 items-center justify-center rounded-full bg-primary text-primary-foreground text-xs">3</span> Docs</CardTitle>
              <CardDescription>Architecture, DB, deep links</CardDescription>
            </CardHeader>
            <CardContent className="space-y-2">
              <Button asChild size="sm" variant="outline" className="w-full"><Link href="/docs">Open docs →</Link></Button>
              <p className="text-xs text-muted-foreground text-center">One topic per page</p>
            </CardContent>
          </Card>
        </div>
      </section>

      {/* Developer onboarding teaser */}
      <section className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Boxes className="size-4" /> Architecture
            </CardTitle>
          </CardHeader>
          <CardContent className="text-sm text-muted-foreground">
            <p>
              <code>src/kit/</code> GTK widget kit (12 files, <code>kit/signal.zig</code> type-safe),
              <code>src/bible_db.zig</code> split content vs <code>library.db</code> personal data,
              <code>aikit/</code> native TTS/LLM sidecars, mobile Kotlin + iOS Swift.
            </p>
            <Button variant="link" size="sm" className="px-0" asChild>
              <Link href="/docs">Read architecture →</Link>
            </Button>
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Languages className="size-4" /> LXX depth
            </CardTitle>
          </CardHeader>
          <CardContent className="text-sm text-muted-foreground">
            <p>
              Analysis sidecar: transliteration search, <code>?simple</code> pipe for LLMs, allusion
              scan + beat-sequence (septcheck-style).
            </p>
            <Button variant="link" size="sm" className="px-0" asChild>
              <Link href="/docs#analysis">Study roots →</Link>
            </Button>
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Search className="size-4" /> Try a link
            </CardTitle>
          </CardHeader>
          <CardContent className="flex gap-2">
            <Button asChild size="sm">
              <a href="https://metanoia.bytecats.codes/bible/John/3/16">John 3:16</a>
            </Button>
            <Button asChild size="sm" variant="outline">
              <a href="https://metanoia.bytecats.codes/bible/Genesis/1">Genesis 1</a>
            </Button>
            <Button asChild size="sm" variant="outline">
              <a href="https://metanoia.bytecats.codes/bible/Romans/8/28">Rom 8:28</a>
            </Button>
          </CardContent>
        </Card>
      </section>

      {/* FAQ — single teaser card -> full page (avoids homepage overload) */}
      <section className="flex items-center justify-between gap-4 rounded-lg border p-4">
        <div>
          <h2 className="font-semibold">Questions?</h2>
          <p className="text-sm text-muted-foreground">Why LXX first, MT toggle, iOS, licensing — all on one clean page.</p>
        </div>
        <Button asChild variant="outline"><Link href="/docs#faq">FAQ →</Link></Button>
      </section>

      {/* Developer resources — preserved from root but with ui-kit. */}
      <section className="flex flex-wrap gap-3 border-t pt-6 text-sm">
        <Button variant="outline" asChild>
          <a href="https://github.com/4cecoder/metanoia">
            <Github className="mr-2 size-4" /> Source
          </a>
        </Button>
        <Button variant="outline" asChild>
          <a href="https://github.com/4cecoder/metanoia/tree/main/docs">
            <BookOpen className="mr-2 size-4" /> Docs
          </a>
        </Button>
        <Button variant="outline" asChild>
          <Link href="/history">
            <ScrollText className="mr-2 size-4" /> History
          </Link>
        </Button>
      </section>
    </div>
  );
}
