/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{svelte,js,ts,jsx,tsx}"],
  theme: {
    extend: {
      colors: {
        e11y: {
          bg: "#1a1a2e",
          bg2: "#16213e",
          hover: "#2d3748",
          input: "#0f0f1a",
          border: "#333",
          "border-hover": "#555",
          text: "#e0e0e0",
          muted: "#a0aec0",
          accent: "#63b3ed",
          "accent-bg": "rgba(99, 179, 237, 0.12)",
          err: "#fc8181",
          "err-bg": "rgba(229, 62, 62, 0.12)",
          warn: "#f6ad55",
          "warn-bg": "rgba(246, 173, 85, 0.15)",
          ok: "#68d391",
        },
      },
    },
  },
  plugins: [],
};
