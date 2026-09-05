import en from "../i18n/translations/en.json";
import zh from "../i18n/translations/zh.json";
import ja from "../i18n/translations/ja.json";
import ko from "../i18n/translations/ko.json";
import de from "../i18n/translations/de.json";
import fr from "../i18n/translations/fr.json";
import es from "../i18n/translations/es.json";
import ru from "../i18n/translations/ru.json";
import be from "../i18n/translations/be.json";
import uk from "../i18n/translations/uk.json";

export const SITE = {
  name: "VivyShot",
  shortName: "VivyShot",
  siteUrl: "https://vivyshot.com",
  appStoreUrl: "https://apps.apple.com/us/app/id6760658121",
  title: "VivyShot — Screenshots and screen recording for Mac",
  description:
    "VivyShot is an open source screenshot, annotation, and recording app built to stay simple, fast, and native on macOS.",
  downloadUrl: "https://apps.apple.com/us/app/id6760658121",
  githubUrl: "https://github.com/vivy-company/vivyshot",
};

export const translations = { en, zh, ja, ko, de, fr, es, ru, be, uk } as const;

export const languageOptions = [
  { code: "en", label: "English", htmlLang: "en", ogLocale: "en_US" },
  { code: "zh", label: "中文", htmlLang: "zh-CN", ogLocale: "zh_CN" },
  { code: "ja", label: "日本語", htmlLang: "ja", ogLocale: "ja_JP" },
  { code: "ko", label: "한국어", htmlLang: "ko", ogLocale: "ko_KR" },
  { code: "de", label: "Deutsch", htmlLang: "de", ogLocale: "de_DE" },
  { code: "fr", label: "Français", htmlLang: "fr", ogLocale: "fr_FR" },
  { code: "es", label: "Español", htmlLang: "es", ogLocale: "es_ES" },
  { code: "ru", label: "Русский", htmlLang: "ru", ogLocale: "ru_RU" },
  { code: "be", label: "Беларуская", htmlLang: "be", ogLocale: "be_BY" },
  { code: "uk", label: "Українська", htmlLang: "uk", ogLocale: "uk_UA" },
] as const;

export const softwareSchema = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: "VivyShot",
  applicationCategory: "GraphicsApplication",
  operatingSystem: "macOS",
  description:
    "Open source screenshot, annotation, and recording software built to stay simple, fast, and native on macOS.",
  url: "https://vivyshot.com/",
  downloadUrl: "https://apps.apple.com/us/app/id6760658121",
  image: "https://vivyshot.com/og.png",
  author: {
    "@type": "Organization",
    name: "Vivy Technologies",
  },
  features: [
    "Screenshot capture",
    "Annotations and callouts",
    "Recording workflow",
    "Export-focused editing",
    "Open source",
    "Focused daily workflow",
    "Native macOS UI",
  ],
};

export const websiteSchema = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "WebSite",
      name: "VivyShot",
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
