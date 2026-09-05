import { SITE, languageOptions } from "../lib/site";
import { homePath } from "../i18n/utils";

export function GET() {
  const paths = [...languageOptions.map(({ code }) => homePath(code)), "/privacy", "/terms", "/refund"];
  return new Response(`<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${paths.map(path => `  <url><loc>${new URL(path, SITE.siteUrl)}</loc></url>`).join("\n")}
</urlset>`, { headers: { "Content-Type": "application/xml; charset=utf-8" } });
}
