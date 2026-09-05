import type { Config } from "tailwindcss"

export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: { extend: {
    colors: {
      background: "hsl(var(--background))", foreground: "hsl(var(--foreground))",
      card: "hsl(var(--card))", popover: "hsl(var(--popover))", border: "hsl(var(--border))",
      input: "hsl(var(--input))", ring: "hsl(var(--ring))", muted: { DEFAULT: "hsl(var(--muted))", foreground: "hsl(var(--muted-foreground))" },
      primary: { DEFAULT: "hsl(var(--primary))", foreground: "hsl(var(--primary-foreground))" },
      secondary: { DEFAULT: "hsl(var(--secondary))", foreground: "hsl(var(--secondary-foreground))" },
      accent: { DEFAULT: "hsl(var(--accent))", foreground: "hsl(var(--accent-foreground))" },
      destructive: "hsl(var(--destructive))", success: "hsl(var(--success))", warning: "hsl(var(--warning))",
      "brand-hover": "hsl(var(--brand-hover))", "brand-soft": "hsl(var(--brand-soft))", "brand-border": "hsl(var(--brand-border))",
      "surface-raised": "hsl(var(--surface-raised))", "surface-hover": "hsl(var(--surface-hover))", "border-strong": "hsl(var(--border-strong))"
    },
    borderRadius: { sm: ".375rem", md: ".5rem", lg: ".625rem", xl: ".875rem" },
    boxShadow: { floating: "0 12px 32px rgb(0 0 0 / 42%)", modal: "0 24px 64px rgb(0 0 0 / 55%)" },
    fontFamily: { mono: ['"SFMono-Regular"', "Consolas", "monospace"] }
  } }, plugins: []
} satisfies Config
