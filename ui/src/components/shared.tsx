import { CopyIcon } from "lucide-react";
import type React from "react";
import { useApp } from "@/app-state";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import type { RuleInfo, Safety } from "@/lib/types";

export const SAFETY_LABEL: Record<Safety, string> = {
  aman: "Aman dihapus",
  hati: "Hati-hati",
  periksa: "Periksa dulu",
  jangan: "Jangan dihapus",
  unknown: "Tidak dikenali",
};

export const SAFETY_HINT: Record<Safety, string> = {
  aman: "Dibuat ulang otomatis / tidak dibutuhkan",
  hati: "Bisa dihapus, tapi ada akibatnya",
  periksa: "File pribadi — Anda yang putuskan",
  jangan: "Sistem / bisa merusak data",
  unknown: "Belum dikenali — periksa sendiri",
};

const SAFETY_VARIANT = {
  aman: "success",
  hati: "warning",
  periksa: "info",
  jangan: "error",
  unknown: "secondary",
} as const;

export function SafetyBadge({ safety, className }: { safety: Safety; className?: string }) {
  return (
    <Badge className={className} variant={SAFETY_VARIANT[safety]}>
      {SAFETY_LABEL[safety]}
    </Badge>
  );
}

/** Warna kategori (diagram "Kenapa penuh?"). */
export const CATEGORY_COLORS: Record<string, string> = {
  cache: "#10b981",
  log: "#84cc16",
  dev: "#8b5cf6",
  trash: "#14b8a6",
  downloads: "#06b6d4",
  installer: "#0ea5e9",
  backup: "#f59e0b",
  vm: "#f97316",
  apps: "#3b82f6",
  appdata: "#6366f1",
  media: "#ec4899",
  docs: "#a855f7",
  mail: "#eab308",
  cloud: "#38bdf8",
  system: "#737373",
  other: "#a3a3a3",
  unscanned: "#d4d4d4",
};

export function CommandBox({ command }: { command: string }) {
  const { copy } = useApp();
  return (
    <div className="flex items-center gap-2 rounded-lg border bg-muted/60 py-1.5 pr-1.5 pl-3">
      <code className="selectable min-w-0 flex-1 overflow-x-auto whitespace-nowrap font-mono text-xs">{command}</code>
      <Button aria-label="Salin perintah" onClick={() => copy(command)} size="icon-xs" variant="ghost">
        <CopyIcon />
      </Button>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-1">
      <div className="font-medium text-muted-foreground text-xs uppercase tracking-wide">{title}</div>
      <div className="selectable text-sm leading-relaxed">{children}</div>
    </div>
  );
}

/** Penjelasan sebuah item: kenapa besar, kalau dihapus, cara yang benar. */
export function Explanation({ rule, className }: { rule: RuleInfo; className?: string }) {
  return (
    <div className={cn("flex flex-col gap-3.5", className)}>
      <Section title={rule.id ? rule.title + (rule.inherited ? " (bagian dari)" : "") : "Apa ini?"}>{rule.why}</Section>
      {rule.effect && <Section title="Kalau dihapus">{rule.effect}</Section>}
      {rule.how && <Section title="Cara membersihkan yang benar">{rule.how}</Section>}
      {rule.command && (
        <div className="flex flex-col gap-1">
          <div className="font-medium text-muted-foreground text-xs uppercase tracking-wide">Perintah Terminal</div>
          <CommandBox command={rule.command} />
        </div>
      )}
    </div>
  );
}

export function PageHeader({
  title,
  description,
  actions,
}: {
  title: string;
  description?: React.ReactNode;
  actions?: React.ReactNode;
}) {
  return (
    <div className="flex flex-wrap items-start justify-between gap-4">
      <div className="flex min-w-0 flex-col gap-1">
        <h1 className="font-heading font-semibold text-2xl tracking-tight">{title}</h1>
        {description && <div className="text-muted-foreground text-sm">{description}</div>}
      </div>
      {actions && <div className="flex shrink-0 flex-wrap items-center gap-2">{actions}</div>}
    </div>
  );
}
