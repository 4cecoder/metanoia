import Link from "next/link";
import { Badge, Card, CardContent, CardHeader, CardTitle } from "@bytecats/ui-kit";
import { Breadcrumbs, PageNav } from "@/components/page-nav";

export default function DatabasePage() {
  return (
    <div className="space-y-8 max-w-3xl">
      <Breadcrumbs items={[{ label: "Home", href: "/" }, { label: "Docs", href: "/docs" }, { label: "Database" }]} />
      <header className="space-y-3">
        <Badge>Docs · Database</Badge>
        <h1 className="text-3xl font-semibold tracking-tight">Sharded DBs</h1>
        <p className="text-muted-foreground">Monolith broken extremely well — each version/source its own file.</p>
      </header>

      <Card>
        <CardHeader>
          <CardTitle className="text-sm">Manifest — 7 shards today</CardTitle>
        </CardHeader>
        <CardContent className="text-xs font-mono space-y-1">
          <div>data/db/manifest.json — single source of truth (see tools/bible/split_db.py SHARDS)</div>
          <div>
            default_bundle: core.db, verses.lxxe.db, interlinear.lxx.db, interlinear.gnt.db, lexicon.db (5 files, ~82 MB
            measured — ~70 MB design in docs/DB_SHARDING.md)
          </div>
          <div>buried not shipped: interlinear.mt.db (233k), verses.nkjv.db (31k → WEB) — bundle:false, on-demand only</div>
          <div className="text-muted-foreground pt-1">
            Planned next: verses.web.db (WEB PD) + verses.kjv.db (KJV PD/Crown) via scripts/import-translation.js — replaces NKJV.
          </div>
        </CardContent>
      </Card>

      <div className="overflow-auto rounded-lg border text-xs">
        <table className="w-full">
          <thead className="bg-muted/50">
            <tr>
              <th className="px-2 py-1 text-left">Shard</th>
              <th className="px-2 py-1 text-left">Filter</th>
              <th className="px-2 py-1 text-right">Rows</th>
              <th className="px-2 py-1 text-left">Primacy</th>
            </tr>
          </thead>
          <tbody>
            <tr className="border-t">
              <td className="px-2 py-1 font-mono">core.db</td>
              <td className="px-2 py-1 font-mono text-[10px]">core tables only</td>
              <td className="px-2 py-1 text-right">5+3+0+4</td>
              <td className="px-2 py-1">
                <Badge variant="secondary" className="text-[10px]">core</Badge>
              </td>
            </tr>
            <tr className="border-t">
              <td className="px-2 py-1 font-mono">verses.lxxe.db</td>
              <td className="px-2 py-1 font-mono text-[10px]">verses.version=&apos;LXXE&apos;</td>
              <td className="px-2 py-1 text-right">27,058</td>
              <td className="px-2 py-1">
                <Badge className="text-[10px]">primary</Badge>
              </td>
            </tr>
            <tr className="border-t bg-amber-50 dark:bg-amber-950/10">
              <td className="px-2 py-1 font-mono">verses.nkjv.db</td>
              <td className="px-2 py-1 font-mono text-[10px]">verses.version=&apos;NKJV&apos;</td>
              <td className="px-2 py-1 text-right">31,102</td>
              <td className="px-2 py-1">
                <Badge variant="outline" className="text-[10px]">buried → WEB</Badge>
              </td>
            </tr>
            <tr className="border-t">
              <td className="px-2 py-1 font-mono">interlinear.lxx.db</td>
              <td className="px-2 py-1 font-mono text-[10px]">interlinear.source=&apos;LXX&apos;</td>
              <td className="px-2 py-1 text-right">432,676</td>
              <td className="px-2 py-1">
                <Badge className="text-[10px]">primary</Badge>
              </td>
            </tr>
            <tr className="border-t">
              <td className="px-2 py-1 font-mono">interlinear.gnt.db</td>
              <td className="px-2 py-1 font-mono text-[10px]">interlinear.source=&apos;GNT&apos;</td>
              <td className="px-2 py-1 text-right">138,994</td>
              <td className="px-2 py-1">
                <Badge className="text-[10px]">primary</Badge>
              </td>
            </tr>
            <tr className="border-t bg-muted/20">
              <td className="px-2 py-1 font-mono">interlinear.mt.db</td>
              <td className="px-2 py-1 font-mono text-[10px]">interlinear.source=&apos;MT&apos;</td>
              <td className="px-2 py-1 text-right">233,343</td>
              <td className="px-2 py-1">
                <Badge variant="outline" className="text-[10px]">buried</Badge>
              </td>
            </tr>
            <tr className="border-t">
              <td className="px-2 py-1 font-mono">lexicon.db</td>
              <td className="px-2 py-1 font-mono text-[10px]">lexicon only</td>
              <td className="px-2 py-1 text-right">6,338</td>
              <td className="px-2 py-1">
                <Badge variant="secondary" className="text-[10px]">shared</Badge>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p className="text-[11px] text-muted-foreground">
        Dry-run (#7 shards) → <code>/tmp/metanoia-shard-test/manifest.json</code> validated:{" "}
        <code>source_bytes 123318272 (118 MB)</code>, <code>source_sha256 8a6539a7…</code>, per-shard
        sha256 in manifest, <code>default_bundle 5 files ~82 MB</code> (core 76K + lxxe 5.2M + lxx 57.2M + gnt
        18.7M + lex 0.4M). Matches <code>tools/bible/split_db.py:31–92 SHARDS</code> order +{" "}
        <code>keep_sql</code> predicates. See <code>docs/DB_SHARDING.md:30–65</code> for design vs measured.
      </p>

      <p className="text-sm text-muted-foreground">
        Script: <code>tools/bible/split_db.py --source data/bible.db --out data/db</code> — VACUUM INTO + DELETE
        WHERE NOT (<code>keep_sql</code> filter) + VACUUM. Each shard is a valid SQLite file with its own{" "}
        <code>CREATE TABLE</code>. Zig opens via <code>ATTACH DATABASE &apos;data/db/&lt;file&gt;&apos; AS schema</code> with
        fallback to legacy <code>data/bible.db</code> if manifest absent. See{" "}
        <Link href="/docs" className="underline">
          docs/DB_SHARDING.md
        </Link>{" "}
        +{" "}
        <Link href="/learn/english" className="underline">
          Learn → English
        </Link>{" "}
        for NKJV→WEB rationale.
      </p>

      <PageNav prev={{ href: "/docs/architecture", label: "Back: Architecture" }} next={{ href: "/docs/voice", label: "Next: TTS + Whisper" }} />
    </div>
  );
}
