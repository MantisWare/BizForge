// Font preference store

export type FontOption = "inter" | "system" | "manrope";

const STORAGE_KEY = "bizforge-font";

const FONT_MAP: Record<FontOption, string> = {
  inter:
    '"Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
  system:
    '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
  manrope:
    '"Manrope", "Inter", -apple-system, BlinkMacSystemFont, sans-serif',
};

class FontStore {
  font = $state<FontOption>("inter");

  constructor() {
    if (typeof window === "undefined") return;
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored === "inter" || stored === "system" || stored === "manrope") {
      this.font = stored;
    }
    this.#apply();
  }

  setFont(font: FontOption): void {
    this.font = font;
    if (typeof window !== "undefined") {
      localStorage.setItem(STORAGE_KEY, font);
    }
    this.#apply();
  }

  #apply(): void {
    if (typeof document === "undefined") return;
    document.documentElement.style.setProperty(
      "--font-sans",
      FONT_MAP[this.font],
    );
  }
}

export const fontStore = new FontStore();

export const FONT_OPTIONS: { id: FontOption; label: string }[] = [
  { id: "inter", label: "Inter" },
  { id: "system", label: "System" },
  { id: "manrope", label: "Manrope" },
];
