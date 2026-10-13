/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        ink: {
          950: "#030713",
          900: "#03050b",
          850: "#0b1222",
          800: "#101b30",
          750: "#15213a",
          700: "#1c2a43",
          600: "#293b58",
          500: "#3b5071",
        },
        gold: {
          200: "#b4f4ff",
          300: "#67e8ff",
          400: "#21dffa",
          500: "#00d6fa",
          600: "#009dbb",
        },
        violet: { 400: "#aa86ff", 500: "#7d47ff", 600: "#6335dd" },
        ember: {
          400: "#fb7185",
          500: "#f43f5e",
        },
      },
      fontFamily: {
        sans: [
          "Inter",
          "-apple-system",
          "BlinkMacSystemFont",
          "Segoe UI",
          "Roboto",
          "Helvetica Neue",
          "Arial",
          "sans-serif",
        ],
        mono: ["ui-monospace", "SFMono-Regular", "Menlo", "monospace"],
      },
      boxShadow: {
        glow: "0 0 0 1px rgba(0,214,250,0.15), 0 8px 40px -12px rgba(0,214,250,0.35)",
        card: "0 1px 0 0 rgba(255,255,255,0.03) inset, 0 12px 40px -20px rgba(0,0,0,0.8)",
      },
      keyframes: {
        "fade-in": {
          from: { opacity: "0", transform: "translateY(4px)" },
          to: { opacity: "1", transform: "translateY(0)" },
        },
        shimmer: {
          "100%": { transform: "translateX(100%)" },
        },
        "pulse-soft": {
          "0%, 100%": { opacity: "1" },
          "50%": { opacity: "0.55" },
        },
      },
      animation: {
        "fade-in": "fade-in 0.25s ease-out",
        shimmer: "shimmer 1.6s infinite",
        "pulse-soft": "pulse-soft 1.8s ease-in-out infinite",
      },
    },
  },
  plugins: [],
};
