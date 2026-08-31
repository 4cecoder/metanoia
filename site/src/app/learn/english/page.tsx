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
        <p className="text-muted-foreground">
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
            <CardTitle className="text-sm">Primary — LXX English (from Greek)</CardTitle>
            <CardDescription>What you read when <code>ot_source=lxx</code> (default)</CardDescription>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <div className="rounded bg-muted p-2 text-xs">
              <span className="font-semibold">Brenton 1851</span> — USFM via eBible.org
              <span className="text-muted-foreground"> (eng-Brenton_usfm.zip)</span>
              <br />
              <span className="text-muted-foreground">
                Public domain · 27,058 verses · 39 books, Daniel = Theodotion. Import:{" "}
                <code>tools/bible/import_brenton_septuagint.py</code> →{" "}
                <code>verses.lxxe.db</code> (<code>verses.version=&apos;LXXE&apos;</code>, primary, ~5.2 MB)
              </span>
            </div>
            <p className="text-xs text-muted-foreground">
              Archaic thee/thou, but faithful to LXX Vorlage. License: PD (Brenton 1851) — see{" "}
              <code>docs/DB_SHARDING.md</code> + <code>docs/FEDORA_AUDIT.md §9</code>. Next: a
              deterministic modernizer <code>thou→you, hath→has</code> as{" "}
              <code>verses.lxxm.db</code> — still PD.
            </p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle className="text-sm">Comparison — MT English (from Hebrew)</CardTitle>
            <CardDescription>Buried, PD, opt-in only</CardDescription>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <div className="rounded bg-muted p-2 text-xs space-y-1">
              <div>
                <span className="font-semibold">WEB</span> — World English Bible — PD (ebible.org,
                modern ASV 1901 base)
              </div>
              <div>
                <span className="font-semibold">KJV</span> (1769) — PD in US, Crown in UK — 31,102
                verses via <code>aruljohn/Bible-kjv</code>
              </div>
              <div>
                <span className="font-semibold">YLT</span> (Young&apos;s Literal, 1862) — PD,
                hyper-literal fringe
              </div>
            </div>
            <p className="text-xs text-muted-foreground">
              All three PD English ship via Fedora&apos;s <code>scripts/import-translation.js</code>{" "}
              shape (one JSON per book) → <code>verses.web.db</code> /{" "}
              <code>verses.kjv.db</code> shards — <code>primacy: comparison/optional</code>,{" "}
              <code>bundle:false</code> or on-demand. Same predicate as{" "}
              <code>tools/bible/split_db.py:46</code> <code>verses.version=&apos;WEB&apos;</code>.
              NKJV shard becomes <code>bundle:false</code> then removed.
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
        next={{ href: "/onboarding", label: "Next: Build — onboarding" }}
      />
    </div>
  );
}
