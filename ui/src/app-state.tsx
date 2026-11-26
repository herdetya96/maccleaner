import type React from "react";
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import { toastManager } from "@/components/ui/toast";
import { api, isDesktop } from "@/lib/api";
import { bytes } from "@/lib/format";
import type { Disk, Info, RecGroup, Status, Summary, TrashRequest } from "@/lib/types";

export type View = "overview" | "explore" | "recs" | "large";

interface AppState {
  info: Info | null;
  desktop: boolean;
  disks: Disk[];
  status: Status | null;
  smoothEta: number | null;
  summary: Summary | null;
  groups: RecGroup[];
  trashSize: number;
  hasResults: boolean;
  view: View;
  setView: (v: View) => void;
  /** Folder yang sedang dibuka di Analisis Folder (null = akar pindaian). */
  folder: string | null;
  openFolder: (path: string | null, select?: string | null) => void;
  focusPath: string | null;
  /** Bertambah setiap kali hasil pindai berubah, untuk memuat ulang tampilan. */
  revision: number;
  startScan: (path: string) => Promise<void>;
  chooseAndScan: () => Promise<void>;
  cancelScan: () => void;
  refreshDisks: () => Promise<void>;
  askTrash: (items: TrashRequest[]) => void;
  pendingTrash: TrashRequest[] | null;
  closeTrash: () => void;
  confirmTrash: () => Promise<void>;
  emptyTrashOpen: boolean;
  setEmptyTrashOpen: (v: boolean) => void;
  confirmEmptyTrash: () => Promise<void>;
  reveal: (path: string) => void;
  copy: (text: string) => void;
}

const Ctx = createContext<AppState | null>(null);

export function useApp(): AppState {
  const v = useContext(Ctx);
  if (!v) throw new Error("useApp di luar AppProvider");
  return v;
}

export function notify(title: string, description?: string, type: "success" | "error" | "info" = "success") {
  toastManager.add({ title, description, type, timeout: type === "error" ? 9000 : 5000 });
}

export function AppProvider({ children }: { children: React.ReactNode }) {
  const [info, setInfo] = useState<Info | null>(null);
  const [disks, setDisks] = useState<Disk[]>([]);
  const [status, setStatus] = useState<Status | null>(null);
  const [smoothEta, setSmoothEta] = useState<number | null>(null);
  const [summary, setSummary] = useState<Summary | null>(null);
  const [groups, setGroups] = useState<RecGroup[]>([]);
  const [trashSize, setTrashSize] = useState(0);
  const [view, setView] = useState<View>("overview");
  const [folder, setFolder] = useState<string | null>(null);
  const [focusPath, setFocusPath] = useState<string | null>(null);
  const [revision, setRevision] = useState(0);
  const [pendingTrash, setPendingTrash] = useState<TrashRequest[] | null>(null);
  const [emptyTrashOpen, setEmptyTrashOpen] = useState(false);
  const pollRef = useRef<number | null>(null);
  const etaRef = useRef<number | null>(null);

  const hasResults = !!summary && status?.state !== "running";

  const refreshDisks = useCallback(async () => {
    try {
      setDisks(await api.disks());
    } catch (e) {
      notify("Gagal membaca disk", String((e as Error).message), "error");
    }
  }, []);

  const loadResults = useCallback(async () => {
    const [s, r] = await Promise.all([api.summary(), api.recommendations()]);
    setSummary(s);
    setGroups(r.groups);
    setTrashSize(r.trash);
    setRevision((x) => x + 1);
    refreshDisks();
  }, [refreshDisks]);

  const stopPolling = () => {
    if (pollRef.current !== null) window.clearInterval(pollRef.current);
    pollRef.current = null;
  };

  const poll = useCallback(async () => {
    let s: Status;
    try {
      s = await api.status();
    } catch {
      return;
    }
    // Haluskan sisa waktu agar angkanya tidak melompat-lompat.
    if (s.eta === null || s.eta === undefined) etaRef.current = null;
    else etaRef.current = etaRef.current === null ? s.eta : etaRef.current * 0.8 + s.eta * 0.2;
    setSmoothEta(etaRef.current);
    setStatus(s);
    if (s.state !== "running") {
      stopPolling();
      if (s.state === "error") notify("Pemindaian gagal", s.error, "error");
      if (s.state === "cancelled") notify("Pemindaian dibatalkan", "Hasil sebagian ditampilkan.", "info");
      if (s.state === "done" || s.state === "cancelled") {
        setFolder(null);
        setFocusPath(null);
        await loadResults();
      }
    }
  }, [loadResults]);

  const startPolling = useCallback(() => {
    stopPolling();
    etaRef.current = null;
    setSmoothEta(null);
    pollRef.current = window.setInterval(poll, 300);
    poll();
  }, [poll]);

  const startScan = useCallback(
    async (path: string) => {
      try {
        setStatus(await api.scan(path));
        startPolling();
      } catch (e) {
        notify("Tidak bisa memindai", String((e as Error).message), "error");
      }
    },
    [startPolling],
  );

  const chooseAndScan = useCallback(async () => {
    const r = await api.chooseFolder();
    if (r.path) await startScan(r.path);
  }, [startScan]);

  const cancelScan = useCallback(() => {
    api.cancel().catch(() => {});
  }, []);

  const openFolder = useCallback((path: string | null, select: string | null = null) => {
    setFolder(path);
    setFocusPath(select);
    setView("explore");
  }, []);

  const confirmTrash = useCallback(async () => {
    const items = pendingTrash ?? [];
    setPendingTrash(null);
    if (!items.length) return;
    try {
      const res = await api.trash(items);
      if (res.done.length) {
        notify(`${res.done.length} item dipindah ke Sampah (${bytes(res.freed)})`, res.note, "success");
      }
      if (res.errors.length) {
        notify(
          `${res.errors.length} item gagal dibuang`,
          res.errors.slice(0, 3).map((e) => `${e.display}: ${e.error}`).join("\n"),
          "error",
        );
      }
    } catch (e) {
      notify("Gagal membuang", String((e as Error).message), "error");
    }
    await loadResults();
  }, [pendingTrash, loadResults]);

  const confirmEmptyTrash = useCallback(async () => {
    setEmptyTrashOpen(false);
    try {
      const r = await api.emptyTrash();
      notify(r.message, undefined, r.ok ? "success" : "error");
    } catch (e) {
      notify("Gagal mengosongkan Sampah", String((e as Error).message), "error");
    }
    await loadResults();
  }, [loadResults]);

  // Muat awal + lanjutkan pemindaian yang sedang berjalan (mis. setelah muat ulang).
  useEffect(() => {
    (async () => {
      await refreshDisks();
      try {
        const i = await api.info();
        setInfo(i);
        setStatus(i.status);
        if (i.status.state === "running") startPolling();
        else if (i.status.state === "done" || i.status.state === "cancelled") await loadResults();
      } catch (e) {
        notify("Tidak terhubung ke MacCleaner", String((e as Error).message), "error");
      }
    })();
    return stopPolling;
  }, [refreshDisks, loadResults, startPolling]);

  // Perintah dari menu aplikasi (desktop): window.__mc.scan("/path"), window.__mc.choose()
  useEffect(() => {
    (window as unknown as { __mc: unknown }).__mc = {
      scan: (p: string) => startScan(p),
      choose: () => chooseAndScan(),
      show: (v: View) => setView(v),
    };
  }, [startScan, chooseAndScan]);

  const value = useMemo<AppState>(
    () => ({
      info, desktop: isDesktop(), disks, status, smoothEta, summary, groups, trashSize, hasResults,
      view, setView, folder, openFolder, focusPath, revision,
      startScan, chooseAndScan, cancelScan, refreshDisks,
      askTrash: (items) => setPendingTrash(items.length ? items : null),
      pendingTrash, closeTrash: () => setPendingTrash(null), confirmTrash,
      emptyTrashOpen, setEmptyTrashOpen, confirmEmptyTrash,
      reveal: (p) => { api.reveal(p).catch((e) => notify("Gagal membuka Finder", String(e.message), "error")); },
      copy: (t) => { api.copy(t).then(() => notify("Perintah disalin")).catch(() => {}); },
    }),
    [info, disks, status, smoothEta, summary, groups, trashSize, hasResults, view, folder, openFolder,
      focusPath, revision, startScan, chooseAndScan, cancelScan, refreshDisks, pendingTrash, confirmTrash,
      emptyTrashOpen, confirmEmptyTrash],
  );

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}
