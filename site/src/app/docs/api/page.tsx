import { Badge, Card, CardContent, CardHeader, CardTitle } from "@bytecats/ui-kit";
import { Breadcrumbs, PageNav } from "@/components/page-nav";

export default function ApiPage() {
  return (
    <div className="space-y-8 max-w-3xl">
      <Breadcrumbs items={[{ label: "Home", href: "/" }, { label: "Docs", href: "/docs" }, { label: "Deep Links" }]} />
      <header className="space-y-3">
        <Badge>Docs · API</Badge>
        <h1 className="text-3xl font-semibold tracking-tight">Deep links</h1>
        <p className="text-muted-foreground">Two shapes, same resolver. Minimal — full table lives here, not on homepage.</p>
      </header>

      <div className="grid gap-4 sm:grid-cols-2">
        <Card>
          <CardHeader><CardTitle className="text-sm">HTTPS (App Link)</CardTitle></CardHeader>
          <CardContent className="space-y-2 text-xs font-mono">
            <div className="rounded bg-muted p-2">https://metanoia.bytecats.codes/bible/John/3/16</div>
            <div className="rounded bg-muted p-2">https://metanoia.bytecats.codes/bible/jn/3/16</div>
            <div className="rounded bg-muted p-2">https://metanoia.bytecats.codes/bible/1Samuel/17/45</div>
            <p className="font-sans text-muted-foreground">Verified via .well-known/assetlinks.json (see site/public/.well-known/)</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader><CardTitle className="text-sm">metanoia://</CardTitle></CardHeader>
          <CardContent className="space-y-2 text-xs font-mono">
            <div className="rounded bg-muted p-2">metanoia://bible/John/3/16</div>
            <div className="rounded bg-muted p-2">metanoia://bible/SongofSolomon/2/1</div>
            <p className="font-sans text-muted-foreground">No web verification — direct intent</p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader><CardTitle className="text-sm">Test via ADB</CardTitle></CardHeader>
        <CardContent>
          <pre className="rounded bg-muted p-3 text-xs overflow-auto">{`adb shell am start -W -a android.intent.action.VIEW \\
  -d "metanoia://bible/John/3/16" com.bytecats.metanoia`}</pre>
        </CardContent>
      </Card>

      <PageNav prev={{ href: "/docs/database", label: "Back: Database" }} next={{ href: "/", label: "Back to home" }} />
    </div>
  );
}
