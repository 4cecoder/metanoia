import Link from "next/link";
import { Badge, Button, Card, CardContent, CardHeader, CardTitle } from "@bytecats/ui-kit";
import { Breadcrumbs, PageNav } from "@/components/page-nav";

export default function CanonPage() {
  return (
    <div className="space-y-8">
      <Breadcrumbs
        items={[
          { label: "Home", href: "/" },
          { label: "Learn", href: "/learn" },
          { label: "Canon & translations" },
        ]}
      />
      <header className="space-y-3">
        <Badge variant="secondary">Learn · 2 min</Badge>
        <h1 className="text-3xl font-semibold tracking-tight">Canon & translations</h1>
        <p className="max-w-2xl text-muted-foreground">
          82 books total — not 66. Protestant + Deuterocanon + Ethiopian. Primary Greek table + interesting
          sources we&apos;re stealing from Fedora & septcheck (with credit).
        </p>
      </header>

      <div className="overflow-auto rounded-lg border">
        <table className="w-full text-sm">
          <thead className="bg-muted/50 text-left">
            <tr>
              <th className="px-3 py-2">Code</th>
              <th className="px-3 py-2">Text</th>
              <th className="px-3 py-2">Role</th>
              <th className="px-3 py-2">Where</th>
            </tr>
          </thead>
          <tbody>
            <tr className="border-t"><td className="px-3 py-2 font-mono">LXXE</td><td className="px-3 py-2">Brenton 1851</td><td className="px-3 py-2"><Badge>Primary</Badge></td><td className="px-3 py-2 text-xs">27k <code>version='LXXE'</code></td></tr>
            <tr className="border-t"><td className="px-3 py-2 font-mono">LXX</td><td className="px-3 py-2">Apostolic interlinear</td><td className="px-3 py-2"><Badge>Primary</Badge></td><td className="px-3 py-2 text-xs">432k <code>source='LXX'</code></td></tr>
            <tr className="border-t"><td className="px-3 py-2 font-mono">GNT</td><td className="px-3 py-2">SBLGNT</td><td className="px-3 py-2"><Badge>Primary</Badge></td><td className="px-3 py-2 text-xs">138k <code>source='GNT'</code></td></tr>
            <tr className="border-t bg-muted/20"><td className="px-3 py-2 font-mono">LXXG</td><td className="px-3 py-2">Swete Greek</td><td className="px-3 py-2"><Badge variant="secondary">Next up</Badge></td><td className="px-3 py-2 text-xs">22k nathans/lxx-swete CC BY-SA</td></tr>
            <tr className="border-t"><td className="px-3 py-2 font-mono">MT / NKJV</td><td className="px-3 py-2">WLC + NKJV</td><td className="px-3 py-2"><Badge variant="outline">Comparison</Badge></td><td className="px-3 py-2 text-xs">Behind Advanced checkbox</td></tr>
          </tbody>
        </table>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <Card><CardHeader><CardTitle className="text-sm">Deuterocanon</CardTitle></CardHeader><CardContent className="text-xs text-muted-foreground">Tobit, Judith, Wisdom, Sirach, Baruch, 1–2 Macc — toggle <code>show_deuterocanon</code> <code>src/models/config.zig:104</code></CardContent></Card>
        <Card><CardHeader><CardTitle className="text-sm">Ethiopian</CardTitle></CardHeader><CardContent className="text-xs text-muted-foreground">Enoch, Jubilees, Meqabyan, Tegsas — <code>show_ethiopian_books</code> <code>config.zig:108</code></CardContent></Card>
        <Card>
          <CardHeader><CardTitle className="text-sm">Friends to borrow</CardTitle></CardHeader>
          <CardContent className="text-xs text-muted-foreground space-y-1">
            <p><a href="https://cybertech99.github.io/FedoraBible/" target="_blank" rel="noreferrer" className="underline">FedoraBible</a>: Peshitta Syriac, Coptic Sahidic, Van Dyck Arabic</p>
            <p><a href="https://github.com/4cecoder/septcheck" target="_blank" rel="noreferrer" className="underline">septcheck</a>: SBLGNT + allusion scan sidecar</p>
          </CardContent>
        </Card>
      </div>

      <Card className="border-dashed">
        <CardHeader><CardTitle className="text-sm">82-book canon</CardTitle></CardHeader>
        <CardContent className="text-sm text-muted-foreground">
          <code>src/bible_db.zig:334-422</code> <code>BIBLE_BOOKS [82]</code> with <code>Canon.Protestant/Deuterocanon/Ethiopian</code>. Book picker filters by <code>show_*</code> flags.
        </CardContent>
      </Card>

      <PageNav
        prev={{ href: "/learn/lxx-vs-mt", label: "Back: LXX vs MT" }}
        next={{ href: "/learn/english", label: "Next: English rendering" }}
      />
    </div>
  );
}
