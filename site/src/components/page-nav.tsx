"use client";

import Link from "next/link";
import { Button } from "@bytecats/ui-kit";
import { ArrowLeft, ArrowRight } from "lucide-react";

export function PageNav({
  prev,
  next,
}: {
  prev?: { href: string; label: string };
  next?: { href: string; label: string };
}) {
  return (
    <div className="flex items-center justify-between gap-4 border-t pt-6 mt-10">
      <div>
        {prev && (
          <Button variant="ghost" asChild>
            <Link href={prev.href} className="gap-2">
              <ArrowLeft className="size-4" /> {prev.label}
            </Link>
          </Button>
        )}
      </div>
      <div>
        {next && (
          <Button asChild>
            <Link href={next.href} className="gap-2">
              {next.label} <ArrowRight className="size-4" />
            </Link>
          </Button>
        )}
      </div>
    </div>
  );
}

export function Breadcrumbs({ items }: { items: { label: string; href?: string }[] }) {
  return (
    <nav className="flex flex-wrap items-center gap-1.5 text-xs text-muted-foreground">
      {items.map((it, i) => (
        <span key={i} className="flex items-center gap-1.5">
          {i > 0 && <span className="opacity-40">/</span>}
          {it.href ? (
            <Link href={it.href} className="hover:text-foreground underline-offset-4 hover:underline">
              {it.label}
            </Link>
          ) : (
            <span className="text-foreground">{it.label}</span>
          )}
        </span>
      ))}
    </nav>
  );
}
