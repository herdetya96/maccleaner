import { ChartPieIcon, FilesIcon, FolderTreeIcon, ListChecksIcon } from "lucide-react";
import type React from "react";
import { type View, useApp } from "@/app-state";
import { ConfirmTrashDialog, EmptyTrashDialog, ScanDialog } from "@/components/dialogs";
import { SAFETY_HINT, SafetyBadge } from "@/components/shared";
import { Badge } from "@/components/ui/badge";
import { bytes } from "@/lib/format";
import { cn } from "@/lib/utils";
import { ExploreView } from "@/views/explore";
import { LargeFilesView } from "@/views/large-files";
import { OverviewView } from "@/views/overview";
import { RecommendationsView } from "@/views/recommendations";

const NAV: { id: View; label: string; icon: React.ComponentType<{ className?: string }> }[] = [
  { id: "overview", label: "Ringkasan", icon: ChartPieIcon },
  { id: "explore", label: "Analisis Folder", icon: FolderTreeIcon },
  { id: "recs", label: "Rekomendasi", icon: ListChecksIcon },
  { id: "large", label: "File Besar", icon: FilesIcon },
];

function Sidebar() {
  const { view, setView, hasResults, summary, info } = useApp();
  return (
    <aside className="app-chrome flex w-60 shrink-0 flex-col border-sidebar-border border-r bg-sidebar text-sidebar-foreground">
      <div className="flex items-center gap-2.5 px-4 pt-5 pb-4">
        <div className="flex size-8 items-center justify-center rounded-lg bg-primary text-primary-foreground shadow-xs">
          <svg aria-hidden="true" className="size-5" fill="none" viewBox="0 0 24 24">
            <rect height="12" rx="3" stroke="currentColor" strokeWidth="2" width="18" x="3" y="6" />
            <rect fill="currentColor" height="3" rx="1.5" width="8" x="6" y="12.5" />
          </svg>
        </div>
        <div className="leading-tight">
          <div className="font-semibold text-foreground text-sm">MacCleaner</div>
          <div className="text-muted-foreground text-xs">v{info?.version ?? ""}</div>
        </div>
      </div>
      <nav className="flex flex-col gap-0.5 px-2">
        {NAV.map(({ id, label, icon: Icon }) => {
          const disabled = id !== "overview" && !hasResults;
          const active = view === id;
          return (
            <button
              className={cn(
                "flex h-8 items-center gap-2.5 rounded-md px-2.5 text-left text-sm transition-colors",
                active
                  ? "bg-sidebar-accent font-medium text-sidebar-accent-foreground"
                  : "hover:bg-sidebar-accent/60 hover:text-sidebar-accent-foreground",
                disabled && "pointer-events-none opacity-40",
              )}
              disabled={disabled}
              key={id}
              onClick={() => setView(id)}
              type="button"
            >
              <Icon className="size-4 opacity-80" />
              <span className="flex-1">{label}</span>
              {id === "recs" && summary && summary.safeTotal > 0 && (
                <Badge size="sm" variant="success">
                  {bytes(summary.safeTotal)}
                </Badge>
              )}
            </button>
          );
        })}
      </nav>
      <div className="mt-auto flex flex-col gap-2.5 p-4">
        <div className="font-medium text-muted-foreground text-xs uppercase tracking-wide">Arti label</div>
        {(["aman", "hati", "periksa", "jangan"] as const).map((s) => (
          <div className="flex flex-col items-start gap-1" key={s}>
            <SafetyBadge safety={s} />
            <span className="text-muted-foreground text-xs leading-snug">{SAFETY_HINT[s]}</span>
          </div>
        ))}
      </div>
    </aside>
  );
}

export default function App() {
  const { view } = useApp();
  return (
    <div className="flex h-full overflow-hidden">
      <Sidebar />
      <main className="min-w-0 flex-1 overflow-y-auto">
        {view === "overview" && <OverviewView />}
        {view === "explore" && <ExploreView />}
        {view === "recs" && <RecommendationsView />}
        {view === "large" && <LargeFilesView />}
      </main>
      <ScanDialog />
      <ConfirmTrashDialog />
      <EmptyTrashDialog />
    </div>
  );
}
