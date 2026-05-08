import { chromium, type Browser, type BrowserContext, type Page } from "playwright";
import type {
  TabInfo,
  SnapshotResult,
  ScreenshotResult,
  NetworkEntry,
  ConsoleEntry,
} from "./types.js";

interface TabState {
  page: Page;
  networkEntries: NetworkEntry[];
  consoleEntries: ConsoleEntry[];
}

export class BrowserManager {
  private browser: Browser | null = null;
  private contexts: Map<string, BrowserContext> = new Map();
  private tabs: Map<string, TabState> = new Map();
  private activeTabId: string | null = null;
  private tabCounter = 0;

  async ensureBrowser(): Promise<Browser> {
    if (this.browser === null) {
      this.browser = await chromium.launch({
        headless: true,
        args: ["--no-sandbox", "--disable-setuid-sandbox", "--ignore-certificate-errors"],
      });
    }
    return this.browser;
  }

  async getOrCreateContext(sessionId: string = "default"): Promise<BrowserContext> {
    const existing = this.contexts.get(sessionId);
    if (existing !== undefined) return existing;

    const browser = await this.ensureBrowser();
    const context = await browser.newContext({
      ignoreHTTPSErrors: true,
      viewport: { width: 1280, height: 720 },
    });
    this.contexts.set(sessionId, context);
    return context;
  }

  private async getActivePage(): Promise<Page> {
    if (this.activeTabId === null) {
      const context = await this.getOrCreateContext();
      const page = await context.newPage();
      const id = `tab-${++this.tabCounter}`;
      this.registerTab(id, page);
      this.activeTabId = id;
    }
    const tab = this.tabs.get(this.activeTabId);
    if (tab === undefined) throw new Error("Active tab not found");
    return tab.page;
  }

  private registerTab(id: string, page: Page): void {
    const state: TabState = { page, networkEntries: [], consoleEntries: [] };

    page.on("response", (resp) => {
      state.networkEntries.push({
        method: resp.request().method(),
        url: resp.url(),
        status: resp.status(),
        content_type: resp.headers()["content-type"] ?? null,
        timestamp: Date.now(),
      });
      if (state.networkEntries.length > 200) {
        state.networkEntries = state.networkEntries.slice(-100);
      }
    });

    page.on("console", (msg) => {
      state.consoleEntries.push({
        type: msg.type(),
        text: msg.text(),
        timestamp: Date.now(),
      });
      if (state.consoleEntries.length > 200) {
        state.consoleEntries = state.consoleEntries.slice(-100);
      }
    });

    this.tabs.set(id, state);
  }

  async dispatch(method: string, params: Record<string, unknown>): Promise<unknown> {
    switch (method) {
      case "browser_navigate":
        return this.navigate(params["url"] as string);
      case "browser_navigate_back":
        return this.navigateBack();
      case "browser_snapshot":
        return this.snapshot(params["take_screenshot_afterwards"] as boolean | undefined);
      case "browser_take_screenshot":
        return this.takeScreenshot();
      case "browser_click":
        return this.click(params["ref"] as string, params["selector"] as string | undefined);
      case "browser_mouse_click_xy":
        return this.clickXY(params["x"] as number, params["y"] as number);
      case "browser_fill":
        return this.fill(params["ref"] as string | undefined, params["selector"] as string | undefined, params["value"] as string);
      case "browser_type":
        return this.type(params["text"] as string);
      case "browser_hover":
        return this.hover(params["ref"] as string | undefined, params["selector"] as string | undefined);
      case "browser_press_key":
        return this.pressKey(params["key"] as string);
      case "browser_select":
        return this.select(params["ref"] as string | undefined, params["selector"] as string | undefined, params["value"] as string);
      case "browser_scroll":
        return this.scroll(params["direction"] as string | undefined, params["amount"] as number | undefined);
      case "browser_console_messages":
        return this.consoleMessages();
      case "browser_network_requests":
        return this.networkRequests();
      case "browser_handle_dialog":
        return this.handleDialog(params["accept"] as boolean | undefined, params["promptText"] as string | undefined);
      case "browser_tabs":
        return this.listTabs(params["action"] as string | undefined, params["tabId"] as string | undefined);
      case "browser_eval":
        return this.evaluate(params["expression"] as string);
      case "browser_search":
        return this.search(params["text"] as string);
      case "browser_wait":
        return this.wait(params["ms"] as number | undefined);
      case "ping":
        return { status: "ok", timestamp: Date.now() };
      case "shutdown":
        await this.shutdown();
        return { status: "shutdown" };
      default:
        throw new Error(`Unknown method: ${method}`);
    }
  }

  async navigate(url: string): Promise<{ url: string; title: string }> {
    const page = await this.getActivePage();
    await page.goto(url, { waitUntil: "domcontentloaded", timeout: 30000 });
    return { url: page.url(), title: await page.title() };
  }

  async navigateBack(): Promise<{ url: string; title: string }> {
    const page = await this.getActivePage();
    await page.goBack({ waitUntil: "domcontentloaded" });
    return { url: page.url(), title: await page.title() };
  }

  async snapshot(takeScreenshot?: boolean): Promise<SnapshotResult> {
    const page = await this.getActivePage();
    const accessibility = await page.accessibility.snapshot();
    const snapshotYaml = JSON.stringify(accessibility, null, 2);
    const result: SnapshotResult = {
      snapshot: snapshotYaml,
      url: page.url(),
      title: await page.title(),
    };
    if (takeScreenshot === true) {
      const buf = await page.screenshot({ type: "png" });
      result.screenshot = buf.toString("base64");
    }
    return result;
  }

  async takeScreenshot(): Promise<ScreenshotResult> {
    const page = await this.getActivePage();
    const buf = await page.screenshot({ type: "png", fullPage: false });
    const viewport = page.viewportSize();
    return {
      base64: buf.toString("base64"),
      width: viewport?.width ?? 1280,
      height: viewport?.height ?? 720,
    };
  }

  async click(ref?: string, selector?: string): Promise<{ clicked: string }> {
    const page = await this.getActivePage();
    const sel = selector ?? ref ?? "body";
    await page.click(sel, { timeout: 10000 });
    return { clicked: sel };
  }

  async clickXY(x: number, y: number): Promise<{ x: number; y: number }> {
    const page = await this.getActivePage();
    await page.mouse.click(x, y);
    return { x, y };
  }

  async fill(ref?: string, selector?: string, value?: string): Promise<{ filled: string }> {
    const page = await this.getActivePage();
    const sel = selector ?? ref ?? "input";
    await page.fill(sel, value ?? "");
    return { filled: sel };
  }

  async type(text: string): Promise<{ typed: number }> {
    const page = await this.getActivePage();
    await page.keyboard.type(text);
    return { typed: text.length };
  }

  async hover(ref?: string, selector?: string): Promise<{ hovered: string }> {
    const page = await this.getActivePage();
    const sel = selector ?? ref ?? "body";
    await page.hover(sel, { timeout: 10000 });
    return { hovered: sel };
  }

  async pressKey(key: string): Promise<{ key: string }> {
    const page = await this.getActivePage();
    await page.keyboard.press(key);
    return { key };
  }

  async select(ref?: string, selector?: string, value?: string): Promise<{ selected: string }> {
    const page = await this.getActivePage();
    const sel = selector ?? ref ?? "select";
    await page.selectOption(sel, value ?? "");
    return { selected: sel };
  }

  async scroll(direction?: string, amount?: number): Promise<{ scrolled: string }> {
    const page = await this.getActivePage();
    const px = amount ?? 300;
    const deltaY = direction === "up" ? -px : px;
    await page.mouse.wheel(0, deltaY);
    return { scrolled: `${direction ?? "down"} ${px}px` };
  }

  consoleMessages(): ConsoleEntry[] {
    if (this.activeTabId === null) return [];
    const tab = this.tabs.get(this.activeTabId);
    return tab?.consoleEntries ?? [];
  }

  networkRequests(): NetworkEntry[] {
    if (this.activeTabId === null) return [];
    const tab = this.tabs.get(this.activeTabId);
    return tab?.networkEntries ?? [];
  }

  async handleDialog(accept?: boolean, promptText?: string): Promise<{ handled: boolean }> {
    const page = await this.getActivePage();
    page.once("dialog", async (dialog) => {
      if (accept === false) {
        await dialog.dismiss();
      } else {
        await dialog.accept(promptText);
      }
    });
    return { handled: true };
  }

  async listTabs(action?: string, tabId?: string): Promise<TabInfo[] | TabInfo> {
    if (action === "new") {
      const context = await this.getOrCreateContext();
      const page = await context.newPage();
      const id = `tab-${++this.tabCounter}`;
      this.registerTab(id, page);
      this.activeTabId = id;
      return { id, url: page.url(), title: await page.title() };
    }

    if (action === "switch" && tabId !== undefined) {
      if (!this.tabs.has(tabId)) throw new Error(`Tab ${tabId} not found`);
      this.activeTabId = tabId;
      const tab = this.tabs.get(tabId)!;
      return { id: tabId, url: tab.page.url(), title: await tab.page.title() };
    }

    if (action === "close" && tabId !== undefined) {
      const tab = this.tabs.get(tabId);
      if (tab !== undefined) {
        await tab.page.close();
        this.tabs.delete(tabId);
        if (this.activeTabId === tabId) {
          const remaining = Array.from(this.tabs.keys());
          this.activeTabId = remaining[0] ?? null;
        }
      }
      return this.getTabList();
    }

    return this.getTabList();
  }

  private async getTabList(): Promise<TabInfo[]> {
    const list: TabInfo[] = [];
    for (const [id, tab] of this.tabs) {
      list.push({ id, url: tab.page.url(), title: await tab.page.title() });
    }
    return list;
  }

  async evaluate(expression: string): Promise<unknown> {
    const page = await this.getActivePage();
    return page.evaluate(expression);
  }

  async search(text: string): Promise<{ found: boolean; count: number }> {
    const page = await this.getActivePage();
    const content = await page.content();
    const regex = new RegExp(text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "gi");
    const matches = content.match(regex);
    return { found: matches !== null, count: matches?.length ?? 0 };
  }

  async wait(ms?: number): Promise<{ waited: number }> {
    const duration = ms ?? 1000;
    await new Promise((r) => setTimeout(r, duration));
    return { waited: duration };
  }

  async shutdown(): Promise<void> {
    for (const [, context] of this.contexts) {
      await context.close().catch(() => {});
    }
    this.contexts.clear();
    this.tabs.clear();
    if (this.browser !== null) {
      await this.browser.close().catch(() => {});
      this.browser = null;
    }
  }
}
