import { SearchIcon, SquareArrowOutUpRightIcon, Trash2Icon } from "lucide-react";
import { useEffect, useState } from "react";
import { notify, useApp } from "@/app-state";
import { PageHeader, SafetyBadge } from "@/components/shared";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Tooltip, TooltipPopup, TooltipTrigger } from "@/components/ui/tooltip";
import { canTrash } from "@/views/explore";
import { NoResults } from "@/views/no-results";
import { api } from "@/lib/api";
import { ago, bytes } from "@/lib/format";
import type { Item } from "@/lib/types";

export function LargeFilesView() {
  const { hasResults, revision, reveal, askTrash, openFolder } = useApp();
  const [items, setItems] = useState<Item[]>([]);
  const [picked, setPicked] = useState<Set<string>>(new Set());

  useEffect(() => {
    if (!hasResults) return;
    api
      .largeFiles()
      .then((list) => {
        setItems(list);
        setPicked((s) => new Set([...s].filter((p) => list.some((i) => i.path === p))));
      })
      .catch((e) => notify("Gagal memuat file besar", String(e.message), "error"));
  }, [hasResults, revision]);

  if (!hasResults) return <NoResults />;

  const chosen = items.filter((i) => i.path && picked.has(i.path) && canTrash(i));
  const total = chosen.reduce((a, i) => a + i.size, 0);
  const toggle = (path: string, on: boolean) =>
    setPicked((s) => {
      const n = new Set(s);
      on ? n.add(path) : n.delete(path);
      return n;
    });

  return (
    <div className="flex min-h-full flex-col">
      <div className="flex flex-1 flex-col gap-5 p-8">
        <PageHeader description="File tunggal terbesar di area yang dipindai." title="File Terbesar" />
        <Card className="overflow-hidden">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="w-10" />
                <TableHead>Nama</TableHead>
                <TableHead className="text-right">Ukuran</TableHead>
                <TableHead>Diubah</TableHead>
                <TableHead>Status</TableHead>
                <TableHead className="w-20" />
              </TableRow>
            </TableHeader>
            <TableBody>
              {items.length === 0 && (
                <TableRow>
                  <TableCell className="py-10 text-center text-muted-foreground" colSpan={6}>
                    Tidak ada file besar.
                  </TableCell>
                </TableRow>
              )}
              {items.map((it) => {
                const path = it.path as string;
                const ok = canTrash(it);
                return (
                  <TableRow key={path}>
                    <TableCell>
                      {ok && (
                        <Checkbox
                          aria-label={`Pilih ${it.name}`}
                          checked={picked.has(path)}
                          onCheckedChange={(v) => toggle(path, !!v)}
                        />
                      )}
                    </TableCell>
                    <TableCell className="w-full max-w-0">
                      <div className="truncate font-medium">{it.name}</div>
                      <div className="truncate font-mono text-muted-foreground text-xs [direction:rtl] text-left" title={it.display}>
                        <bdi>{it.display}</bdi>
                      </div>
                    </TableCell>
                    <TableCell className="whitespace-nowrap text-right tabular-nums">{bytes(it.size)}</TableCell>
                    <TableCell className="whitespace-nowrap text-muted-foreground">{ago(it.mtime)}</TableCell>
                    <TableCell>
                      <Tooltip>
                        <TooltipTrigger render={<div className="flex flex-col items-start gap-0.5" />}>
                          <SafetyBadge safety={it.rule.safety} />
                          <span className="max-w-44 truncate text-muted-foreground text-xs">{it.rule.title}</span>
                        </TooltipTrigger>
                        <TooltipPopup className="max-w-72">{it.rule.why}</TooltipPopup>
                      </Tooltip>
                    </TableCell>
                    <TableCell>
                      <div className="flex justify-end gap-0.5">
                        <Button aria-label="Tampilkan di Finder" onClick={() => reveal(path)} size="icon-xs" variant="ghost">
                          <SquareArrowOutUpRightIcon />
                        </Button>
                        <Button
                          aria-label="Lihat di Analisis Folder"
                          onClick={() => openFolder(path.slice(0, path.lastIndexOf("/")) || "/", path)}
                          size="icon-xs"
                          variant="ghost"
                        >
                          <SearchIcon />
                        </Button>
                      </div>
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </Card>
      </div>
      {chosen.length > 0 && (
        <div className="sticky bottom-0 flex items-center gap-3 border-t bg-background/90 px-8 py-3 backdrop-blur">
          <span className="flex-1 font-medium">
            {chosen.length} file dipilih · <span className="tabular-nums">{bytes(total)}</span>
          </span>
          <Button onClick={() => setPicked(new Set())} variant="ghost">
            Batal pilih
          </Button>
          <Button
            onClick={() =>
              askTrash(
                chosen.map((i) => ({ path: i.path as string, display: i.display, size: i.size, safety: i.rule.safety })),
              )
            }
            variant="destructive"
          >
            <Trash2Icon />
            Buang ke Sampah…
          </Button>
        </div>
      )}
    </div>
  );
}
