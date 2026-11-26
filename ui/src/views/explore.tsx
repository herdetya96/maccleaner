import type React from "react";
import {
  ArrowUpIcon, EllipsisIcon, FileIcon, FolderIcon, FolderOpenIcon, LockIcon, SquareArrowOutUpRightIcon, Trash2Icon,
  TriangleAlertIcon,
} from "lucide-react";
import { useEffect, useState } from "react";
import { notify, useApp } from "@/app-state";
import { Explanation, SafetyBadge } from "@/components/shared";
import { Alert, AlertDescription } from "@/components/ui/alert";
import {
  Breadcrumb, BreadcrumbItem, BreadcrumbLink, BreadcrumbList, BreadcrumbPage, BreadcrumbSeparator,
} from "@/components/ui/breadcrumb";
import { Button } from "@/components/ui/button";
import { Card, CardPanel } from "@/components/ui/card";
import { NoResults } from "@/views/no-results";
import { api } from "@/lib/api";
import { ago, bytes, count } from "@/lib/format";
import type { Item, NodeResult } from "@/lib/types";
import { cn } from "@/lib/utils";

function canTrash(it: Item) {
  return !it.other && !it.protected && it.rule.deletable && it.rule.safety !== "jangan";
}
function cleansContents(it: Item) {
  return it.isDir && !it.rule.inherited && !!it.rule.id && it.rule.mode === "contents";
}

function Row({
  item, max, selected, onSelect, onOpen,
}: { item: Item; max: number; selected: boolean; onSelect: () => void; onOpen: () => void }) {
  const Icon = item.other ? EllipsisIcon : item.isDir ? (item.denied ? LockIcon : FolderIcon) : FileIcon;
  return (
    <div
      className={cn(
        "grid grid-cols-[20px_minmax(0,1fr)_120px_80px_118px] items-center gap-3 rounded-lg px-3 py-2 text-sm",
        item.other ? "text-muted-foreground" : "hover:bg-accent",
        selected && "bg-accent",
      )}
      onClick={item.other ? undefined : onSelect}
      onDoubleClick={item.other || !item.isDir ? undefined : onOpen}
      onKeyDown={(e) => {
        if (e.key === "Enter" && item.isDir && !item.other) onOpen();
      }}
      role={item.other ? undefined : "button"}
      tabIndex={item.other ? undefined : 0}
    >
      <Icon className={cn("size-4", item.isDir && !item.other ? "text-info" : "text-muted-foreground")} />
      <div className="flex min-w-0 items-baseline gap-2">
        <span className="truncate">{item.name}</span>
        {item.isDir && item.files > 0 && (
          <span className="shrink-0 text-muted-foreground text-xs">{count(item.files)} file</span>
        )}
      </div>
      <div className="h-1.5 overflow-hidden rounded-full bg-input">
        <div className="h-full rounded-full bg-info" style={{ width: `${Math.max(0.5, (item.size / max) * 100)}%` }} />
      </div>
      <span className="text-right font-medium tabular-nums">{bytes(item.size)}</span>
      <span className="flex justify-end">{!item.other && <SafetyBadge safety={item.rule.safety} />}</span>
    </div>
  );
}

function Detail({ item, isCurrent }: { item: Item; isCurrent: boolean }) {
  const { openFolder, reveal, askTrash } = useApp();
  const r = item.rule;
  let action: React.ReactNode;
  if (item.protected) {
    action = (
      <Alert>
        <LockIcon />
        <AlertDescription>Folder penting — dilindungi dari penghapusan oleh aplikasi ini.</AlertDescription>
      </Alert>
    );
  } else if (r.safety === "jangan") {
    action = (
      <Alert variant="error">
        <TriangleAlertIcon />
        <AlertDescription className="text-foreground">Jangan dihapus manual. {r.how}</AlertDescription>
      </Alert>
    );
  } else if (r.partOf) {
    action = (
      <Alert variant="warning">
        <TriangleAlertIcon />
        <AlertDescription className="text-foreground">
          Ini bagian dalam dari "{r.title}". Menghapus satu file di dalamnya bisa merusak keseluruhannya — buang
          seluruh foldernya saja.
        </AlertDescription>
      </Alert>
    );
  } else if (!r.deletable) {
    action = (
      <Alert variant="warning">
        <TriangleAlertIcon />
        <AlertDescription className="text-foreground">
          Bersihkan lewat caranya sendiri (lihat di atas), bukan dengan menghapus file.
        </AlertDescription>
      </Alert>
    );
  } else if (item.path) {
    const contents = cleansContents(item);
    action = (
      <Button
        className="w-full"
        onClick={() =>
          askTrash([
            { path: item.path as string, display: item.display, size: item.size, safety: r.safety, contents },
          ])
        }
        size="lg"
        variant="destructive"
      >
        <Trash2Icon />
        {contents ? "Kosongkan isinya" : "Buang ke Sampah"}
      </Button>
    );
  }
  return (
    <Card className="sticky top-6">
      <CardPanel className="flex flex-col gap-4 pt-6">
        <div className="flex flex-col gap-1">
          <span className="text-muted-foreground text-xs">{isCurrent ? "Folder ini" : item.isDir ? "Folder" : "File"}</span>
          <h2 className="selectable break-words font-semibold text-lg leading-tight">{item.name}</h2>
          <span className="selectable break-all font-mono text-muted-foreground text-xs">{item.display}</span>
        </div>
        <div className="flex items-center justify-between gap-3">
          <span className="font-semibold text-3xl tabular-nums tracking-tight">{bytes(item.size)}</span>
          <SafetyBadge safety={r.safety} />
        </div>
        <span className="-mt-2 text-muted-foreground text-xs">
          {item.isDir ? `${count(item.files)} file · diubah ${ago(item.mtime)}` : `Diubah ${ago(item.mtime)}`}
        </span>
        {item.denied && (
          <Alert variant="warning">
            <LockIcon />
            <AlertDescription className="text-foreground">
              Isi folder tidak bisa dibaca (izin ditolak). Ukuran sebenarnya bisa lebih besar.
            </AlertDescription>
          </Alert>
        )}
        <Explanation rule={r} />
        <div className="flex flex-wrap gap-2">
          {item.isDir && !isCurrent && item.path && (
            <Button onClick={() => openFolder(item.path)}>
              <FolderOpenIcon />
              Buka folder
            </Button>
          )}
          {item.path && (
            <Button onClick={() => reveal(item.path as string)} variant="outline">
              <SquareArrowOutUpRightIcon />
              Tampilkan di Finder
            </Button>
          )}
        </div>
        {action}
      </CardPanel>
    </Card>
  );
}

export function ExploreView() {
  const { hasResults, folder, openFolder, focusPath, revision } = useApp();
  const [data, setData] = useState<NodeResult | null>(null);
  const [selected, setSelected] = useState<string | null>(null);

  useEffect(() => {
    if (!hasResults) return;
    let alive = true;
    api
      .node(folder)
      .then((d) => {
        if (!alive) return;
        setData(d);
        setSelected(focusPath && d.items.some((i) => i.path === focusPath) ? focusPath : null);
      })
      .catch((e) => {
        // Folder sudah dibuang → kembali ke akar.
        if (folder) openFolder(null);
        else notify("Gagal memuat folder", String(e.message), "error");
      });
    return () => {
      alive = false;
    };
  }, [hasResults, folder, focusPath, revision, openFolder]);

  if (!hasResults) return <NoResults />;
  if (!data) return null;

  const max = data.items[0]?.size || 1;
  const current = data.items.find((i) => i.path === selected) ?? null;
  const crumbs = data.crumbs;

  return (
    <div className="flex flex-col gap-5 p-8">
      <div className="flex items-center gap-3">
        <Button
          aria-label="Naik satu folder"
          disabled={crumbs.length < 2}
          onClick={() => openFolder(crumbs[crumbs.length - 2]?.path ?? null)}
          size="icon"
          variant="outline"
        >
          <ArrowUpIcon />
        </Button>
        <Breadcrumb className="min-w-0 flex-1">
          <BreadcrumbList>
            {crumbs.map((c, i) => (
              <span className="contents" key={c.path}>
                {i > 0 && <BreadcrumbSeparator />}
                <BreadcrumbItem>
                  {i === crumbs.length - 1 ? (
                    <BreadcrumbPage>{c.name}</BreadcrumbPage>
                  ) : (
                    <BreadcrumbLink render={<button onClick={() => openFolder(c.path)} type="button" />}>
                      {c.name}
                    </BreadcrumbLink>
                  )}
                </BreadcrumbItem>
              </span>
            ))}
          </BreadcrumbList>
        </Breadcrumb>
        <span className="font-semibold tabular-nums">{bytes(data.node.size)}</span>
      </div>
      <div className="grid items-start gap-5 xl:grid-cols-[minmax(0,1fr)_360px]">
        <Card className="app-chrome">
          <CardPanel className="p-1.5">
            {data.items.length === 0 && (
              <div className="py-12 text-center text-muted-foreground text-sm">Folder ini kosong.</div>
            )}
            {data.items.map((it) => (
              <Row
                item={it}
                key={(it.other ? "other:" : "") + (it.path ?? it.name)}
                max={max}
                onOpen={() => openFolder(it.path)}
                onSelect={() => setSelected(it.path)}
                selected={!!it.path && it.path === selected}
              />
            ))}
          </CardPanel>
        </Card>
        <Detail isCurrent={!current} item={current ?? data.node} />
      </div>
      <p className="text-muted-foreground text-xs">Klik untuk melihat penjelasan, klik dua kali untuk membuka folder.</p>
    </div>
  );
}

export { canTrash };
