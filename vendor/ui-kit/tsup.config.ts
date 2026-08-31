import { defineConfig } from "tsup";
import { preserveDirectivesPlugin } from "@hyperse/esbuild-plugin-preserve-directives";

export default defineConfig({
  entry: ["src/index.ts"],
  format: ["esm", "cjs"],
  dts: true,
  sourcemap: true,
  clean: false, // build:css runs first and writes dist/styles.css — don't wipe it
  splitting: false,
  external: ["react", "react-dom"],
  // esbuild (which tsup wraps) strips "use client" source directives during
  // bundling by design (github.com/evanw/esbuild/issues/3115) — verified
  // empirically: without this, dist/index.js had zero occurrences despite
  // every interactive component's source having one, which broke every
  // consuming Next.js App Router app (createContext is not a function,
  // since the whole bundle got treated as a Server Component). A plain
  // esbuild `banner` doesn't work either — esbuild detects and strips
  // banner-injected directive-shaped strings too. This plugin patches the
  // directive back into the output after esbuild's own processing.
  // Required by the plugin: treeshake must be off (it treeshakes itself).
  treeshake: false,
  esbuildPlugins: [
    preserveDirectivesPlugin({
      directives: ["use client"],
      include: /\.(js|ts|jsx|tsx)$/,
      exclude: /node_modules/,
    }),
  ],
});
