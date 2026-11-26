import { HardDriveIcon } from "lucide-react";
import { useApp } from "@/app-state";
import { Button } from "@/components/ui/button";
import { Empty, EmptyContent, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty";

export function NoResults() {
  const { startScan, info } = useApp();
  return (
    <Empty className="h-full">
      <EmptyHeader>
        <EmptyMedia variant="icon">
          <HardDriveIcon />
        </EmptyMedia>
        <EmptyTitle>Belum ada hasil pemindaian</EmptyTitle>
        <EmptyDescription>Pindai folder rumah atau seluruh disk terlebih dahulu.</EmptyDescription>
      </EmptyHeader>
      <EmptyContent>
        <Button disabled={!info} onClick={() => info && startScan(info.home)}>
          Pindai folder rumah
        </Button>
      </EmptyContent>
    </Empty>
  );
}
