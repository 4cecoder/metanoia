"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Button } from "@bytecats/ui-kit";
import { Badge } from "@bytecats/ui-kit";
import { Github, BookOpen, Hammer, ScrollText, HelpCircle } from "lucide-react";

const nav = [
  { href: "/", label: "Overview" },
  { href: "/learn", label: "Learn", icon: ScrollText },
  { href: "/onboarding", label: "Build", icon: Hammer },
  { href: "/docs", label: "Docs", icon: BookOpen },
] as const;

export function SiteHeader() {
  const pathname = usePathname();
  return (
    <header className="sticky top-0 z-30 border-b bg-background/80 backdrop-blur supports-[backdrop-filter]:bg-background/60">
      <div className="mx-auto flex max-w-6xl items-center gap-3 px-5 py-3 sm:px-6 lg:px-8">
        <Link href="/" className="flex items-center gap-2.5 font-semibold tracking-tight">
          <span className="inline-flex h-7 w-7 items-center justify-center rounded-md bg-primary text-primary-foreground text-sm">
            Μ
          </span>
          Metanoia
          <Badge variant="secondary" className="ml-1 hidden sm:inline-flex">
            LXX + GNT
          </Badge>
        </Link>
        <nav className="ml-6 hidden items-center gap-1 md:flex">
          {nav.map((item) => {
            const active = pathname === item.href || (item.href !== "/" && pathname.startsWith(item.href));
            return (
              <Link
                key={item.href}
                href={item.href}
                className={`rounded-md px-2.5 py-1.5 text-sm transition-colors hover:bg-accent hover:text-accent-foreground ${active ? "bg-accent text-accent-foreground" : "text-muted-foreground"}`}
              >
                {item.label}
              </Link>
            );
          })}
        </nav>
        <div className="ml-auto flex items-center gap-2">
          <Button variant="ghost" size="sm" asChild>
            <a href="https://github.com/4cecoder/metanoia" target="_blank" rel="noreferrer">
              <Github className="size-4" /> GitHub
            </a>
          </Button>
          <Button size="sm" asChild>
            <a href="/onboarding">Get Started</a>
          </Button>
        </div>
      </div>
    </header>
  );
}
