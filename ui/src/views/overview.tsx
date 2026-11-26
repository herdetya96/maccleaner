import {
  CircleAlertIcon, CircleCheckIcon, FolderSearchIcon, InfoIcon, RefreshCwIcon, ShieldAlertIcon, TriangleAlertIcon,
} from "lucide-react";
import { useApp } from "@/app-state";
import { CATEGORY_COLORS, PageHeader } from "@/components/shared";
import { Alert, AlertAction, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardAction, CardDescription, CardFooter, CardHeader, CardPanel, CardTitle } from "@/components/ui/card";
import { Meter, MeterIndicator, MeterTrack } from "@/components/ui/meter";
import { api } from "@/lib/api";
import { bytes, count, duration } from "@/lib/format";
import type { Disk, Insight, Summary } from "@/lib/types";
import { cn } from "@/lib/utils";

const LEVEL_BAR: Record<Disk["level"], string> = {
  aman: "bg-success",
  sedang: "bg-warning",
  tinggi: "bg-warning",
  kritis: "bg-destructive",
};

function DiskCard({ disk }: { disk: Disk }) {
  const { startScan } = useApp();
  const alarming = disk.level === "tinggi" || disk.level === "kritis";
  return (
    <Card>
      <CardHeader>
        <CardTitle>{disk.name}</CardTitle>
        <CardDescription>
          {disk.mount}
          {disk.fs ? ` · ${disk.fs}` : ""}
        </CardDescription>
        <CardAction>
          <span
            className={cn(
              "font-semibold text-3xl tabular-nums tracking-tight",
              disk.level === "kritis" && "text-destructive-foreground",
              disk.level === "tinggi" && "text-warning-foreground",
            )}
          >
            {Math.round(disk.percent)}%
          </span>
        </CardAction>
      </CardHeader>
      <CardPanel className="flex flex-col gap-3">
        <Meter aria-label={`Pemakaian ${disk.name}`} value={Math.min(100, disk.percent)}>
          <MeterTrack className="h-2.5 rounded-full">
            <MeterIndicator className={cn("rounded-full", LEVEL_BAR[disk.level])} />
          </MeterTrack>
        </Meter>
        <div className="flex justify-between text-muted-foreground text-xs tabular-nums">
          <span>Terpakai {bytes(disk.used)}</span>
          <span>
            Tersedia {bytes(disk.available ?? disk.free)} dari {bytes(disk.total)}
          </span>
        </div>
        {(disk.purgeable ?? 0) > 1e9 && (
          <div className="text-muted-foreground text-xs">
            Termasuk {bytes(disk.purgeable ?? 0)} yang bisa dibersihkan macOS sendiri (purgeable).
          </div>
        )}
        <Alert variant={disk.level === "kritis" ? "error" : alarming ? "warning" : "default"}>
          {alarming ? <TriangleAlertIcon /> : <InfoIcon />}
          <AlertDescription className={cn(alarming && "text-foreground")}>{disk.message}</AlertDescription>
        </Alert>
      </CardPanel>
      <CardFooter className="flex flex-wrap gap-2">
        {disk.scanPaths.map((sp, i) => (
          <Button key={sp.path} onClick={() => startScan(sp.path)} variant={i === 0 ? "default" : "outline"}>
            Pindai {sp.label.charAt(0).toLowerCase() + sp.label.slice(1)}
          </Button>
        ))}
      </CardFooter>
    </Card>
  );
}

function Donut({ slices }: { slices: { id: string; label: string; size: number }[] }) {
  const total = slices.reduce((a, s) => a + s.size, 0) || 1;
  const r = 46;
  const c = 2 * Math.PI * r;
  let offset = 0;
  return (
    <svg aria-label="Pemakaian per kategori" className="size-52 shrink-0" role="img" viewBox="0 0 120 120">
      <circle className="stroke-muted" cx="60" cy="60" fill="none" r={r} strokeWidth="16" />
      {slices.map((s) => {
        const len = (s.size / total) * c;
        const el = (
          <circle
            cx="60"
            cy="60"
            fill="none"
            key={s.id}
            r={r}
            stroke={CATEGORY_COLORS[s.id] ?? "#a3a3a3"}
            strokeDasharray={`${Math.max(0, len - 0.8)} ${c}`}
            strokeDashoffset={-offset}
            strokeWidth="16"
            transform="rotate(-90 60 60)"
          >
            <title>
              {s.label}: {bytes(s.size)}
            </title>
          </circle>
        );
        offset += len;
        return el;
      })}
      <text className="fill-foreground font-semibold" fontSize="13" textAnchor="middle" x="60" y="58">
        {bytes(total)}
      </text>
      <text className="fill-muted-foreground" fontSize="7" textAnchor="middle" x="60" y="71">
        total
      </text>
    </svg>
  );
}

function WhyFull({ summary }: { summary: Summary }) {
  const all = [...summary.categories];
  if (summary.wholeDisk && summary.unscanned > 0) {
    all.push({ id: "unscanned", label: "Data sistem / tak terbaca", size: summary.unscanned });
  }
  const total = all.reduce((a, s) => a + s.size, 0) || 1;
  // Kategori kecil digabung ke "Lainnya" (satu entri saja, agar key unik).
  const shown: typeof all = [];
  let rest = 0;
  all.forEach((s, i) => {
    if (s.id !== "other" && i < 9 && s.size / total > 0.004) shown.push(s);
    else rest += s.size;
  });
  if (rest > 0) shown.push({ id: "other", label: "Lainnya", size: rest });
  return (
    <Card>
      <CardHeader>
        <CardTitle>Kenapa penuh?</CardTitle>
        <CardDescription>
          {summary.display} · {bytes(summary.scanned)} dalam {count(summary.files)} file · selesai dalam{" "}
          {duration(summary.elapsed)}
        </CardDescription>
      </CardHeader>
      <CardPanel className="flex flex-wrap items-center gap-6">
        <Donut slices={shown} />
        <ul className="flex min-w-56 flex-1 flex-col gap-2">
          {shown.map((s) => (
            <li className="flex items-center gap-2.5 text-sm" key={s.id}>
              <span className="size-3 shrink-0 rounded-sm" style={{ background: CATEGORY_COLORS[s.id] ?? "#a3a3a3" }} />
              <span className="flex-1">{s.label}</span>
              <span className="text-muted-foreground tabular-nums">
                {bytes(s.size)} · {Math.round((s.size / total) * 100)}%
              </span>
            </li>
          ))}
        </ul>
      </CardPanel>
    </Card>
  );
}

const INSIGHT_VARIANT: Record<Insight["level"], "success" | "warning" | "error" | "info"> = {
  aman: "success",
  hati: "warning",
  sedang: "warning",
  tinggi: "warning",
  kritis: "error",
  jangan: "error",
  periksa: "info",
  info: "info",
};
const INSIGHT_ICON = { success: CircleCheckIcon, warning: TriangleAlertIcon, error: CircleAlertIcon, info: InfoIcon };

function Findings({ summary }: { summary: Summary }) {
  const { setView } = useApp();
  return (
    <Card>
      <CardHeader>
        <CardTitle>Temuan</CardTitle>
        <CardDescription>Apa yang memenuhi disk, dan apa yang bisa dibersihkan.</CardDescription>
      </CardHeader>
      <CardPanel className="flex flex-col gap-2">
        {summary.insights.map((ins) => {
          const v = INSIGHT_VARIANT[ins.level] ?? "info";
          const Icon = INSIGHT_ICON[v];
          return (
            <Alert key={ins.text} variant={v}>
              <Icon />
              <AlertDescription className="text-foreground">{ins.text}</AlertDescription>
            </Alert>
          );
        })}
        <div className="mt-2 grid grid-cols-2 gap-3">
          <div className="rounded-xl border bg-success/4 p-3">
            <div className="font-semibold text-success-foreground text-xl tabular-nums">{bytes(summary.safeTotal)}</div>
            <div className="text-muted-foreground text-xs">aman dikosongkan</div>
          </div>
          <div className="rounded-xl border bg-warning/4 p-3">
            <div className="font-semibold text-warning-foreground text-xl tabular-nums">
              {bytes(summary.cautionTotal)}
            </div>
            <div className="text-muted-foreground text-xs">perlu dipertimbangkan</div>
          </div>
        </div>
      </CardPanel>
      <CardFooter className="flex flex-wrap gap-2">
        <Button onClick={() => setView("recs")}>Lihat rekomendasi</Button>
        <Button onClick={() => setView("explore")} variant="outline">
          Telusuri folder
        </Button>
      </CardFooter>
    </Card>
  );
}

export function OverviewView() {
  const { disks, summary, refreshDisks, desktop, chooseAndScan, info } = useApp();
  return (
    <div className="mx-auto flex max-w-6xl flex-col gap-6 p-8">
      <PageHeader
        actions={
          <>
            {desktop && (
              <Button onClick={chooseAndScan} variant="outline">
                <FolderSearchIcon />
                Pindai folder lain…
              </Button>
            )}
            <Button aria-label="Muat ulang" onClick={refreshDisks} size="icon" variant="outline">
              <RefreshCwIcon />
            </Button>
          </>
        }
        description="Lihat disk mana yang penuh, lalu pindai untuk tahu penyebabnya."
        title="Ringkasan Disk"
      />

      {info?.needsFullDiskAccess && (
        <Alert variant="warning">
          <ShieldAlertIcon />
          <AlertTitle>Akses Disk Penuh belum diberikan</AlertTitle>
          <AlertDescription>
            Sebagian folder (Mail, Pesan, Safari) tidak bisa dihitung sehingga hasil pindai kurang lengkap.
          </AlertDescription>
          <AlertAction>
            <Button onClick={() => api.openFullDiskAccess()} size="sm" variant="outline">
              Buka Pengaturan
            </Button>
          </AlertAction>
        </Alert>
      )}

      <div className="grid grid-cols-[repeat(auto-fill,minmax(320px,1fr))] gap-4">
        {disks.map((d) => (
          <DiskCard disk={d} key={d.mount} />
        ))}
      </div>

      {summary && (
        <div className="grid gap-4 lg:grid-cols-2">
          <WhyFull summary={summary} />
          <Findings summary={summary} />
        </div>
      )}
    </div>
  );
}
