import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

// Hasil build (dist/) dimuat oleh desktop app lewat skema maccleaner://app/
// dan bisa juga disajikan oleh server Python (mode pengembangan).
export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: { alias: { "@": decodeURIComponent(new URL("./src", import.meta.url).pathname) } },
  base: "./",
  build: { outDir: "dist", emptyOutDir: true, assetsDir: "assets", target: "safari16" },
});
