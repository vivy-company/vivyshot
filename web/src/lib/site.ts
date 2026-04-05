import en from "../i18n/translations/en.json";
import zh from "../i18n/translations/zh.json";

export const SITE = {
  name: "VivyShot: Screen Studio",
  shortName: "VivyShot",
  siteUrl: "https://vivyshot.com",
  title: "VivyShot: Screen Studio for macOS",
  description:
    "VivyShot: Screen Studio is an open source screenshot, annotation, and recording app built around a portable engine and native UI on each platform.",
  downloadUrl: "",
  githubUrl: "https://github.com/vivy-company/vivyshot",
  themeStorageKey: "vivyshot-theme",
  languageStorageKey: "vivyshot-language",
};

export const translations = { en, zh } as const;

export const softwareSchema = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: "VivyShot: Screen Studio",
  applicationCategory: "GraphicsApplication",
  operatingSystem: "macOS",
  description:
    "Open source screenshot, annotation, and recording software built around a portable engine and native UI on each platform.",
  url: "https://vivyshot.com/",
  image: "https://vivyshot.com/og.png",
  author: {
    "@type": "Organization",
    name: "Vivy Technologies",
  },
  softwareVersion: "0.1",
  features: [
    "Screenshot capture",
    "Annotations and callouts",
    "Recording workflow",
    "Export-focused editing",
    "Open source",
    "Focused daily workflow",
    "Portable engine",
    "Native platform UI",
  ],
};

export const websiteSchema = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "WebSite",
      name: "VivyShot: Screen Studio",
      url: "https://vivyshot.com/",
    },
    {
      "@type": "Organization",
      name: "Vivy Technologies",
      url: "https://vivyshot.com/",
      logo: "https://vivyshot.com/logo.png",
    },
  ],
};
