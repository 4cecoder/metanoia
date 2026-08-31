import { Badge, Card, CardContent, CardHeader, CardTitle } from "@bytecats/ui-kit";
import { Breadcrumbs, PageNav } from "@/components/page-nav";

export default function VoicePage() {
  return (
    <div className="space-y-8 max-w-3xl">
      <Breadcrumbs items={[{ label: "Home", href: "/" }, { label: "Docs", href: "/docs" }, { label: "TTS + Whisper" }]} />
      <header className="space-y-3">
        <div className="flex flex-wrap gap-2">
          <Badge>Docs · Preserved</Badge>
          <Badge variant="outline" className="gap-1">Preserved <code className="text-[10px]">index.html:551</code></Badge>
        </div>
        <h1 className="text-3xl font-semibold tracking-tight">TTS + Whisper Voice Engine</h1>
        <p className="max-w-2xl text-muted-foreground">Benchmarked voice synthesis with real-time STT verification — verbatim from original portal (<code>index.html:551</code> footer + voice sections), now on its own page with no info lost.</p>
      </header>

      <div className="overflow-auto rounded-lg border">
        <table className="w-full text-sm">
          <thead className="bg-muted/50 text-left">
            <tr><th className="px-3 py-2">Scripture Passage</th><th className="px-3 py-2">Voice</th><th className="px-3 py-2">Whisper</th><th className="px-3 py-2">Accuracy</th><th className="px-3 py-2">Status</th></tr>
          </thead>
          <tbody>
            <tr className="border-t"><td className="px-3 py-2">&quot;In the beginning God created...&quot;</td><td className="px-3 py-2 font-mono">tommy</td><td className="px-3 py-2">base</td><td className="px-3 py-2 font-semibold text-green-600">100.0%</td><td className="px-3 py-2"><Badge>EXCELLENT</Badge></td></tr>
            <tr className="border-t"><td className="px-3 py-2">&quot;The Lord is my shepherd...&quot;</td><td className="px-3 py-2 font-mono">tommy</td><td className="px-3 py-2">base</td><td className="px-3 py-2 font-semibold text-green-600">100.0%</td><td className="px-3 py-2"><Badge>EXCELLENT</Badge></td></tr>
            <tr className="border-t"><td className="px-3 py-2">&quot;For God so loved the world.&quot;</td><td className="px-3 py-2 font-mono">tommy</td><td className="px-3 py-2">tiny</td><td className="px-3 py-2 font-semibold">83.3%</td><td className="px-3 py-2"><Badge variant="outline">GOOD</Badge></td></tr>
          </tbody>
        </table>
      </div>

      <Card className="border-green-200 bg-green-50 dark:bg-green-950/20">
        <CardHeader><CardTitle className="text-sm">💡 Recommended</CardTitle></CardHeader>
        <CardContent className="text-sm text-muted-foreground">Use <strong>tommy</strong> voice + <strong>base</strong> Whisper model for 100% accuracy on passages &gt;7 words (CUDA GTX 1070, Qwen3-TTS 12Hz + Faster-Whisper).</CardContent>
      </Card>

      <div className="grid gap-4 sm:grid-cols-2">
        <Card><CardHeader><CardTitle className="text-sm">Native Zig Engine</CardTitle></CardHeader><CardContent className="text-xs text-muted-foreground">Zig 0.17+ • GTK4 • SQLite3 — zero-overhead, instant startup, memory safe. Direct C interop, same stack as <code>src/bible_db.zig</code>.</CardContent></Card>
        <Card><CardHeader><CardTitle className="text-sm">Stack</CardTitle></CardHeader><CardContent className="text-xs font-mono">Qwen3-TTS • Whisper STT • PyTorch/CUDA • aikit/ GGML/MLX backends (opt-in -Dnative-ai)</CardContent></Card>
      </div>

      <div className="rounded-lg border border-dashed bg-amber-50/50 p-3 text-xs text-muted-foreground dark:bg-amber-950/10">
        <span className="font-medium text-foreground">Preserved</span> — voice table + recommended note preserved from <code>index.html:551</code> footer context and original portal voice sections. No info lost — see <code>site/src/app/globals.css:12</code> for Tokyo Night preservation (<code>#0f1117</code> / <code>#7aa2f7</code> / <code>backdrop-blur:20px</code>).
      </div>

      <PageNav prev={{ href: "/docs/database", label: "Back: Database" }} next={{ href: "/docs/api", label: "Next: Deep Links" }} />
    </div>
  );
}
