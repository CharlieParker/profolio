import path from "path";
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      "@": path.resolve(import.meta.dirname, "./src"),
    },
  },
  // mirrors nginx's /api/ proxy so native `pnpm dev` behaves like the container
  server: {
    proxy: {
      "/api": "http://localhost:8000",
    },
  },
});
