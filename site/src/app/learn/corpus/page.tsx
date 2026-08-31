import Link from "next/link";
import { Badge, Card, CardContent, CardHeader, CardTitle } from "@bytecats/ui-kit";
import { Breadcrumbs, PageNav } from "@/components/page-nav";

export default function CorpusPage() {
  return (
    <div className="space-y-8">
      <Breadcrumbs items={[{ label: "Home", href: "/" }, { label: "Learn", href: "/learn" }, { label: "Corpus principles" }]} />
      <header className="space-y-3">
        <Badge>Learn · Preserved from original theme</Badge>
        <h1 className="text-3xl font-semibold tracking-tight">Universal Biblical Corpus</h1>
        <p className="max-w-2xl text-muted-foreground">
          Preserved verbatim from the original Tokyo-Night developer portal — no information lost.
          81+ books, 4 traditions, 0.0 canonical hiding. This is the indexing philosophy the new
          site now distributes across <Link href="/learn/canon" className="underline">Canon</Link> and{" "}
          <Link href="/learn/english" className="underline">English</Link>.
        </p>
      </header>

      <div className="grid gap-3 sm:grid-cols-3 text-center">
        <Card><CardContent className="pt-6"><div className="text-3xl font-bold">81+</div><div className="text-xs text-muted-foreground">Indexed Canon Books</div></CardContent></Card>
        <Card><CardContent className="pt-6"><div className="text-3xl font-bold">4</div><div className="text-xs text-muted-foreground">Textual Traditions (Hebrew, Greek, Ge&apos;ez, NT)</div></CardContent></Card>
        <Card><CardContent className="pt-6"><div className="text-3xl font-bold">100%</div><div className="text-xs text-muted-foreground">Offline Native Execution</div></CardContent></Card>
      </div>

      <section className="space-y-4">
        <h2 className="text-xl font-semibold">Core indexing principles</h2>
        <div className="grid gap-4 md:grid-cols-3">
          <Card>
            <CardHeader><CardTitle className="text-sm">1. No Hiding</CardTitle></CardHeader>
            <CardContent className="text-sm text-muted-foreground">
              Search returns <em>ALL</em> matching books across Protestant, Catholic, Orthodox, and Ethiopian canons
              without silent filters. Filtering happens only in the book picker via <code>show_deuterocanon</code> / <code>show_ethiopian_books</code> — see <code>src/models/config.zig:104</code>.
            </CardContent>
          </Card>
          <Card>
            <CardHeader><CardTitle className="text-sm">2. Tradition-First</CardTitle></CardHeader>
            <CardContent className="text-sm text-muted-foreground">
              Organized by original textual tradition: Hebrew/Masoretic → Greek/Septuagint → Ge&apos;ez/Ethiopic → Greek NT.
              New site keeps this but re-orders primacy to LXX+GNT first (inverse Logos, <code>src/bible_db.zig:588-590</code>).
            </CardContent>
          </Card>
          <Card>
            <CardHeader><CardTitle className="text-sm">3. Historical Transparency</CardTitle></CardHeader>
            <CardContent className="text-sm text-muted-foreground">
              Explicitly surface books missing from the Protestant canon (1 Enoch, Jubilees, Tobit, Wisdom, Maccabees, Meqabyan). See <code>src/bible_db.zig:334-422 BIBLE_BOOKS [82]</code>.
            </CardContent>
          </Card>
        </div>
      </section>

      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader><CardTitle className="text-sm">Masoretic Tradition</CardTitle></CardHeader>
          <CardContent className="text-sm text-muted-foreground">
            39 Books of the Hebrew Canon (Torah, Nevi&apos;im, Ketuvim). Full Hebrew interlinear <code>source=&apos;MT&apos;</code> 233k rows — now <em>buried</em> in <code>interlinear.mt.db</code> (<code>bundle:false</code>), not deleted.
          </CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle className="text-sm">Septuagint (LXX)</CardTitle></CardHeader>
          <CardContent className="text-sm text-muted-foreground">
            Greek Old Testament with Deuterocanon (Wisdom, Sirach, Tobit, Judith, Baruch, Maccabees). Now primary: <code>LXXE</code> 27k + <code>LXX</code> 432k, plus planned <code>LXXG</code> Swete via Roger&apos;s pipeline.
          </CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle className="text-sm">Ethiopic Canon</CardTitle></CardHeader>
          <CardContent className="text-sm text-muted-foreground">
            Broadest canon — 1 Enoch, Jubilees, 1–3 Meqabyan in Ge&apos;ez. <code>canon=Ethiopian</code> (≈15 books) — opt-in via <code>show_ethiopian_books</code>.
          </CardContent>
        </Card>
      </div>

      <div className="rounded-lg border bg-muted/30 p-3 text-xs text-muted-foreground">
        Theme note — original page used Tokyo Night (<code>#0f1117</code>, <code>#7aa2f7</code>, liquid-glass <code>backdrop-blur:20px</code>, radial gradients). New site uses Astryx neutral/stone but preserves the same accent logic and adds <code>data-ui-theme=&quot;tokyo&quot;</code> as an alt (see <code>site/src/app/globals.css</code>).
      </div>

      <PageNav prev={{ href: "/learn", label: "Back: Learn hub" }} next={{ href: "/learn/canon", label: "Next: Canon table" }} />
    </div>
  );
}
