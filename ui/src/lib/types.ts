// Bentuk data API — sama persis untuk desktop app (Swift) dan server Python.

export type Safety = "aman" | "hati" | "periksa" | "jangan" | "unknown";

export interface RuleInfo {
  id: string | null;
  title: string;
  category: string;
  categoryLabel: string;
  safety: Safety;
  safetyLabel: string;
  why: string;
  effect: string;
  how: string;
  command: string;
  mode: "self" | "contents";
  deletable: boolean;
  inherited: boolean;
  partOf?: boolean;
}

export interface Item {
  name: string;
  path: string | null;
  display: string;
  size: number;
  files: number;
  isDir: boolean;
  mtime: number;
  denied?: boolean;
  pct: number;
  rule: RuleInfo;
  protected: boolean;
  other?: boolean;
}

export type DiskLevel = "aman" | "sedang" | "tinggi" | "kritis";

export interface Disk {
  name: string;
  mount: string;
  total: number;
  used: number;
  free: number;
  available?: number;
  purgeable?: number;
  percent: number;
  level: DiskLevel;
  message: string;
  fs: string;
  isRoot: boolean;
  scanPaths: { label: string; path: string }[];
}

export type ScanState = "idle" | "running" | "done" | "cancelled" | "error";

export interface Status {
  state: ScanState;
  error?: string;
  root?: string;
  display?: string;
  files: number;
  dirs: number;
  bytes: number;
  current: string;
  elapsed: number;
  denied: number;
  fraction: number;
  eta: number | null;
  estimate: "history" | "disk" | "tree";
}

export interface Insight {
  level: "aman" | "hati" | "info" | "sedang" | "tinggi" | "kritis" | "jangan" | "periksa";
  text: string;
}

export interface Summary {
  root: string;
  display: string;
  scanned: number;
  files: number;
  elapsed: number;
  categories: { id: string; label: string; size: number }[];
  disk: Disk | null;
  wholeDisk: boolean;
  unscanned: number;
  safeTotal: number;
  cautionTotal: number;
  denied: number;
  insights: Insight[];
}

export interface RecItem {
  path: string;
  display: string;
  size: number;
  files: number;
  mtime: number;
  isDir: boolean;
}

export interface RecGroup {
  id: string;
  rule: RuleInfo;
  kind: "trash" | "manual";
  total: number;
  items: RecItem[];
}

export interface NodeResult {
  node: Item;
  items: Item[];
  crumbs: { name: string; path: string }[];
}

export interface Info {
  version: string;
  home: string;
  platform: string;
  status: Status;
  /** true di desktop app (jembatan Swift). */
  desktop?: boolean;
  needsFullDiskAccess?: boolean;
}

export interface TrashRequest {
  path: string;
  display: string;
  size: number;
  safety: Safety;
  contents?: boolean;
}

export interface TrashResult {
  done: { path: string; display: string }[];
  errors: { path: string; display: string; error: string }[];
  freed: number;
  note: string;
}
