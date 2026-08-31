# @bytecats/ui-kit

A shared React component library for bytecats' small products — one kit,
many repos, instead of re-solving buttons and dialogs in every new app.

It combines three upstream open-source projects:

- **[shadcn/ui](https://ui.shadcn.com)** (MIT) — the component layer: accessible
  Radix-based primitives, composed as plain, ownable React + Tailwind source
  you copy into your own repo rather than a black-box npm dependency.
- **[Astryx](https://github.com/facebook/astryx)** (MIT, Meta Platforms, Inc.) —
  the design-token layer: verified color, radius, and typography values
  pulled from Astryx's real published theme packages.
- **[Magic UI](https://magicui.design)** (MIT,
  [magicuidesign/magicui](https://github.com/magicuidesign/magicui)) — a
  small, curated set of animated components (marquee, shimmer button,
  animated beam, ...) layered on top of the same shadcn/ui + Tailwind
  conventions, animated with [Motion](https://motion.dev).

Astryx itself is a React + [StyleX](https://stylexjs.com) design system —
this kit does **not** install the `astryx` package or run StyleX at runtime.
Running two live CSS engines (Tailwind + StyleX) in one component library
would be a mess for consumers. Instead, this kit takes Astryx's **verified
design tokens only** (the actual `dist/theme.css` values from
`@astryxdesign/theme-neutral` and `@astryxdesign/theme-stone` on npm) and
wires them into Tailwind v4's CSS-variable theme layer, which is the
mechanism shadcn/ui itself already expects. shadcn/ui supplies the
components and interaction model; Astryx supplies the look.

## Install

This repo is **private**, and not published to npm — so two things follow:

1. Use the `git+ssh` form, not the `github:` shorthand. `bun add github:...`
   resolves through GitHub's public tarball API and 404s on a private repo
   (verified — it fails outright). `git+ssh` clones over SSH instead:

   ```bash
   bun add "git+ssh://git@github.com/4cecoder/ui-kit.git"
   ```

2. Whatever machine runs this needs read access to the repo. Locally that
   means an SSH key added to the `4cecoder` GitHub account (`ssh -T
   git@github.com` should print a success message). In CI/CD (GitHub
   Actions, Netlify, etc.) that means a deploy key or a fine-grained PAT
   with read access to this repo, configured as a build secret — there's no
   SSH agent to fall back on there.

`dist/` is committed to this repo specifically so this works: a git-based
install doesn't run a build step, and bun blocks the `prepare` lifecycle
script by default on any dependency it doesn't already trust (`bun pm
untrusted` / `bun pm trust` — verified this actually happens on a fresh
install). If `dist/` weren't committed, a git install would silently give
you a package with no compiled output.

## Usage

```tsx
import { Button, Card, CardContent, CardHeader, CardTitle } from "@bytecats/ui-kit";
import "@bytecats/ui-kit/styles.css"; // once, at your app root

function Example() {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Hello</CardTitle>
      </CardHeader>
      <CardContent>
        <Button>Click me</Button>
      </CardContent>
    </Card>
  );
}
```

That single `styles.css` import is all a consuming app needs — it's a fully
compiled Tailwind v4 stylesheet (base layer, component utility classes, and
theme tokens), so **consuming apps do not need Tailwind installed at all**.
This is the correct shape for a Tailwind v4 component library: ship compiled
CSS, not a Tailwind preset/plugin for the consumer to wire up themselves.
(A preset-based approach only makes sense if you want consumers to
re-theme/purge against their own class usage — not the goal here.)

See [`src/demo.tsx`](./src/demo.tsx) for a slightly larger example.

## Components included

A curated general-purpose set — not shadcn's full catalog, not Astryx's
150+ components, not Magic UI's 150+ effects. These are the primitives
nearly every small product repo ends up needing, plus a small set of
genuinely common gaps against Astryx's real catalog and a handful of
well-adapted Magic UI effects.

**Core (shadcn/ui + Astryx tokens):**
`Alert`, `AlertDialog`, `Avatar`, `Badge`, `Breadcrumb`, `Button`, `Calendar`,
`Card`, `Checkbox`, `Collapsible`, `Command`, `Dialog`, `DropdownMenu`,
`HoverCard`, `Input`, `InputGroup`, `Label`, `Pagination`, `Popover`,
`Progress`, `RadioGroup`, `Select`, `Separator`, `Skeleton`, `Slider`,
`Toaster` (Sonner), `Switch`, `Table`, `Tabs`, `Textarea`, `Tooltip`.

**Hand-built (no shadcn equivalent; API design referenced Astryx's own
components — see source comments for exact files cited):**
`EmptyState`, `Kbd`/`KbdGroup`, `SegmentedControl`/`SegmentedControlItem`.

**Magic UI (animated components, see "Magic UI" below):**
`AnimatedBeam`, `BentoGrid`/`BentoCard`, `BorderBeam`, `Confetti`/
`ConfettiButton`, `Marquee`, `NumberTicker`, `ShimmerButton`.

Deliberately left out for now: anything more app-shell-shaped (sidebar,
data-heavy chart/table widgets, forms-library bindings) — those are
product-specific enough that pulling them in here would bias the kit toward
one app's opinions. Add them with the shadcn CLI as a specific product needs
them (see "Adding more components" below); they'll pick up this kit's
Astryx theming automatically since they share the same CSS variables.

## Magic UI

A small, curated slice of [Magic UI](https://github.com/magicuidesign/magicui)
(MIT) — not all 150+ of its components, just the handful that are broadly
useful in a general-purpose product kit rather than landing-page-specific:
`Marquee`, `ShimmerButton`, `AnimatedBeam`, `BentoGrid`, `NumberTicker`,
`BorderBeam`, `Confetti`. Each was pulled from Magic UI's real registry
source (not reconstructed from docs) and adapted to this kit's conventions
— `cn()`, `data-slot` attributes, and Astryx theme CSS variables in place of
Magic UI's hardcoded colors where the component has themeable colors. See
the attribution comment at the top of each component file in
`src/components/ui/` for the exact upstream URL fetched.

These components pull in [`motion`](https://motion.dev) (the current
`framer-motion` successor package — the real Magic UI source imports from
`motion/react`, confirmed by reading it directly rather than assumed) and,
for `Confetti`, `canvas-confetti`. Both are real runtime dependencies of
this kit now, unlike the rest of the component set.

## Theming & dark mode

Two verified Astryx themes ship today:

- **`neutral`** (default) — restrained warm grays, minimal and quiet.
- **`stone`** — warm stone and slate, earthy and understated.

Switch themes with a single HTML attribute, no JS or rebuild required:

```html
<html data-ui-theme="stone">
```

Omit the attribute (or use `data-ui-theme="neutral"`) for the default.

**Dark mode is automatic and requires no toggle, no `.dark` class, and no
JavaScript.** Every Astryx color token is wired through CSS's `light-dark()`
function exactly as Astryx itself ships them, and `color-scheme: light dark`
is set on `:root`. The browser picks light or dark based on the user's OS/
browser preference (`prefers-color-scheme`) automatically. Tailwind v4's
`dark:` utility variant is left at its default (`@media
(prefers-color-scheme: dark)`) so both the CSS variables and any `dark:`
utility classes inside components stay in sync — there's no `.dark` class
to toggle in the first place, so there's nothing for app code to get out of
sync with.

## Where the token values come from

Per-instructions, token values were **not** taken from docs pages or blog
summaries. They were pulled directly from the real published npm tarballs:

```bash
npm pack @astryxdesign/theme-neutral@0.1.7
npm pack @astryxdesign/theme-stone@0.1.7
npm pack @astryxdesign/core@0.1.7
```

...then extracted and read straight out of each package's own generated
`dist/theme.css` (and `dist/astryx.css` for the shared spacing scale).
Every value in [`src/styles/globals.css`](./src/styles/globals.css) is
copied verbatim from those files — see the source comments in that file for
the exact package + version cited next to each block.

Both `@astryxdesign/theme-neutral@0.1.7` and `@astryxdesign/theme-stone@0.1.7`
are MIT-licensed, Copyright (c) 2026 Meta Platforms, Inc. — confirmed by
reading each package's own `LICENSE` file inside the tarball (not assumed).
The [facebook/astryx](https://github.com/facebook/astryx) repository itself
is also MIT-licensed. See [`LICENSE`](./LICENSE) for full attribution.

Astryx also publishes `theme-butter`, `theme-chocolate`, `theme-matcha`,
`theme-gothic`, and `theme-y2k` — all real, all MIT, and all could be added
the same way if a product needs a different visual identity.

## Adding more components

This repo keeps `components.json` around, so the shadcn CLI still works
directly against it:

```bash
bunx shadcn@latest add <component> --cwd .
```

New components land in `src/components/ui/`; re-export them from
`src/index.ts` and rebuild.

## Building

```bash
bun install
bun run build   # compiles src/styles/globals.css -> dist/styles.css (Tailwind v4 CLI),
                 # then bundles src/index.ts -> dist/{index.js,index.cjs,index.d.ts} (tsup)
```

`react` and `react-dom` are peer dependencies — this package does not bundle
them.

## Attribution

- Component source in `src/components/ui/` is generated by and derived from
  the [shadcn/ui](https://ui.shadcn.com) registry (MIT, Copyright (c) 2023
  shadcn), via `bunx shadcn@latest add`, then wired to Astryx-sourced theme
  tokens instead of shadcn's stock palette.
- Design tokens in `src/styles/globals.css` are sourced from
  [Meta's Astryx design system](https://github.com/facebook/astryx) (MIT,
  Copyright (c) 2026 Meta Platforms, Inc.), specifically the
  `@astryxdesign/theme-neutral` and `@astryxdesign/theme-stone` npm
  packages. `EmptyState`, `Kbd`/`KbdGroup`, and
  `SegmentedControl`/`SegmentedControlItem` have no shadcn equivalent and
  were hand-built for this kit; their prop shapes were informed by reading
  Astryx's own component source for the same components (cited in each
  file's header comment), not copied — Astryx ships those as React +
  StyleX, this kit ships them as plain Tailwind components.
- `AnimatedBeam`, `BentoGrid`/`BentoCard`, `BorderBeam`, `Confetti`/
  `ConfettiButton`, `Marquee`, `NumberTicker`, and `ShimmerButton` in
  `src/components/ui/` are adapted from
  [Magic UI](https://github.com/magicuidesign/magicui) (MIT), pulled
  directly from its real registry source and re-themed to this kit's
  Astryx CSS variables (see "Magic UI" above and each file's header
  comment for the exact upstream source fetched).

This project is not affiliated with or endorsed by shadcn, Meta, or Magic UI.

## License

MIT — see [LICENSE](./LICENSE).
