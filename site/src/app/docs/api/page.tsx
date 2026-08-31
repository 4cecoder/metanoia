import Link from "next/link";
import { Badge, Button, Card, CardContent, CardHeader, CardTitle } from "@bytecats/ui-kit";
import { Breadcrumbs, PageNav } from "@/components/page-nav";

export default function ApiPage() {
  return (
    <div className="space-y-10 max-w-3xl">
      <Breadcrumbs items={[{ label: "Home", href: "/" }, { label: "Docs", href: "/docs" }, { label: "Deep Links" }]} />
      <header className="space-y-3">
        <Badge>Docs · Deep Links — preserved from Tokyo Night portal</Badge>
        <h1 className="text-3xl font-semibold tracking-tight">Deep links</h1>
        <p className="text-muted-foreground">
          Two shapes, same resolver. No information lost — the full portal from <code>index.html:324-515</code> (Tokyo Night, liquid-glass) now lives here, one page per job instead of one overloaded scroll.
        </p>
      </header>

      {/* How It Works — verbatim from index.html:324 */}
      <section className="space-y-4">
        <h2 className="text-xl font-semibold">How It Works</h2>
        <p className="text-sm text-muted-foreground">Two simple link formats, automatic verse resolution.</p>
        <div className="grid gap-4 md:grid-cols-3">
          <Card>
            <CardHeader><CardTitle className="text-sm">Web-Friendly Links</CardTitle></CardHeader>
            <CardContent className="space-y-2 text-sm text-muted-foreground">
              <p>Standard HTTPS URLs that work in browsers and auto-open Metanoia with App Link verification.</p>
              <pre className="rounded bg-muted p-2 text-xs">https://metanoia.bytecats.codes/bible/John/3/16</pre>
            </CardContent>
          </Card>
          <Card>
            <CardHeader><CardTitle className="text-sm">Direct App Links</CardTitle></CardHeader>
            <CardContent className="space-y-2 text-sm text-muted-foreground">
              <p>Use the <code>metanoia://</code> scheme for immediate deep links without verification.</p>
              <pre className="rounded bg-muted p-2 text-xs">metanoia://bible/John/3/16</pre>
            </CardContent>
          </Card>
          <Card>
            <CardHeader><CardTitle className="text-sm">Smart Resolution</CardTitle></CardHeader>
            <CardContent className="space-y-2 text-sm text-muted-foreground">
              <p>Full names, abbreviations (<code>jn</code>, <code>1sam</code>), and automatic chapter/verse validation — land on <code>src/main.zig:load_chapter_into_study</code> with <code>ORDER BY (version != ?)</code> fallback.</p>
              <pre className="rounded bg-muted p-2 text-xs">https://metanoia.bytecats.codes/bible/jn/3/16</pre>
            </CardContent>
          </Card>
        </div>
      </section>

      {/* Integration Guide — verbatim index.html:361 */}
      <section className="space-y-4">
        <h2 className="text-xl font-semibold">Integration Guide</h2>
        <Card>
          <CardHeader><CardTitle className="text-sm">Kotlin / Android</CardTitle></CardHeader>
          <CardContent><pre className="rounded bg-muted p-3 text-xs overflow-auto">{`val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://metanoia.bytecats.codes/bible/John/3/16"))
startActivity(intent)`}</pre></CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle className="text-sm">Web / HTML</CardTitle></CardHeader>
          <CardContent><pre className="rounded bg-muted p-3 text-xs overflow-auto">{`<a href="https://metanoia.bytecats.codes/bible/Romans/8/28">Read Romans 8:28</a>`}</pre></CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle className="text-sm">JavaScript / Web</CardTitle></CardHeader>
          <CardContent><pre className="rounded bg-muted p-3 text-xs overflow-auto">{`window.open('https://metanoia.bytecats.codes/bible/Genesis/1/1', '_self');`}</pre></CardContent>
        </Card>
      </section>

      {/* Link Examples — verbatim index.html:393 */}
      <section className="space-y-4">
        <h2 className="text-xl font-semibold">Link Examples</h2>
        <div className="rounded-lg border bg-green-50 p-3 text-sm dark:bg-green-950/20">✅ Tested & Working — verified with latest Metanoia app.</div>
        <div className="overflow-auto rounded-lg border">
          <table className="w-full text-sm">
            <thead className="bg-muted/50 text-left"><tr><th className="px-3 py-2">Link</th><th className="px-3 py-2">Opens</th><th className="px-3 py-2">Type</th></tr></thead>
            <tbody>
              <tr className="border-t"><td className="px-3 py-2 font-mono text-xs">metanoia://bible/John/3/16</td><td className="px-3 py-2">John 3:16</td><td className="px-3 py-2"><Badge variant="outline">Custom</Badge></td></tr>
              <tr className="border-t"><td className="px-3 py-2 font-mono text-xs">https://metanoia.bytecats.codes/bible/Genesis/1</td><td className="px-3 py-2">Genesis 1 (chapter)</td><td className="px-3 py-2"><Badge>HTTPS</Badge></td></tr>
              <tr className="border-t"><td className="px-3 py-2 font-mono text-xs">https://metanoia.bytecats.codes/bible/1Samuel/17/45</td><td className="px-3 py-2">1 Samuel 17:45</td><td className="px-3 py-2"><Badge>HTTPS</Badge></td></tr>
              <tr className="border-t"><td className="px-3 py-2 font-mono text-xs">metanoia://bible/SongofSolomon/2/1</td><td className="px-3 py-2">Song of Solomon 2:1</td><td className="px-3 py-2"><Badge variant="outline">Custom</Badge></td></tr>
              <tr className="border-t"><td className="px-3 py-2 font-mono text-xs">https://metanoia.bytecats.codes/bible/jn/3/16</td><td className="px-3 py-2">John 3:16 (abbrev)</td><td className="px-3 py-2"><Badge>HTTPS</Badge></td></tr>
              <tr className="border-t"><td className="px-3 py-2 font-mono text-xs">https://metanoia.bytecats.codes/bible/Romans/8/28</td><td className="px-3 py-2">Romans 8:28</td><td className="px-3 py-2"><Badge>HTTPS</Badge></td></tr>
            </tbody>
          </table>
        </div>
      </section>

      {/* Testing — verbatim index.html:444 */}
      <section className="space-y-4">
        <h2 className="text-xl font-semibold">Testing Links</h2>
        <Card className="border-amber-200 bg-amber-50 dark:bg-amber-950/20">
          <CardHeader><CardTitle className="text-sm">⚠️ ADB Testing</CardTitle></CardHeader>
          <CardContent>
            <pre className="rounded bg-muted p-3 text-xs overflow-auto">{`adb shell am start -W -a android.intent.action.VIEW \\
  -d "metanoia://bible/John/3/16" com.bytecats.metanoia`}</pre>
          </CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle className="text-sm">Live Testing</CardTitle></CardHeader>
          <CardContent className="flex flex-wrap gap-2">
            <Button asChild size="sm"><a href="https://metanoia.bytecats.codes/bible/John/3/16">Test John 3:16</a></Button>
            <Button asChild size="sm" variant="outline"><a href="https://metanoia.bytecats.codes/bible/Genesis/1">Test Genesis 1</a></Button>
            <Button asChild size="sm" variant="outline"><a href="https://metanoia.bytecats.codes/bible/Romans/8/28">Test Romans 8:28</a></Button>
          </CardContent>
        </Card>
      </section>

      {/* FAQ — verbatim index.html:468 */}
      <section className="space-y-4">
        <h2 className="text-xl font-semibold">FAQ</h2>
        <div className="grid gap-4 md:grid-cols-2">
          <Card><CardHeader><CardTitle className="text-sm">What if Metanoia isn&apos;t installed?</CardTitle></CardHeader><CardContent className="text-sm text-muted-foreground">HTTPS link opens in browser; user can install from there.</CardContent></Card>
          <Card><CardHeader><CardTitle className="text-sm">Does this work on iOS?</CardTitle></CardHeader><CardContent className="text-sm text-muted-foreground">Android-only today; iOS Universal Links planned, <code>metanoia://</code> works where allowed.</CardContent></Card>
          <Card><CardHeader><CardTitle className="text-sm">Can I link to specific translations?</CardTitle></CardHeader><CardContent className="text-sm text-muted-foreground">Not yet — opens user&apos;s preference. Translation-keyed links planned (see <code>docs/DEEP_LINKING_GUIDE.md:294</code>).</CardContent></Card>
          <Card><CardHeader><CardTitle className="text-sm">What about deuterocanonical books?</CardTitle></CardHeader><CardContent className="text-sm text-muted-foreground">66-book baseline today; use full names (<code>Tobit</code>, etc.) for others until abbreviations land. Full 82-book picker is in <Link href="/learn/canon" className="underline">Canon</Link>.</CardContent></Card>
        </div>
      </section>

      <section className="flex flex-wrap gap-2 text-xs">
        <Badge variant="outline">Verified via .well-known/assetlinks.json</Badge>
        <Badge variant="secondary">Tokyo Night → Astryx: liquid-glass preserved</Badge>
        <Link href="/learn/corpus" className="underline">Corpus principles →</Link>
      </section>

      <PageNav prev={{ href: "/docs/voice", label: "Back: TTS + Whisper" }} next={{ href: "/", label: "Back to home" }} />
    </div>
  );
}
