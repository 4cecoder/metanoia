import { Badge, Card, CardContent, CardHeader, CardTitle } from "@bytecats/ui-kit";
import { Breadcrumbs, PageNav } from "@/components/page-nav";

export default function ArchitecturePage() {
  return (
    <div className="space-y-8 max-w-3xl">
      <Breadcrumbs items={[{ label: "Home", href: "/" }, { label: "Docs", href: "/docs" }, { label: "Architecture" }]} />
      <header className="space-y-3">
        <Badge>Docs · Architecture</Badge>
        <h1 className="text-3xl font-semibold tracking-tight">How Metanoia is built</h1>
        <p className="text-muted-foreground">One diagram — each layer maps to a folder you can open.</p>
      </header>

      <Card>
        <CardHeader><CardTitle className="text-sm">Layers</CardTitle></CardHeader>
        <CardContent className="space-y-2 text-sm font-mono text-xs">
          <div>src/kit/ — 12-file GTK widget kit (ffi, widget, signal, theme, components/*) — see docs/KIT.md</div>
          <div>src/bible_db.zig — core.db + sharded verses/interlinear + lexicon, ATTACH pattern (docs/DB_SHARDING.md)</div>
          <div>src/main.zig:403-417 load_chapter_into_study — picks LXXE+GNT vs NKJV+MT by config.ot_source</div>
          <div>aikit/ — native TTS/LLM GGML/MLX backends, sidecar pattern (like septcheck lxx_server.py)</div>
          <div>mobile/ — Kotlin + Compose, BibleManager.kt mirrors same otTextTradition flag</div>
          <div>site/ — this Next.js 16 + Bun + @bytecats/ui-kit static export (output: export)</div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle className="text-sm">Why Zig + GTK4</CardTitle></CardHeader>
        <CardContent className="text-sm text-muted-foreground">
          Same reason Fedora is no-build vanilla JS and septcheck is FastAPI: own the hot path. Zig gives
          C-interop for sqlite3 + GTK without Node, and kit/signal.zig catches DestroyNotify ABI bugs at compile time (docs/SIGNAL_SAFETY.md).
        </CardContent>
      </Card>

      <PageNav prev={{ href: "/docs", label: "Back: Docs hub" }} next={{ href: "/docs/database", label: "Next: Database" }} />
    </div>
  );
}
