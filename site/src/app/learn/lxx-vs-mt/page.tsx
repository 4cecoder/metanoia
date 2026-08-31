import Link from "next/link";
import { Badge, Card, CardContent, CardHeader, CardTitle } from "@bytecats/ui-kit";
import { Breadcrumbs, PageNav } from "@/components/page-nav";

export default function LxxVsMt() {
  return (
    <div className="space-y-8 max-w-3xl">
      <Breadcrumbs
        items={[
          { label: "Home", href: "/" },
          { label: "Learn", href: "/learn" },
          { label: "LXX vs Masoretic" },
        ]}
      />
      <header className="space-y-3">
        <Badge variant="secondary">Learn · 2 min</Badge>
        <h1 className="text-3xl font-semibold tracking-tight">LXX vs Masoretic — not a rivalry</h1>
        <p className="max-w-2xl text-muted-foreground">
          Both preserve the same story through different channels. The question is which channel the
          New Testament authors were actually reading.
        </p>
      </header>

      <div className="grid gap-4 sm:grid-cols-2">
        <Card>
          <CardHeader><CardTitle className="text-sm">Septuagint (LXX)</CardTitle></CardHeader>
          <CardContent className="space-y-2 text-sm text-muted-foreground">
            <p>Greek translation for diaspora synagogues. NT authors quote it verbatim.</p>
            <p className="font-mono text-xs bg-muted p-2 rounded">παρθένος — Isa 7:14 → Matt 1:23</p>
            <p className="text-xs">Deut 32:8 בני אלהים / υἱῶν θεοῦ vs MT בני ישראל — DSS side with LXX.</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle className="text-sm">Masoretic (MT)</CardTitle></CardHeader>
          <CardContent className="space-y-2 text-sm text-muted-foreground">
            <p>Tiberian pointing (Ben Asher, Ben Naphtali) 7th–10th c. — brilliant reading tradition.</p>
            <p className="font-mono text-xs bg-muted p-2 rounded">WLC 2008 · Leningrad 1008 CE</p>
            <p className="text-xs">Consonants older; vowels + cantillation are medieval witnesses.</p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader><CardTitle className="text-base">How Metanoia orders them</CardTitle></CardHeader>
        <CardContent className="text-sm text-muted-foreground space-y-2">
          <p>
            LXXE + LXX interlinear + GNT are <em>primary</em> — you read Greek OT+NT as one language.
            MT/NKJV is <em>comparison</em> behind <code>src/models/config.zig:142</code> toggle in Settings → Advanced.
            Lexicon prefers <code>GNT &lt; LXX &lt; MT</code> <code>src/bible_db.zig:588-590</code>.
          </p>
          <p>
            Like Logos, we bury the secondary — just in the other direction. Roger's FedoraBible keeps
            them as neutral peers; septcheck drops MT entirely. We choose the church's reading order.
          </p>
        </CardContent>
      </Card>

      <div className="flex gap-2 text-xs">
        <Badge variant="outline">Primary: LXX+GNT</Badge>
        <Badge variant="secondary">Comparison: MT</Badge>
        <span className="text-muted-foreground">Both kept, ordered.</span>
      </div>

      <PageNav
        prev={{ href: "/history", label: "Back: Why LXX First" }}
        next={{ href: "/learn/canon", label: "Next: Canon & translations" }}
      />
    </div>
  );
}
