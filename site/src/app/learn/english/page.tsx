import Link from "next/link";
import { Badge, Card, CardContent, CardDescription, CardHeader, CardTitle } from "@bytecats/ui-kit";
import { Breadcrumbs, PageNav } from "@/components/page-nav";

export default function EnglishPage() {
  return (
    <div className="space-y-8 max-w-3xl">
      <Breadcrumbs
        items={[
          { label: "Home", href: "/" },
          { label: "Learn", href: "/learn" },
          { label: "English renderings" },
        ]}
      />
      <header className="space-y-3">
        <Badge>Learn · English</Badge>
        <h1 className="text-3xl font-semibold tracking-tight">English that matches the Greek</h1>
        <p className="max-w-2xl text-muted-foreground">
          You liked NKJV — so do we for Masoretic precision. But NKJV&apos;s Old Testament is
          translated from the Masoretic Text (MT), not the Septuagint. If roots are LXX+GNT,
          the English you read in the OT should be from LXX too. Roger&apos;s FedoraBible taught us how to
          do that cleanly.
        </p>
      </header>

      <Card className="border-amber-200 bg-amber-50 dark:bg-amber-950/20 dark:border-amber-900">
        <CardHeader>
          <CardTitle className="text-sm flex items-center gap-2">
            ⚠️ The NKJV trap <Badge variant="outline">copyrighted</Badge>
          </CardTitle>
          <CardDescription>
            NKJV is Thomas Nelson, 1982 — not public domain. Fedora&apos;s{" "}
            <code>data/sources/SOURCE.md:1</code> explicitly excludes NIV/ESV/NKJV/NASB:
            &quot;hosting their full text isn&apos;t something this project does.&quot; Metanoia
            ships <code>verses version=&apos;NKJV&apos;</code> 31,102 as{" "}
            <code>src/bible_db.zig:476 DEFAULT_VERSION</code> — that&apos;s the trap (beautiful, but
            MT + licensed).
          </CardDescription>
        </CardHeader>
        <CardContent className="text-xs text-muted-foreground">
          Fedora keeps OT English as <code>lxx-en/</code> Brenton USFM (PD) +{" "}
          <code>lxx-gr/</code> Swete Greek (PD text, CC BY-SA transcription). KJV/WLC/Peshitta are
          PD/free. We&apos;re copying that split: LXX-English stays PD, MT-English moves to PD too.
        </CardContent>
      </Card>

      <div className="grid gap-4 sm:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle className="text-sm flex items-center gap-2">
              Primary — LXX English (from Greek) <Badge>Primary</Badge>
            </CardTitle>
            <CardDescription>
              What you read when <code>ot_source=lxx</code> (default) ·{" "}
              <code>manifest.primacy=&apos;primary&apos;</code>
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <div className="rounded bg-muted p-2 text-xs space-y-1">
              <div className="flex items-center gap-2">
                <span className="font-semibold">Brenton 1851</span>{" "}
                <Badge variant="secondary" className="text-[10px]">
                  LXXE
                </Badge>{" "}
                <Badge className="text-[10px]">primary</Badge>
              </div>
              <div className="text-muted-foreground">
                USFM via eBible.org <span className="font-mono">(eng-Brenton_usfm.zip)</span> · Public domain
                · 27,058 verses · 39 books, Daniel = Theodotion
              </div>
              <div className="text-muted-foreground">
                Import: <code>tools/bible/import_brenton_septuagint.py</code> →{" "}
                <code>data/db/verses.lxxe.db</code> (<code>verses.version=&apos;LXXE&apos;</code>, ~5.2 MB)
              </div>
              <div className="flex items-center gap-2 pt-1">
                <span className="font-semibold">LXXM</span>{" "}
                <Badge variant="secondary" className="text-[10px]">
                  LXXM
                </Badge>{" "}
                <Badge variant="outline" className="text-[10px]">
                  optional
                </Badge>{" "}
                <span className="text-muted-foreground">modernized Brenton</span>
              </div>
              <div className="text-muted-foreground">
                Deterministic post-process <code>thou→you, hath→has, doth→does, shalt→shall</code> — no
                re-scrape: <code>tools/bible/modernize_brenton.py</code> →{" "}
                <code>verses.lxxm.db</code> (<code>version=&apos;LXXM&apos;</code>, still PD)
              </div>
            </div>
            <p className="text-xs text-muted-foreground">
              Archaic <em>thee/thou</em> is faithful to LXX Vorlage — <code>LXXM</code> keeps the same
              scholarship without the Elizabethan pronouns. License: PD (Brenton 1851) — see{" "}
              <code>docs/DB_SHARDING.md</code> + <code>docs/FEDORA_AUDIT.md §9</code>.
            </p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle className="text-sm flex items-center gap-2">
              Comparison — MT English (from Hebrew){" "}
              <Badge variant="outline">comparison · buried</Badge>
            </CardTitle>
            <CardDescription>
              PD only · opt-in via <code>manifest.bundle=false</code> —{" "}
              <code>primacy: comparison/optional/buried</code>
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <div className="rounded bg-muted p-2 text-xs space-y-2">
              <div className="flex items-start justify-between gap-2">
                <div>
                  <span className="font-semibold">WEB</span> — World English Bible — PD (ebible.org,
                  modern ASV 1901 base) · <span className="font-mono">31k vv</span>
                </div>
                <Badge variant="outline" className="text-[10px] shrink-0">
                  comparison
                </Badge>
              </div>
              <div className="text-muted-foreground">
                Replaces NKJV as the PD MT-English. Import: <code>tools/bible/import_web.py</code> (
                <code>eng-web_usfm.zip</code> USFM, same shape as Brenton + Fedora&apos;s{" "}
                <code>import-translation.js</code> JSON fallback) →{" "}
                <code>verses.web.db</code> (<code>version=&apos;WEB&apos;</code>)
              </div>
              <div className="flex items-start justify-between gap-2 pt-1 border-t border-border/50">
                <div>
                  <span className="font-semibold">KJV</span> (1769) — PD in US, Crown in UK — 31,102 vv
                  via <code>aruljohn/Bible-kjv</code>
                </div>
                <Badge variant="outline" className="text-[10px] shrink-0">
                  optional
                </Badge>
              </div>
              <div className="flex items-start justify-between gap-2">
                <div>
                  <span className="font-semibold">YLT</span> (1862) — PD, hyper-literal fringe
                </div>
                <Badge variant="outline" className="text-[10px] shrink-0">
                  optional
                </Badge>
              </div>
              <div className="flex items-start justify-between gap-2 border-t border-amber-200 pt-1">
                <div className="text-amber-900 dark:text-amber-200">
                  <span className="font-semibold">NKJV</span> — Thomas Nelson, 1982 — 31,102 vv
                </div>
                <Badge variant="outline" className="text-[10px] border-amber-300 shrink-0">
                  buried → removed
                </Badge>
              </div>
            </div>
            <p className="text-xs text-muted-foreground">
              PD English ships via Fedora&apos;s <code>scripts/import-translation.js</code> per-book JSON
              shape (one JSON per book) — or directly from USFM — →{" "}
              <code>verses.web.db</code> / <code>verses.kjv.db</code> shards —{" "}
              <code>primacy: comparison/optional</code>, <code>bundle:false</code>. Same predicate as{" "}
              <code>tools/bible/split_db.py:46</code> <code>verses.version=&apos;WEB&apos;</code>. NKJV shard
              becomes <code>bundle:false</code> then removed.
            </p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-sm">How Roger ships it — and our plan</CardTitle>
          <CardDescription>Per-version file + license table + parallel tabs — then manifest</CardDescription>
        </CardHeader>
        <CardContent className="text-sm text-muted-foreground space-y-3">
          <ul className="list-disc pl-5 space-y-1 text-xs">
            <li>
              <strong>Per-version file before merge:</strong> Fedora keeps{" "}
              <code>data/sources/kjv/*.json</code> + <code>lxx-en/*.usfm</code> +{" "}
              <code>lxx-gr/*.txt</code> — then one-file build only at the end. We reverse it:
              <em> stay split at runtime</em> — <code>data/db/verses.lxxe.db</code> vs{" "}
              <code>verses.web.db</code> (sharded, ATTACH).
            </li>
            <li>
              <strong>License table per source:</strong> Fedora&apos;s <code>SOURCE.md</code> lists
              license + verse count + import shape. Our <code>manifest.json</code> does the same
              with <code>primacy</code> + <code>bundle</code> flags — 7 shards today (see{" "}
              <Link href="/docs/database" className="underline">
                Docs → Database
              </Link>
              ).
            </li>
            <li>
              <strong>Parallel tabs, not replacement:</strong> Fedora&apos;s linked tabs (
              <em>each keeping its own translation while turning pages together</em>) let you compare
              LXXE vs WEB without picking a winner — better than swapping <code>NKJV</code> for{" "}
              <code>WEB</code>.
            </li>
          </ul>
          <div className="rounded bg-muted p-2 text-xs space-y-1">
            <div>
              1. Keep <code>LXXE</code> as default OT English (<code>src/main.zig:417</code> when{" "}
              <code>ot_source=lxx</code>)
            </div>
            <div>
              2. Add <code>WEB</code> shard via <code>scripts/import-translation.js</code> shape — PD,
              modern NKJV-adjacent readability
            </div>
            <div>
              3. Mark <code>NKJV</code> shard <code>bundle:false</code> then remove after WEB ships —
              fixes the licensing trap
            </div>
            <div>
              4. Optional <code>LXXM</code> modernized Brenton — deterministic thee/thou pass, stays
              PD
            </div>
          </div>
          <p className="text-xs">
            Shout-out:{" "}
            <a
              href="https://cybertech99.github.io/FedoraBible/"
              target="_blank"
              rel="noreferrer"
              className="underline"
            >
              FedoraBible
            </a>{" "}
            live +{" "}
            <a
              href="https://github.com/cybertech99/FedoraBible"
              target="_blank"
              rel="noreferrer"
              className="underline"
            >
              github/cybertech99/FedoraBible
            </a>{" "}
            — licenses in <code>data/sources/SOURCE.md</code> + §9 of <code>docs/FEDORA_AUDIT.md</code>.
          </p>
        </CardContent>
      </Card>

      <PageNav
        prev={{ href: "/learn/canon", label: "Back: Canon" }}
        next={{ href: "/learn/corpus", label: "Next: Corpus principles" }}
      />
    </div>
  );
}
