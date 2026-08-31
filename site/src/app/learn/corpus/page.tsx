import Link from "next/link";
import { Badge, Card, CardContent, CardHeader, CardTitle } from "@bytecats/ui-kit";
import { Breadcrumbs, PageNav } from "@/components/page-nav";

export default function CorpusPage() {
  return (
    <div className="space-y-8 max-w-3xl">
      <Breadcrumbs items={[{ label: "Home", href: "/" }, { label: "Learn", href: "/learn" }, { label: "Corpus principles" }]} />
      <header className="space-y-3">
        <div className="flex flex-wrap gap-2">
          <Badge variant="secondary">Learn · 2 min</Badge>
          <Badge variant="outline" className="gap-1">Preserved <code className="text-[10px]">index.html:551</code></Badge>
          <Badge>Tokyo Night → Astryx</Badge>
        </div>
        <h1 className="text-3xl font-semibold tracking-tight">Universal Biblical Corpus</h1>
        <p className="max-w-2xl text-muted-foreground prose">
          Preserved verbatim from the original Tokyo-Night developer portal — no information lost.
          81+ books, 4 traditions, 0.0 canonical hiding. This is the indexing philosophy the new
          site now distributes across <Link href="/learn/canon" className="underline">Canon</Link> and{" "}
          <Link href="/learn/english" className="underline">English</Link>.
        </p>
      </header>

      {/* Stats — combined into one glass card (was 3 cards, now 1 to stay ≤4) */}
      <Card className="backdrop-blur supports-[backdrop-filter]:bg-card/70">
        <CardContent className="grid grid-cols-3 gap-3 pt-6 text-center">
          <div><div className="text-3xl font-bold">81+</div><div className="text-xs text-muted-foreground">Indexed Canon Books</div></div>
          <div><div className="text-3xl font-bold">4</div><div className="text-xs text-muted-foreground">Textual Traditions</div></div>
          <div><div className="text-3xl font-bold">100%</div><div className="text-xs text-muted-foreground">Offline Native</div></div>
        </CardContent>
      </Card>

      {/* Principles — one card with 3 columns inside (was 3 cards) */}
      <Card>
        <CardHeader><CardTitle className="text-sm">Core indexing principles</CardTitle></CardHeader>
        <CardContent className="grid gap-4 md:grid-cols-3 text-sm text-muted-foreground">
          <div className="space-y-1">
            <div className="font-medium text-foreground text-xs">1. No Hiding</div>
            <p className="text-xs leading-relaxed">Search returns <em>ALL</em> matches across Protestant/Catholic/Orthodox/Ethiopian without silent filters. Filtering only via <code>show_deuterocanon</code> / <code>show_ethiopian_books</code> — <code>src/models/config.zig:104</code>.</p>
          </div>
          <div className="space-y-1">
            <div className="font-medium text-foreground text-xs">2. Tradition-First</div>
            <p className="text-xs leading-relaxed">Hebrew → Greek LXX → Ge&apos;ez → Greek NT. Now LXX+GNT primary (inverse Logos, <code>src/bible_db.zig:588-590</code>).</p>
          </div>
          <div className="space-y-1">
            <div className="font-medium text-foreground text-xs">3. Transparency</div>
            <p className="text-xs leading-relaxed">Surface books missing from Protestant canon (1 Enoch, Jubilees, Tobit, Wisdom, Maccabees). <code>src/bible_db.zig:334-422 BIBLE_BOOKS [82]</code>.</p>
          </div>
        </CardContent>
      </Card>

      {/* Traditions — one card with 3 columns inside (was 3 cards) */}
      <Card>
        <CardHeader><CardTitle className="text-sm">Textual traditions</CardTitle></CardHeader>
        <CardContent className="grid gap-4 md:grid-cols-3 text-xs text-muted-foreground">
          <div className="space-y-1">
            <div className="font-medium text-foreground">Masoretic</div>
            <p>39 books Hebrew Canon. <code>source=&apos;MT&apos;</code> 233k rows — buried in <code>interlinear.mt.db</code> (<code>bundle:false</code>).</p>
          </div>
          <div className="space-y-1">
            <div className="font-medium text-foreground">Septuagint (LXX)</div>
            <p>Greek OT + Deuterocanon. Primary: <code>LXXE</code> 27k + <code>LXX</code> 432k + planned <code>LXXG</code> Swete.</p>
          </div>
          <div className="space-y-1">
            <div className="font-medium text-foreground">Ethiopic</div>
            <p>Broadest canon — 1 Enoch, Jubilees, 1–3 Meqabyan in Ge&apos;ez. <code>show_ethiopian_books</code>.</p>
          </div>
        </CardContent>
      </Card>

      <div className="rounded-lg border bg-muted/30 p-3 text-xs text-muted-foreground">
        Theme: original used Tokyo Night (<code>#0f1117</code>, <code>#7aa2f7</code>, liquid-glass <code>backdrop-blur:20px</code>, radial gradients <code>index.html:11-40</code>). Now Astryx neutral default + <code>data-theme=&quot;tokyo&quot;</code> primary dark (<code>site/src/app/globals.css:12</code>).
      </div>

      <div className="rounded-lg border border-dashed bg-amber-50/50 p-3 text-xs text-muted-foreground dark:bg-amber-950/10">
        <span className="font-medium text-foreground">Preserved</span> — footer content from <code>index.html:551</code> (“Made with ❤️ by the Metanoia community”) is now in site footer; deep-link, testing, FAQ, and corpus sections preserved verbatim across <Link href="/docs/api" className="underline">Docs → Deep Links</Link> and this page. No info lost.
      </div>

      <PageNav prev={{ href: "/learn/english", label: "Back: English rendering" }} next={{ href: "/onboarding", label: "Next: Build — onboarding" }} />
    </div>
  );
}
