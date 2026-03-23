import path from "node:path"
import { fileURLToPath } from "node:url"
import { defineConfig } from "vite"
import { svelte } from "@sveltejs/vite-plugin-svelte"
import cssInjectedByJsPlugin from "vite-plugin-css-injected-by-js"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const assetOutDir = path.resolve(__dirname, "../lib/e11y/devtools/overlay/assets")

export default defineConfig(({ command }) => {
  if (command === "serve") {
    return {
      plugins: [svelte()],
    }
  }

    return {
      plugins: [svelte(), cssInjectedByJsPlugin()],
      build: {
        copyPublicDir: false,
        lib: {
        entry: path.resolve(__dirname, "src/overlay-entry.ts"),
        name: "E11yDevtoolsOverlay",
        formats: ["iife"],
        fileName: () => "overlay.js",
      },
      outDir: assetOutDir,
      emptyOutDir: false,
      rollupOptions: {
        output: {
          inlineDynamicImports: true,
        },
      },
    },
  }
})
