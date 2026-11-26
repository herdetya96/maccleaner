/** Ukuran dalam satuan desimal (1 GB = 1000³ byte), sama seperti Finder. */
export function bytes(value: number): string {
  let n = Number(value) || 0;
  const units = ["B", "KB", "MB", "GB", "TB"];
  let i = 0;
  while (Math.abs(n) >= 999.5 && i < units.length - 1) {
    n /= 1000;
    i++;
  }
  if (i === 0) return `${n} B`;
  return `${n.toFixed(n >= 100 ? 0 : 1).replace(".", ",")} ${units[i]}`;
}

export const count = (n: number): string => (n || 0).toLocaleString("id-ID");

/** 45 dtk · 3 mnt 12 dtk · 1 jam 5 mnt */
export function duration(sec: number): string {
  const s = Math.max(0, Math.round(sec || 0));
  if (s < 60) return `${s} dtk`;
  if (s < 3600) {
    const m = Math.floor(s / 60);
    const r = s % 60;
    return r ? `${m} mnt ${r} dtk` : `${m} mnt`;
  }
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  return m ? `${h} jam ${m} mnt` : `${h} jam`;
}

/** Sisa waktu dalam bahasa sehari-hari. */
export function eta(sec: number | null | undefined): string {
  if (sec === null || sec === undefined) return "Memperkirakan sisa waktu…";
  if (sec < 10) return "Hampir selesai…";
  if (sec < 60) return "Kurang dari 1 menit lagi";
  if (sec < 3600) return `Sekitar ${Math.max(1, Math.round(sec / 60))} menit lagi`;
  const total = Math.round(sec / 60);
  const h = Math.floor(total / 60);
  const m = total % 60;
  return m ? `Sekitar ${h} jam ${m} menit lagi` : `Sekitar ${h} jam lagi`;
}

const rtf = new Intl.RelativeTimeFormat("id", { numeric: "auto" });

/** "3 bulan yang lalu" */
export function ago(ts: number): string {
  if (!ts) return "";
  const s = Date.now() / 1000 - ts;
  const steps: [number, Intl.RelativeTimeFormatUnit, number][] = [
    [60, "second", 1],
    [3600, "minute", 60],
    [86400, "hour", 3600],
    [2592000, "day", 86400],
    [31536000, "month", 2592000],
    [Number.POSITIVE_INFINITY, "year", 31536000],
  ];
  for (const [limit, unit, div] of steps) {
    if (s < limit) return rtf.format(-Math.round(s / div), unit);
  }
  return "";
}
