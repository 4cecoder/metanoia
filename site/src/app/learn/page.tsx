import Link from "next/link";
import { Badge, Button, Card, CardContent, CardDescription, CardHeader, CardTitle } from "@bytecats/ui-kit";
import { Breadcrumbs, PageNav } from "@/components/page-nav";

export default function LearnHub() {
  return (
    <div className="space-y-8">
      <Breadcrumbs items={[{ label: "Home", href: "/" }, { label: "Learn" }]} />
      <header className="space-y-3">
        <Badge variant="secondary">Learn — educational material</Badge>
        <h1 className="text-3xl font-semibold tracking-tight">Learn before you build</h1>
        <p className="max-w-2xl text-muted-foreground">
          Three short pages. Each does one job. No overload — tap through in order and you&apos;ll
          land on developer docs exactly when you need them.
        </p>
      </header>

      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        <Card className="flex flex-col">
          <CardHeader>
            <Badge className="w-fit">1</Badge>
            <CardTitle className="text-base">Why LXX First</CardTitle>
            <CardDescription>Timeline: LXX 3rd c. BCE → NT quotes → MT pointed 7th–10th c.</CardDescription>
          </CardHeader>
          <CardContent className="mt-auto">
            <Button asChild size="sm" className="w-full"><Link href="/history">Read — 2 min</Link></Button>
          </CardContent>
        </Card>
        <Card className="flex flex-col">
          <CardHeader>
            <Badge className="w-fit" variant="secondary">2</Badge>
            <CardTitle className="text-base">LXX vs Masoretic</CardTitle>
            <CardDescription>What differs, why both matter, where DSS sides with LXX</CardDescription>
          </CardHeader>
          <CardContent className="mt-auto">
            <Button asChild size="sm" variant="outline" className="w-full"><Link href="/learn/lxx-vs-mt">Compare — 2 min</Link></Button>
          </CardContent>
        </Card>
        <Card className="flex flex-col">
          <CardHeader>
            <Badge className="w-fit" variant="outline">3</Badge>
            <CardTitle className="text-base">Canon & Translations</CardTitle>
            <CardDescription>82 books, primary vs comparison, interesting sources</CardDescription>
          </CardHeader>
          <CardContent className="mt-auto">
            <Button asChild size="sm" variant="outline" className="w-full"><Link href="/learn/canon">Explore →</Link></Button>
          </CardContent>
        </Card>
        <Card className="flex flex-col border-amber-200">
          <CardHeader>
            <Badge className="w-fit" variant="outline">4</Badge>
            <CardTitle className="text-base">English Rendering</CardTitle>
            <CardDescription>NKJV trap + Roger&apos;s PD fix (Brenton vs WEB/KJV)</CardDescription>
          </CardHeader>
          <CardContent className="mt-auto">
            <Button asChild size="sm" variant="outline" className="w-full"><Link href="/learn/english">Fix English →</Link></Button>
          </CardContent>
        </Card>
      </div>

      <div className="rounded-lg border bg-muted/30 p-4 text-sm">
        <span className="font-medium">Flow:</span> Learn (this page) → Why LXX First → LXX vs MT → Canon →{" "}
        <Link href="/onboarding" className="underline">Onboarding (Build)</Link> →{" "}
        <Link href="/docs" className="underline">Docs</Link>. Each page ends with a single Next button.
      </div>

      <PageNav next={{ href: "/history", label: "Start: Why LXX First" }} />
    </div>
  );
}
