import Link from "next/link";
import { Badge, Button, Card, CardContent, CardDescription, CardHeader, CardTitle } from "@bytecats/ui-kit";
import { Breadcrumbs, PageNav } from "@/components/page-nav";

export default function DocsHub() {
  return (
    <div className="space-y-8">
      <Breadcrumbs items={[{ label: "Home", href: "/" }, { label: "Docs" }]} />
      <header className="space-y-3">
        <Badge>Docs — one topic per page</Badge>
        <h1 className="text-3xl font-semibold tracking-tight">Developer docs</h1>
        <p className="max-w-2xl text-muted-foreground">
          Heavy notes, but never overloaded — pick one page. Each links to the next. Start at architecture.
        </p>
      </header>

      <div className="grid gap-4 md:grid-cols-3">
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Architecture</CardTitle>
            <CardDescription>Zig kit, bible_db, aikit, mobile</CardDescription>
          </CardHeader>
          <CardContent><Button asChild size="sm" className="w-full"><Link href="/docs/architecture">Open →</Link></Button></CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Database</CardTitle>
            <CardDescription>Sharded DBs, manifest, ATTACH</CardDescription>
          </CardHeader>
          <CardContent><Button asChild size="sm" variant="outline" className="w-full"><Link href="/docs/database">Open →</Link></Button></CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Deep Links</CardTitle>
            <CardDescription>HTTPS, metanoia://, ADB</CardDescription>
          </CardHeader>
          <CardContent><Button asChild size="sm" variant="outline" className="w-full"><Link href="/docs/api">Open →</Link></Button></CardContent>
        </Card>
      </div>

      <div className="rounded-lg border bg-muted/30 p-4 text-sm text-muted-foreground">
        Full docs also live in <code>docs/</code> (MAINTENANCE, KIT, SIGNAL_SAFETY, ZIG_DISCOVERIES). This site is the
        curated, navigable surface.
      </div>

      <PageNav prev={{ href: "/onboarding", label: "Back: Onboarding" }} next={{ href: "/docs/architecture", label: "Next: Architecture" }} />
    </div>
  );
}
