/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{svelte,js,ts,jsx,tsx}"],
  theme: {
    extend: {
      colors: {
        e11y: {
          bg: "var(--e11y-bg)",
          bg2: "var(--e11y-bg2)",
          hover: "var(--e11y-bg-hover)",
          input: "var(--e11y-bg-input)",
          border: "var(--e11y-border)",
          "border-hover": "var(--e11y-border-hover)",
          text: "var(--e11y-text)",
          muted: "var(--e11y-muted)",
          accent: "var(--e11y-accent)",
          "accent-bg": "var(--e11y-accent-bg)",
          "accent-border": "var(--e11y-accent-border)",
          err: "var(--e11y-err)",
          "err-bg": "var(--e11y-err-bg)",
          "err-border": "var(--e11y-err-border)",
          warn: "var(--e11y-warn)",
          "warn-bg": "var(--e11y-warn-bg)",
          ok: "var(--e11y-ok)",
        },
      },
    },
  },
  plugins: [],
  corePlugins: {
    preflight: false,
  },
};
