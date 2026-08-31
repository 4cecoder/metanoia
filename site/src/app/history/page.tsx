import { Badge } from "@bytecats/ui-kit";
import { Card, CardContent, CardHeader, CardTitle } from "@bytecats/ui-kit";
import { Breadcrumbs, PageNav } from "@/components/page-nav";

export default function HistoryPage() {
  return (
    <div className="space-y-10 max-w-3xl">
      <Breadcrumbs items={[{ label: "Home", href: "/" }, { label: "Learn", href: "/learn" }, { label: "Why LXX First" }]} />
      <header className="space-y-3">
        <Badge variant="secondary">History note — why this app is Septuagint-first</Badge>
        <h1 className="text-3xl font-semibold tracking-tight">Why LXX + GNT are the roots</h1>
        <p className="max-w-2xl text-muted-foreground">
          Not a preference — a timeline. Logos buries LXX because modern English Bibles are licensed
          off MT-based translations. Metanoia buries MT because the church studied in Greek before Hebrew
          had vowels.
        </p>
      </header>

      <section className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader><CardTitle>3rd–1st c. BCE — LXX</CardTitle></CardHeader>
          <CardContent className="text-sm text-muted-foreground space-y-2">
            <p>
              Torah in Alexandria (~280 BCE, Letter of Aristeas), rest by 1st c. BCE for Greek-speaking
              synagogues (Philo, Josephus). The diaspora&apos;s Bible.
            </p>
            <p className="text-xs">Source you share with septcheck & Fedora LXXG: `nathans/lxx-swete` (Swete 1887–1930 word-per-line).</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle>1st c. CE — NT quotes LXX</CardTitle></CardHeader>
          <CardContent className="text-sm text-muted-foreground space-y-2">
            <p>
              ~70–80% of ~300 OT citations follow LXX wording verbatim. Isa 7:14 עַלְמָה → παρθένος →
              Matt 1:23; Amos 9:11-12/Acts 15:16-17; Ps 40:6/Heb 10:5.
            </p>
            <p className="text-xs">The disciples heard Greek LXX in synagogues; consonantal Hebrew had no niqqud yet.</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle>7th–10th c. CE — MT pointed</CardTitle></CardHeader>
          <CardContent className="text-sm text-muted-foreground space-y-2">
            <p>
              Consonantal text stabilized 1st–2nd c. CE; Tiberian vocalization (Ben Asher/Ben Naphtali) adds
              niqqud + cantillation 7th–10th c. Leningrad/WLC = 1008 CE.
            </p>
            <p className="text-xs">DSS (1947) often side with LXX Vorlage over MT: Deut 32:8 בני אלהים/υἱῶν θεοῦ vs בני ישראל, Jer length.</p>
          </CardContent>
        </Card>
      </section>

      <section className="space-y-3">
        <h2 className="text-xl font-semibold">So Logos got it backwards for study</h2>
        <p className="max-w-3xl text-sm text-muted-foreground">
          Tyndale→KJV cemented MT English; ESV/NASB/NKJV licensing keeps it default in premium tools. That&apos;s a
          publishing fact, not a textual argument. Metanoia keeps MT as a comparison pane (
          <code>src/models/config.zig:142</code> defaults <code>ot_source=&quot;lxx&quot;</code>, checkbox at{" "}
          <code>src/main.zig:1191</code> Advanced) — buried Logos-style, but in the other direction.
        </p>
        <div className="flex flex-wrap gap-2 text-sm">
          <Badge>Primary: LXXE + LXX + GNT</Badge>
          <Badge variant="outline">Comparison: MT / NKJV (toggle in Settings)</Badge>
          <Badge variant="secondary">Next: LXXG Swete second witness</Badge>
        </div>
      </section>

      <section className="rounded-lg border p-4 text-sm text-muted-foreground">
        <p className="font-medium text-foreground">Both matter — ordered correctly.</p>
        <p>
          Greek for NT background and early-church reading; Hebrew for later Masoretic precision and
          consonantal variants (see DSS). The app pairs LXXE English + LXX interlinear so {` `}
          <code>load_chapter_into_study</code> (<code>src/main.zig:403-417</code>) and lexicon (<code>src/bible_db.zig:584-598</code>{" "}
          <code>ORDER BY source → GNT&lt;LXX&lt;MT</code>) stay in one language for ordered study. Lexicon
          transliteration fix (<code>lxx_translit.py:72</code>) closes the <code>art</code>⊂<code>amart-</code> collision.
        </p>
      </section>

      <PageNav
        prev={{ href: "/learn", label: "Back: Learn hub" }}
        next={{ href: "/learn/lxx-vs-mt", label: "Next: LXX vs MT" }}
      />
    </div>
  );
}
