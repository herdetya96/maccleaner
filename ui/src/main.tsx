import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { AppProvider } from "@/app-state";
import { ToastProvider } from "@/components/ui/toast";
import { TooltipProvider } from "@/components/ui/tooltip";
import App from "./App";
import "./index.css";

// Mode gelap mengikuti pengaturan macOS.
const media = window.matchMedia("(prefers-color-scheme: dark)");
const applyTheme = () => document.documentElement.classList.toggle("dark", media.matches);
applyTheme();
media.addEventListener("change", applyTheme);

// Di desktop app, matikan menu klik kanan bawaan WebKit (Reload/Inspect) kecuali di teks.
document.addEventListener("contextmenu", (e) => {
  const t = e.target as HTMLElement;
  if (!t.closest("input, textarea, .selectable")) e.preventDefault();
});

const rootEl = document.getElementById("root");
if (rootEl) {
  createRoot(rootEl).render(
    <StrictMode>
      <ToastProvider position="top-right">
        <TooltipProvider>
          <AppProvider>
            <App />
          </AppProvider>
        </TooltipProvider>
      </ToastProvider>
    </StrictMode>,
  );
}
