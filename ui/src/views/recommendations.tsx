import type React from "react";
import { ChevronRightIcon, SearchIcon, SquareArrowOutUpRightIcon, Trash2Icon } from "lucide-react";
import { useMemo, useState } from "react";
import { useApp } from "@/app-state";
import { CommandBox, PageHeader, SafetyBadge } from "@/components/shared";
import { Alert, AlertAction, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import { Collapsible, CollapsiblePanel, CollapsibleTrigger } from "@/components/ui/collapsible";
import { Tooltip, TooltipPopup, TooltipTrigger } from "@/components/ui/tooltip";
import { NoResults } from "@/views/no-results";
import { ago, bytes } from "@/lib/format";
import type { RecGroup, TrashRequest } from "@/lib/types";
import { cn } from "@/lib/utils";

function IconAction({ label, onClick, children }: { label: string; onClick: () => void; children: React.ReactNode }) {
  return (
    <Tooltip>
      <TooltipTrigger render={<Button aria-label={label} onClick={onClick} size="icon-xs" variant="ghost" />}>
        {children}
      </TooltipTrigger>
      <TooltipPopup>{label}</TooltipPopup>
    </Tooltip>
  );
}

function GroupCard({
  group, picked, setPicked,
}: { group: RecGroup; picked: Set<string>; setPicked: (fn: (s: Set<string>) => Set<string>) => void }) {
  const { reveal, openFolder } = useApp();
  const r = group.rule;
  const selectable = group.kind === "trash";
  const n = group.items.filter((i) => picked.has(i.path)).length;
  const all = n > 0 && n === group.items.length;
  const some = n > 0 && !all;

  const setAll = (on: boolean) =>
    setPicked((s) => {
      const next = new Set(s);
      for (const i of group.items) on ? next.add(i.path) : next.delete(i.path);
      return next;
    });
  const toggle = (path: string, on: boolean) =>
    setPicked((s) => {
      const next = new Set(s);
      on ? next.add(path) : next.delete(path);
      return next;
    });

  return (
    <Card className="overflow-hidden">
      <Collapsible>
        <div className="flex items-center gap-3 px-4 py-3.5">
          {selectable && (
            <Checkbox
              aria-label={`Pilih semua ${r.title}`}
              checked={all}
              indeterminate={some}
              onCheckedChange={(v) => setAll(!!v)}
            />
          )}
          <CollapsibleTrigger className="group flex min-w-0 flex-1 items-center gap-3 text-left outline-none">
            <div className="flex min-w-0 flex-1 flex-col gap-1">
              <div className="flex flex-wrap items-center gap-2">
                <span className="font-medium">{r.title}</span>
                <SafetyBadge safety={r.safety} />
                {some && <span className="text-muted-foreground text-xs">sebagian dipilih</span>}
              </div>
              <p className="line-clamp-2 text-muted-foreground text-sm">{r.why}</p>
            </div>
            <div className="shrink-0 text-right">
              <div className="font-semibold tabular-nums">{bytes(group.total)}</div>
              <div className="text-muted-foreground text-xs">{group.items.length} lokasi</div>
            </div>
            <ChevronRightIcon className="size-4 shrink-0 text-muted-foreground transition-transform group-data-[panel-open]:rotate-90" />
          </CollapsibleTrigger>
        </div>
        <CollapsiblePanel>
          <div className="flex flex-col gap-3 border-t bg-muted/40 px-4 py-4">
            <div className="grid gap-4 text-sm sm:grid-cols-2">
              {r.effect && (
                <div>
                  <div className="mb-0.5 font-medium text-muted-foreground text-xs uppercase tracking-wide">Kalau dihapus</div>
                  <div className="selectable">{r.effect}</div>
                </div>
              )}
              {r.how && (
                <div>
                  <div className="mb-0.5 font-medium text-muted-foreground text-xs uppercase tracking-wide">Cara yang benar</div>
                  <div className="selectable">{r.how}</div>
                </div>
              )}
            </div>
            {r.command && <CommandBox command={r.command} />}
            <ul className="flex max-h-80 flex-col overflow-y-auto">
              {group.items.slice(0, 300).map((it) => (
                <li className="flex items-center gap-3 rounded-md px-1.5 py-1 text-sm hover:bg-accent" key={it.path}>
                  {selectable && (
                    <Checkbox
                      aria-label={`Pilih ${it.display}`}
                      checked={picked.has(it.path)}
                      onCheckedChange={(v) => toggle(it.path, !!v)}
                    />
                  )}
                  <span className="min-w-0 flex-1 truncate text-left [direction:rtl]" title={it.display}>
                    <bdi>{it.display}</bdi>
                  </span>
                  <span className="shrink-0 text-muted-foreground text-xs">{ago(it.mtime)}</span>
                  <span className="w-20 shrink-0 text-right tabular-nums">{bytes(it.size)}</span>
                  <IconAction label="Tampilkan di Finder" onClick={() => reveal(it.path)}>
                    <SquareArrowOutUpRightIcon />
                  </IconAction>
                  <IconAction
                    label="Lihat di Analisis Folder"
                    onClick={() => openFolder(it.path.slice(0, it.path.lastIndexOf("/")) || "/", it.path)}
                  >
                    <SearchIcon />
                  </IconAction>
                </li>
              ))}
              {group.items.length > 300 && (
                <li className="px-1.5 py-1 text-muted-foreground text-xs">…dan {group.items.length - 300} lainnya</li>
              )}
            </ul>
          </div>
        </CollapsiblePanel>
      </Collapsible>
    </Card>
  );
}

export function RecommendationsView() {
  const { hasResults, groups, trashSize, setEmptyTrashOpen, askTrash } = useApp();
  const [picked, setPicked] = useState<Set<string>>(new Set());

  const trashable = groups.filter((g) => g.kind === "trash");
  const manual = groups.filter((g) => g.kind === "manual");

  // Buang pilihan yang sudah tidak ada setelah daftar dimuat ulang.
  const valid = useMemo(() => new Set(trashable.flatMap((g) => g.items.map((i) => i.path))), [trashable]);
  const chosen: TrashRequest[] = trashable.flatMap((g) =>
    g.items
      .filter((i) => picked.has(i.path) && valid.has(i.path))
      .map((i) => ({ path: i.path, display: i.display, size: i.size, safety: g.rule.safety })),
  );
  const chosenTotal = chosen.reduce((a, i) => a + i.size, 0);

  if (!hasResults) return <NoResults />;

  const pickSafe = () =>
    setPicked((s) => {
      const next = new Set(s);
      for (const g of trashable) if (g.rule.safety === "aman") for (const i of g.items) next.add(i.path);
      return next;
    });

  return (
    <div className="flex min-h-full flex-col">
      <div className="flex flex-1 flex-col gap-5 p-8">
        <PageHeader
          actions={<Button onClick={pickSafe} variant="outline">Pilih semua yang aman</Button>}
          description="Dikelompokkan berdasarkan jenis. File dipindah ke Sampah dulu, jadi masih bisa dikembalikan."
          title="Rekomendasi Pembersihan"
        />
        {trashSize > 0 && (
          <Alert>
            <Trash2Icon />
            <AlertTitle>Sampah berisi {bytes(trashSize)}</AlertTitle>
            <AlertDescription>
              File di Sampah masih memakan ruang disk sampai dikosongkan. Mengosongkan Sampah bersifat permanen.
            </AlertDescription>
            <AlertAction>
              <Button onClick={() => setEmptyTrashOpen(true)} size="sm" variant="destructive-outline">
                Kosongkan Sampah…
              </Button>
            </AlertAction>
          </Alert>
        )}
        {groups.length === 0 && (
          <Card className="items-center p-10 text-muted-foreground">Tidak ada yang perlu dibersihkan di area ini. 🎉</Card>
        )}
        {trashable.length > 0 && (
          <section className="flex flex-col gap-3">
            <h2 className="font-semibold text-lg">Bisa dibuang dari sini</h2>
            {trashable.map((g) => (
              <GroupCard group={g} key={g.id} picked={picked} setPicked={setPicked} />
            ))}
          </section>
        )}
        {manual.length > 0 && (
          <section className="flex flex-col gap-3">
            <div>
              <h2 className="font-semibold text-lg">Perlu dibersihkan dari aplikasinya</h2>
              <p className="text-muted-foreground text-sm">
                Item ini besar, tapi menghapus filenya langsung bisa merusak data. Ikuti cara yang disarankan.
              </p>
            </div>
            {manual.map((g) => (
              <GroupCard group={g} key={g.id} picked={picked} setPicked={setPicked} />
            ))}
          </section>
        )}
      </div>
      <div
        className={cn(
          "sticky bottom-0 flex items-center gap-3 border-t bg-background/90 px-8 py-3 backdrop-blur",
          chosen.length === 0 && "hidden",
        )}
      >
        <span className="flex-1 font-medium">
          {chosen.length} item dipilih · <span className="tabular-nums">{bytes(chosenTotal)}</span>
        </span>
        <Button onClick={() => setPicked(new Set())} variant="ghost">
          Batal pilih
        </Button>
        <Button onClick={() => askTrash(chosen)} variant="destructive">
          <Trash2Icon />
          Buang ke Sampah…
        </Button>
      </div>
    </div>
  );
}
