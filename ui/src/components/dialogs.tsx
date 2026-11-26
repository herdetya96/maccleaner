import { TriangleAlertIcon } from "lucide-react";
import { useApp } from "@/app-state";
import { Alert, AlertDescription } from "@/components/ui/alert";
import {
  AlertDialog,
  AlertDialogClose,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogPopup,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Button } from "@/components/ui/button";
import { Progress, ProgressIndicator, ProgressTrack } from "@/components/ui/progress";
import { ScrollArea } from "@/components/ui/scroll-area";
import { SafetyBadge } from "@/components/shared";
import { bytes, count, duration, eta } from "@/lib/format";

const ESTIMATE_NOTE = {
  history: "Perkiraan berdasarkan pemindaian sebelumnya di folder ini.",
  disk: "Perkiraan berdasarkan pemakaian disk.",
  tree: "Pemindaian pertama di folder ini — perkiraan makin akurat seiring berjalan.",
} as const;

/** Dialog progres pemindaian: bar, persen, sisa waktu. */
export function ScanDialog() {
  const { status, smoothEta, cancelScan } = useApp();
  const open = status?.state === "running";
  const pct = Math.round((status?.fraction ?? 0) * 100);
  return (
    <AlertDialog open={open}>
      <AlertDialogPopup className="max-w-md">
        <AlertDialogHeader>
          <AlertDialogTitle>Memindai {status?.display}</AlertDialogTitle>
          <AlertDialogDescription>{status ? ESTIMATE_NOTE[status.estimate] ?? "" : ""}</AlertDialogDescription>
        </AlertDialogHeader>
        <div className="flex flex-col gap-3 px-6 pb-6">
          <Progress value={Math.max(1, pct)}>
            <ProgressTrack className="h-2.5">
              <ProgressIndicator />
            </ProgressTrack>
          </Progress>
          <div className="flex items-baseline justify-between gap-4">
            <span className="font-semibold text-2xl tabular-nums">{pct}%</span>
            <span className="font-medium text-sm">{eta(smoothEta)}</span>
          </div>
          <div className="text-muted-foreground text-sm tabular-nums">
            {count(status?.files ?? 0)} file · {bytes(status?.bytes ?? 0)} · berjalan {duration(status?.elapsed ?? 0)}
          </div>
          <div className="truncate font-mono text-muted-foreground text-xs [direction:rtl]" title={status?.current}>
            {status?.current}
          </div>
        </div>
        <AlertDialogFooter>
          <Button onClick={cancelScan} variant="outline">
            Batalkan
          </Button>
        </AlertDialogFooter>
      </AlertDialogPopup>
    </AlertDialog>
  );
}

/** Konfirmasi sebelum membuang ke Sampah. */
export function ConfirmTrashDialog() {
  const { pendingTrash, closeTrash, confirmTrash } = useApp();
  const items = pendingTrash ?? [];
  const total = items.reduce((a, i) => a + i.size, 0);
  const risky = items.filter((i) => i.safety !== "aman").length;
  return (
    <AlertDialog onOpenChange={(o) => !o && closeTrash()} open={!!pendingTrash}>
      <AlertDialogPopup>
        <AlertDialogHeader>
          <AlertDialogTitle>
            Buang {items.length} item ({bytes(total)}) ke Sampah?
          </AlertDialogTitle>
          <AlertDialogDescription>
            Item dipindah ke Sampah dan masih bisa dikembalikan. Ruang disk baru benar-benar kosong setelah Sampah
            dikosongkan.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <div className="flex min-h-0 flex-col gap-3 px-6 pb-6">
          {risky > 0 && (
            <Alert variant="warning">
              <TriangleAlertIcon />
              <AlertDescription>
                {risky} item <b>bukan</b> berlabel "Aman dihapus". Pastikan Anda memang tidak membutuhkannya.
              </AlertDescription>
            </Alert>
          )}
          <ScrollArea className="max-h-64 rounded-lg border">
            <ul className="divide-y text-sm">
              {items.map((i) => (
                <li className="flex items-center gap-3 px-3 py-2" key={i.path}>
                  <span className="min-w-0 flex-1 truncate [direction:rtl] text-left" title={i.display}>
                    <bdi>
                      {i.display}
                      {i.contents ? " (isinya saja)" : ""}
                    </bdi>
                  </span>
                  {i.safety !== "aman" && <SafetyBadge safety={i.safety} />}
                  <span className="shrink-0 text-muted-foreground tabular-nums">{bytes(i.size)}</span>
                </li>
              ))}
            </ul>
          </ScrollArea>
        </div>
        <AlertDialogFooter>
          <AlertDialogClose render={<Button variant="outline" />}>Batal</AlertDialogClose>
          <Button onClick={confirmTrash} variant="destructive">
            Ya, buang ke Sampah
          </Button>
        </AlertDialogFooter>
      </AlertDialogPopup>
    </AlertDialog>
  );
}

export function EmptyTrashDialog() {
  const { emptyTrashOpen, setEmptyTrashOpen, confirmEmptyTrash, trashSize } = useApp();
  return (
    <AlertDialog onOpenChange={setEmptyTrashOpen} open={emptyTrashOpen}>
      <AlertDialogPopup>
        <AlertDialogHeader>
          <AlertDialogTitle>Kosongkan Sampah?</AlertDialogTitle>
          <AlertDialogDescription>
            Semua file di Sampah ({bytes(trashSize)}) akan dihapus <b>permanen</b> dan tidak bisa dikembalikan.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogClose render={<Button variant="outline" />}>Batal</AlertDialogClose>
          <Button onClick={confirmEmptyTrash} variant="destructive">
            Kosongkan
          </Button>
        </AlertDialogFooter>
      </AlertDialogPopup>
    </AlertDialog>
  );
}
