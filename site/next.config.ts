import type { NextConfig } from "next";

const isProd = process.env.NODE_ENV === "production";
// GitHub Pages serves user/organization pages at / and project pages at /<repo>.
// Metanoia is a project page (4cecoder/metanoia) in prod, but next dev runs at /.
const repoBase = process.env.PAGES_BASE_PATH ?? "";

const nextConfig: NextConfig = {
  // Static export for GitHub Pages — no Node server at runtime.
  // Matches septcheck/frontend/next.config.ts and FedoraBible's public/ static model.
  output: "export",
  trailingSlash: true,
  images: { unoptimized: true },
  // Only set basePath/assetPrefix when building for Pages project subpath.
  ...(repoBase
    ? { basePath: repoBase, assetPrefix: `${repoBase}/` }
    : {}),
};

export default nextConfig;
