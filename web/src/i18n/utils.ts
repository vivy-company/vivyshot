import { languageOptions } from "../lib/site";

export type Language = (typeof languageOptions)[number]["code"];

export function getLanguage(url: URL): Language {
  return languageOptions.find(({ code }) => code === url.pathname.split("/")[1])?.code ?? "en";
}

export function homePath(language: Language): string {
  return language === "en" ? "/" : `/${language}/`;
}
