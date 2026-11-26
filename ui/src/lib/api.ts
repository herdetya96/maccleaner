import type {
  Disk, Info, Item, NodeResult, RecGroup, Status, Summary, TrashRequest, TrashResult,
} from "./types";

type Bridge = { postMessage(msg: unknown): Promise<string> };

/** Jembatan WKWebView ke Swift (desktop app). */
function bridge(): Bridge | null {
  const w = window as unknown as { webkit?: { messageHandlers?: { mc?: Bridge } } };
  return w.webkit?.messageHandlers?.mc ?? null;
}

export const isDesktop = (): boolean => bridge() !== null;

function token(): string {
  return document.querySelector<HTMLMetaElement>('meta[name="mc-token"]')?.content ?? "";
}

async function call<T>(method: "GET" | "POST", path: string, body?: unknown): Promise<T> {
  const b = bridge();
  if (b) {
    // Desktop: dijawab langsung oleh Swift tanpa server/jaringan.
    const raw = await b.postMessage({ method, path, body: body ?? null });
    const data = JSON.parse(raw) as T & { __error?: string };
    if (data && typeof data === "object" && "__error" in data && data.__error) {
      throw new Error(data.__error);
    }
    return data;
  }
  // Server Python (mode web / pengembangan).
  const res = await fetch(path, {
    method,
    headers: { "X-Token": token(), ...(body !== undefined ? { "Content-Type": "application/json" } : {}) },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error((data as { error?: string }).error || `HTTP ${res.status}`);
  return data as T;
}

const q = (path: string | null | undefined) => (path ? `?path=${encodeURIComponent(path)}` : "");

export const api = {
  info: () => call<Info>("GET", "/api/info"),
  disks: () => call<{ disks: Disk[] }>("GET", "/api/disks").then((r) => r.disks),
  status: () => call<Status>("GET", "/api/status"),
  scan: (path: string) => call<Status>("POST", "/api/scan", { path }),
  cancel: () => call<{ ok: boolean }>("POST", "/api/cancel", {}),
  node: (path?: string | null) => call<NodeResult>("GET", `/api/node${q(path)}`),
  summary: () => call<Summary>("GET", "/api/summary"),
  recommendations: () => call<{ groups: RecGroup[]; trash: number }>("GET", "/api/recommendations"),
  largeFiles: () => call<{ items: Item[] }>("GET", "/api/largefiles").then((r) => r.items),
  trash: (items: TrashRequest[]) =>
    call<TrashResult>("POST", "/api/trash", { items: items.map((i) => ({ path: i.path, contents: !!i.contents })) }),
  emptyTrash: () => call<{ ok: boolean; message: string }>("POST", "/api/empty-trash", {}),
  reveal: (path: string) => call<{ ok: boolean }>("POST", "/api/reveal", { path }),

  // Khusus desktop app.
  chooseFolder: () => call<{ path: string | null }>("POST", "/api/choose-folder", {}),
  openFullDiskAccess: () => call<{ ok: boolean }>("POST", "/api/open-fda", {}),
  copy: async (text: string) => {
    if (isDesktop()) return call<{ ok: boolean }>("POST", "/api/copy", { text });
    await navigator.clipboard?.writeText(text);
    return { ok: true };
  },
};
