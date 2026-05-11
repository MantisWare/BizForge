import { forgemap as forgemapApi } from '$api/client';
import type {
  ForgeMapDetection,
  ForgeMapScanResult,
  ForgeMapEntry,
} from '$api/types';

class ForgeMapStore {
  detection = $state<ForgeMapDetection | null>(null);
  scanResult = $state<ForgeMapScanResult | null>(null);
  entries = $state<ForgeMapEntry[]>([]);
  loading = $state(false);
  scanning = $state(false);
  error = $state<string | null>(null);

  fileCount = $derived(this.scanResult?.file_count ?? 0);
  languages = $derived(this.scanResult?.languages ?? []);
  totalExports = $derived(this.scanResult?.total_exports ?? 0);
  hasCodebase = $derived(this.detection?.has_codebase ?? false);
  detectedStack = $derived(this.detection?.detected_stack ?? []);

  async detect(projectId: string): Promise<ForgeMapDetection | null> {
    this.loading = true;
    this.error = null;

    try {
      const data = await forgemapApi.detect(projectId);
      this.detection = data.detection;
      return data.detection;
    } catch (err) {
      this.error = (err as Error).message;
      return null;
    } finally {
      this.loading = false;
    }
  }

  async scan(
    projectId: string,
    opts?: { write_headers?: boolean; session_id?: string },
  ): Promise<ForgeMapScanResult | null> {
    this.scanning = true;
    this.error = null;

    try {
      const data = await forgemapApi.scan(projectId, opts);
      this.scanResult = data.scan;
      return data.scan;
    } catch (err) {
      this.error = (err as Error).message;
      return null;
    } finally {
      this.scanning = false;
    }
  }

  async fetchIndex(projectId: string): Promise<ForgeMapEntry[]> {
    this.loading = true;
    this.error = null;

    try {
      const data = await forgemapApi.index(projectId);
      this.entries = data.entries;
      return data.entries;
    } catch (err) {
      this.error = (err as Error).message;
      return [];
    } finally {
      this.loading = false;
    }
  }

  reset(): void {
    this.detection = null;
    this.scanResult = null;
    this.entries = [];
    this.loading = false;
    this.scanning = false;
    this.error = null;
  }
}

export const forgemapStore = new ForgeMapStore();
