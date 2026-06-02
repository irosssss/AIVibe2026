// Home screen — light + dark.

function HomeScreen({ dark = false }) {
  const C = dark ? COLORS.dark : COLORS.light;
  const W = 402;

  return (
    <div style={{
      width: W, height: 874, background: C.bg, color: C.onSurface,
      position: 'relative', overflow: 'hidden',
    }}>
      <StatusBar dark={dark} />

      {/* scroll content */}
      <div style={{
        position: 'absolute', inset: 0, paddingTop: 54, paddingBottom: 84,
        overflow: 'hidden', display: 'flex', flexDirection: 'column',
      }}>
        {/* Top-right avatar + search */}
        <div style={{
          padding: '8px 16px 0', display: 'flex', justifyContent: 'flex-end', alignItems: 'center', gap: 10,
        }}>
          <div style={{
            width: 36, height: 36, borderRadius: 18,
            background: dark ? 'rgba(241,236,226,0.08)' : 'rgba(28,25,22,0.05)',
            display: 'flex', alignItems: 'center', justifyContent: 'center', color: C.onSurfaceMuted,
          }}>
            <Icon name="magnifyingglass" size={20} />
          </div>
          <div style={{
            width: 36, height: 36, borderRadius: 18,
            background: `linear-gradient(135deg, ${C.sandSoft}, ${C.terracottaSoft})`,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            ...typeStyle('callout', { color: C.onSurface, fontWeight: 700 }),
          }}>А</div>
        </div>

        {/* Large title */}
        <div style={{ padding: '6px 16px 4px' }}>
          <div style={{ ...typeStyle('largeTitle', { color: C.onSurface }) }}>Привет, Анна</div>
          <div style={{ ...typeStyle('body', { color: C.onSurfaceMuted, marginTop: 4 }) }}>
            Чем займёмся сегодня?
          </div>
        </div>

        {/* Hero CTA card */}
        <div style={{ padding: '20px 16px 0' }}>
          <div style={{
            background: C.surface, borderRadius: 20, padding: 18,
            boxShadow: softShadow(dark),
            display: 'flex', flexDirection: 'column', gap: 14,
            position: 'relative', overflow: 'hidden',
          }}>
            {/* line-art empty room — extremely minimal */}
            <div style={{
              height: 124, width: '100%', position: 'relative',
              background: `linear-gradient(180deg, ${dark ? '#26221C' : '#FAF6EF'} 0%, ${dark ? '#1F1C17' : '#F2EBDD'} 100%)`,
              borderRadius: 14, overflow: 'hidden',
            }}>
              <svg width="100%" height="100%" viewBox="0 0 320 124" preserveAspectRatio="xMidYMid slice" fill="none"
                stroke={dark ? 'rgba(241,236,226,0.55)' : 'rgba(28,25,22,0.45)'} strokeWidth="1.3" strokeLinecap="round">
                {/* room perspective */}
                <path d="M30 110 L120 70 L240 70 L290 110 Z" />
                <path d="M30 18 L120 50 L240 50 L290 18" />
                <path d="M30 18 L30 110 M290 18 L290 110" />
                <path d="M120 50 L120 70 M240 50 L240 70" />
                {/* window */}
                <rect x="140" y="58" width="40" height="10" />
                <path d="M160 58 L160 68" />
                {/* lamp */}
                <path d="M210 50 L210 95 L218 100" />
                <circle cx="218" cy="92" r="6" fill={C.sandSoft} stroke="none" />
                <circle cx="218" cy="92" r="6" />
              </svg>
            </div>
            <div>
              <div style={{ ...typeStyle('caption', { color: C.terracotta, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.8 }) }}>Новый проект</div>
              <div style={{ ...typeStyle('title2', { color: C.onSurface, marginTop: 4 }) }}>
                Отсканируйте комнату
              </div>
              <div style={{ ...typeStyle('callout', { color: C.onSurfaceMuted, marginTop: 4 }) }}>
                AI подберёт стиль и мебель в рамках бюджета
              </div>
            </div>
            <PrimaryButton dark={dark}>Начать сканирование</PrimaryButton>
          </div>
        </div>

        {/* Current projects */}
        <div style={{ marginTop: 24 }}>
          <SectionHeader dark={dark} title="Текущие проекты" trailing="Все" />
          <div style={{
            display: 'flex', gap: 12, padding: '0 16px', overflow: 'hidden',
          }}>
            <ProjectCard dark={dark} name="Гостиная" tone="sand"
              step={3} total={5} budget="245 000" budgetMax="350 000" pct={0.7} />
            <ProjectCard dark={dark} name="Кухня" tone="sage"
              step={1} total={5} budget="62 000" budgetMax="180 000" pct={0.34} />
          </div>
        </div>

        {/* Ideas of the day */}
        <div style={{ marginTop: 24 }}>
          <SectionHeader dark={dark} title="Идеи дня" />
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10, padding: '0 16px' }}>
            <IdeaCard dark={dark} tone="terracotta" style="Скандинавский · светлая гостиная" budget="от 180 000 ₽" />
            <IdeaCard dark={dark} tone="olive" style="Японди · спальня в тёплых тонах" budget="от 220 000 ₽" />
          </div>
        </div>

        <div style={{ height: 24 }} />
      </div>

      <TabBar dark={dark} active="home" />
    </div>
  );
}

function SectionHeader({ dark, title, trailing }) {
  const C = dark ? COLORS.dark : COLORS.light;
  return (
    <div style={{
      display: 'flex', alignItems: 'baseline', justifyContent: 'space-between',
      padding: '0 16px 10px',
    }}>
      <div style={{ ...typeStyle('title3', { color: C.onSurface }) }}>{title}</div>
      {trailing && <div style={{ ...typeStyle('callout', { color: C.terracotta, fontWeight: 600 }) }}>{trailing}</div>}
    </div>
  );
}

function ProjectCard({ dark, name, tone, step, total, budget, budgetMax, pct }) {
  const C = dark ? COLORS.dark : COLORS.light;
  return (
    <div style={{
      width: 248, flexShrink: 0,
      background: C.surface, borderRadius: 20, padding: 12,
      boxShadow: softShadow(dark),
      display: 'flex', flexDirection: 'column', gap: 10,
    }}>
      <PhotoSlot tone={tone} ratio="16 / 10" label="скан комнаты" radius={12} />
      <div style={{ display: 'flex', flexDirection: 'column', gap: 6, padding: '2px 4px 4px' }}>
        <div style={{ ...typeStyle('headline', { color: C.onSurface }) }}>{name}</div>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div style={{ ...typeStyle('caption', { color: C.onSurfaceMuted }) }}>Шаг {step} из {total}</div>
          <div style={{ ...typeStyle('caption', { color: C.onSurface, fontWeight: 600 }) }}>{budget} ₽</div>
        </div>
        <ProgressBar dark={dark} pct={pct} color={pct < 0.8 ? C.sage : pct < 1 ? C.amber : C.danger} />
      </div>
    </div>
  );
}

function ProgressBar({ dark, pct, color, height = 5 }) {
  const C = dark ? COLORS.dark : COLORS.light;
  return (
    <div style={{
      width: '100%', height, borderRadius: height/2,
      background: dark ? 'rgba(241,236,226,0.10)' : 'rgba(28,25,22,0.08)',
      overflow: 'hidden',
    }}>
      <div style={{
        width: `${Math.min(Math.max(pct, 0), 1) * 100}%`, height: '100%',
        background: color || C.sage, borderRadius: height/2,
      }} />
    </div>
  );
}

function IdeaCard({ dark, tone, style, budget }) {
  const C = dark ? COLORS.dark : COLORS.light;
  return (
    <div style={{
      background: C.surface, borderRadius: 20, padding: 12,
      boxShadow: softShadow(dark),
      display: 'flex', gap: 12, alignItems: 'center',
    }}>
      <div style={{ width: 88, flexShrink: 0 }}>
        <PhotoSlot tone={tone} ratio="1 / 1" radius={12} />
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ ...typeStyle('caption', { color: C.sage, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.6 }) }}>Идея от AI</div>
        <div style={{ ...typeStyle('headline', { color: C.onSurface, marginTop: 2 }) }}>{style}</div>
        <div style={{ ...typeStyle('caption', { color: C.onSurfaceMuted, marginTop: 4 }) }}>{budget}</div>
      </div>
      <div style={{
        padding: '8px 14px', borderRadius: 10,
        background: dark ? 'rgba(209,127,98,0.18)' : 'rgba(194,103,74,0.12)',
        color: C.terracotta,
        ...typeStyle('caption', { fontWeight: 600 }),
      }}>Примерить</div>
    </div>
  );
}

Object.assign(window, { HomeScreen, ProgressBar, SectionHeader });
