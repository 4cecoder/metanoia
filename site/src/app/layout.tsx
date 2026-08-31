import type { Metadata } from "next";
import "@bytecats/ui-kit/styles.css";
import "./globals.css";
import { SiteHeader } from "@/components/site-header";
import { SiteFooter } from "@/components/site-footer";

export const metadata: Metadata = {
  title: "Metanoia — Greek Bible Study (LXX + GNT)",
  description:
    "Septuagint-first Bible study app in Zig + GTK4. LXX + GNT as one Greek story; Masoretic as comparison. Developer portal, deep links, and onboarding.",
  metadataBase: new URL("https://4cecoder.github.io/metanoia"),
  openGraph: {
    title: "Metanoia — Septuagint-first Bible Study",
    description: "LXX + GNT as primary roots. Masoretic buried, not deleted.",
    type: "website",
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" data-ui-theme="neutral">
      <body className="min-h-screen bg-background text-foreground antialiased">
        <SiteHeader />
        <main className="mx-auto max-w-6xl px-5 py-10 sm:px-6 lg:px-8">
          {children}
        </main>
        <SiteFooter />
      </body>
    </html>
  );
}
