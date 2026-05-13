# 🎨 AI Vibe — Landing Page

> Design system landing page for [AI Vibe](https://github.com/irosssss/AIVibe2026) built with **Apple Design System** principles + **shadcn/ui** components.

![Next.js](https://img.shields.io/badge/Next.js-14-black?logo=next.js)
![TailwindCSS](https://img.shields.io/badge/Tailwind-3.4-blue?logo=tailwindcss)
![shadcn/ui](https://img.shields.io/badge/shadcn/ui-latest-black)
![TypeScript](https://img.shields.io/badge/TypeScript-5.4-blue?logo=typescript)

## ✨ Features

- **Apple Design Language** — SF Pro typography, frosted glass effects, smooth animations
- **shadcn/ui Components** — Button, Card, Badge with custom variants
- **Responsive** — Mobile-first, looks great on all devices
- **Dark Mode** — Enabled by default (Apple style)
- **Sections:**
  - 🏠 Hero with phone mockup
  - ⚡ Features grid (6 cards)
  - 🔄 How It Works (4 steps)
  - 💰 Pricing (3 tiers)
  - 📌 Footer with links

## 🚀 Quick Start

```bash
# Install dependencies
npm install

# Start dev server
npm run dev

# Build for production
npm run build
```

Open [http://localhost:3000](http://localhost:3000).

## 📁 Structure

```
demo-design-mg/
├── src/
│   ├── app/
│   │   ├── globals.css          # CSS variables + Tailwind
│   │   ├── layout.tsx           # Root layout + metadata
│   │   └── page.tsx             # Landing page composition
│   ├── components/
│   │   ├── ui/                  # shadcn/ui primitives
│   │   │   ├── button.tsx
│   │   │   ├── card.tsx
│   │   │   └── badge.tsx
│   │   ├── Navigation.tsx       # Fixed nav with blur
│   │   ├── HeroSection.tsx      # Hero + phone mockup
│   │   ├── FeaturesSection.tsx  # 6 feature cards
│   │   ├── HowItWorksSection.tsx
│   │   ├── PricingSection.tsx   # 3-tier pricing
│   │   └── FooterSection.tsx
│   └── lib/
│       └── utils.ts             # cn() helper
├── tailwind.config.ts           # Apple-style tokens
├── package.json
└── tsconfig.json
```

## 🎨 Design Tokens

| Token | Value | Inspired By |
|-------|-------|-------------|
| Font | SF Pro Display / System | Apple.com |
| Radius | `1rem` (16px) | iOS 18 widgets |
| Blur | `backdrop-blur-xl` | macOS Sonoma |
| Colors | Blue→Purple gradient | Apple Vision Pro |
| Animation | `ease-out 0.8s` | Apple keynote transitions |

## 🔗 Links

- **Main project:** [AIVibe2026](https://github.com/irosssss/AIVibe2026)
- **shadcn/ui:** [ui.shadcn.com](https://ui.shadcn.com)
- **RoomPlan:** [Apple Developer](https://developer.apple.com/augmented-reality/roomplan/)

## License

MIT
