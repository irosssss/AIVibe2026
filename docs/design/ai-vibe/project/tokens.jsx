// AIVibe design tokens — colors, type, icons, small primitives.

const COLORS = {
  light: {
    bg: '#F6F2EB',
    bgSubtle: '#EFEAE1',
    surface: '#FFFCF6',
    elevated: '#FFFFFF',
    onSurface: '#1C1916',
    onSurfaceMuted: '#6E665B',
    onSurfaceFaint: '#A39B8E',
    divider: 'rgba(28, 25, 22, 0.08)',
    hairline: 'rgba(28, 25, 22, 0.06)',
    terracotta: '#C2674A',
    terracottaSoft: '#E8C9BC',
    sage: '#88A084',
    sageSoft: '#CFDCC8',
    sand: '#D6B589',
    sandSoft: '#EFE0C2',
    amber: '#DD9F4A',
    danger: '#B5503A',
    fieldBg: '#EFEAE1',
  },
  dark: {
    bg: '#15130F',
    bgSubtle: '#1A1814',
    surface: '#1F1C17',
    elevated: '#2A2620',
    onSurface: '#F1ECE2',
    onSurfaceMuted: '#A09889',
    onSurfaceFaint: '#6E665B',
    divider: 'rgba(241, 236, 226, 0.10)',
    hairline: 'rgba(241, 236, 226, 0.07)',
    terracotta: '#D17F62',
    terracottaSoft: '#4A2E22',
    sage: '#9CB497',
    sageSoft: '#2E3A2C',
    sand: '#E0C091',
    sandSoft: '#3D3325',
    amber: '#E5AC5F',
    danger: '#C2624A',
    fieldBg: '#2A2620',
  },
};

// SF Pro stack — system font on macOS/iOS.
const FONT_DISPLAY = '-apple-system, "SF Pro Display", "SF Pro", system-ui, sans-serif';
const FONT_TEXT = '-apple-system, "SF Pro Text", "SF Pro", system-ui, sans-serif';
const FONT_MONO = 'ui-monospace, "SF Mono", Menlo, monospace';

// 8 type roles per Apple HIG.
const TYPE = {
  largeTitle: { font: FONT_DISPLAY, size: 34, weight: 700, leading: 41, tracking: 0.37 },
  title1:     { font: FONT_DISPLAY, size: 28, weight: 700, leading: 34, tracking: 0.36 },
  title2:     { font: FONT_DISPLAY, size: 22, weight: 700, leading: 28, tracking: 0.35 },
  title3:     { font: FONT_DISPLAY, size: 20, weight: 600, leading: 25, tracking: 0.38 },
  headline:   { font: FONT_TEXT,    size: 17, weight: 600, leading: 22, tracking: -0.43 },
  body:       { font: FONT_TEXT,    size: 17, weight: 400, leading: 22, tracking: -0.43 },
  callout:    { font: FONT_TEXT,    size: 16, weight: 400, leading: 21, tracking: -0.32 },
  caption:    { font: FONT_TEXT,    size: 13, weight: 400, leading: 18, tracking: -0.08 },
};

function typeStyle(role, overrides = {}) {
  const t = TYPE[role];
  return {
    fontFamily: t.font,
    fontSize: t.size,
    fontWeight: t.weight,
    lineHeight: `${t.leading}px`,
    letterSpacing: `${(t.tracking >= 0 ? '' : '-') + Math.abs(t.tracking).toFixed(2)}px`,
    ...overrides,
  };
}

// Format helpers
const fmtRub = (n) => `${n.toLocaleString('ru-RU')} ₽`;

// SF-Symbols-style icon set (stroke-based, currentColor).
function Icon({ name, size = 22, strokeWidth = 1.6, style }) {
  const sw = strokeWidth;
  const common = { width: size, height: size, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: sw, strokeLinecap: 'round', strokeLinejoin: 'round', style };
  switch (name) {
    case 'house':
      return <svg {...common}><path d="M3 11.5 12 4l9 7.5"/><path d="M5.5 10v9.5h13V10"/></svg>;
    case 'house.fill':
      return <svg {...common} fill="currentColor" stroke="none"><path d="M12 3 3 11v1.2l2-.1V20a1 1 0 0 0 1 1h3.5v-6h5V21H18a1 1 0 0 0 1-1v-7.9l2 .1V11l-9-8Z"/></svg>;
    case 'viewfinder':
      return <svg {...common}><path d="M4 8V5h3"/><path d="M20 8V5h-3"/><path d="M4 16v3h3"/><path d="M20 16v3h-3"/></svg>;
    case 'camera.viewfinder':
      return <svg {...common}><path d="M4 8V5h3"/><path d="M20 8V5h-3"/><path d="M4 16v3h3"/><path d="M20 16v3h-3"/><circle cx="12" cy="12" r="3"/></svg>;
    case 'bag':
      return <svg {...common}><path d="M5 8h14l-1 12H6L5 8Z"/><path d="M9 8a3 3 0 0 1 6 0"/></svg>;
    case 'bag.fill':
      return <svg {...common} fill="currentColor" stroke="none"><path d="M9 5a3 3 0 0 1 6 0v1h3.6l1 14H4.4l1-14H9V5Zm1.4 1h3.2a1.6 1.6 0 0 0-3.2 0Z"/></svg>;
    case 'person.circle':
      return <svg {...common}><circle cx="12" cy="12" r="9"/><circle cx="12" cy="10" r="3"/><path d="M5.5 19a7 7 0 0 1 13 0"/></svg>;
    case 'chevron.left':
      return <svg {...common}><path d="M15 5l-7 7 7 7"/></svg>;
    case 'chevron.right':
      return <svg {...common}><path d="M9 5l7 7-7 7"/></svg>;
    case 'chevron.down':
      return <svg {...common}><path d="M5 9l7 7 7-7"/></svg>;
    case 'chevron.up':
      return <svg {...common}><path d="M5 15l7-7 7 7"/></svg>;
    case 'xmark':
      return <svg {...common}><path d="M6 6l12 12M18 6L6 18"/></svg>;
    case 'plus':
      return <svg {...common}><path d="M12 5v14M5 12h14"/></svg>;
    case 'heart':
      return <svg {...common}><path d="M12 20s-7-4.5-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.5-7 10-7 10Z"/></svg>;
    case 'heart.fill':
      return <svg {...common} fill="currentColor" stroke="currentColor"><path d="M12 20s-7-4.5-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.5-7 10-7 10Z"/></svg>;
    case 'star.fill':
      return <svg {...common} fill="currentColor" stroke="none"><path d="m12 3 2.8 5.7 6.2.9-4.5 4.4 1.1 6.2L12 17.3 6.4 20.2l1.1-6.2L3 9.6l6.2-.9L12 3Z"/></svg>;
    case 'star':
      return <svg {...common}><path d="m12 3 2.8 5.7 6.2.9-4.5 4.4 1.1 6.2L12 17.3 6.4 20.2l1.1-6.2L3 9.6l6.2-.9L12 3Z"/></svg>;
    case 'checkmark.circle.fill':
      return <svg {...common} fill="currentColor" stroke="none"><circle cx="12" cy="12" r="9"/><path d="m8 12 3 3 5-6" stroke="#fff" strokeWidth="2" fill="none" strokeLinecap="round" strokeLinejoin="round"/></svg>;
    case 'xmark.circle.fill':
      return <svg {...common} fill="currentColor" stroke="none"><circle cx="12" cy="12" r="9"/><path d="M9 9l6 6M15 9l-6 6" stroke="#fff" strokeWidth="2" strokeLinecap="round" fill="none"/></svg>;
    case 'info.circle':
      return <svg {...common}><circle cx="12" cy="12" r="9"/><path d="M12 11v6"/><circle cx="12" cy="7.5" r="0.8" fill="currentColor"/></svg>;
    case 'paperplane.fill':
      return <svg {...common} fill="currentColor" stroke="none"><path d="M3 11 21 4l-7 17-3-7-8-3Z"/></svg>;
    case 'paperclip':
      return <svg {...common}><path d="M15 7v9a4 4 0 0 1-8 0V6a3 3 0 0 1 6 0v10a2 2 0 0 1-4 0V8"/></svg>;
    case 'magnifyingglass':
      return <svg {...common}><circle cx="11" cy="11" r="6"/><path d="m20 20-4.5-4.5"/></svg>;
    case 'wallet':
      return <svg {...common}><rect x="3" y="6" width="18" height="13" rx="2"/><path d="M16 13h2"/><path d="M3 9h13a2 2 0 0 1 2-2V5l-3 1H5a2 2 0 0 0-2 2v1Z" fill="currentColor" stroke="none"/></svg>;
    case 'lightbulb':
      return <svg {...common}><path d="M9 17h6"/><path d="M10 20h4"/><path d="M8 13.5a5 5 0 1 1 8 0L15 16H9l-1-2.5Z"/></svg>;
    case 'figure.walk':
      return <svg {...common}><circle cx="14" cy="4.5" r="1.5"/><path d="M14 7l-3 5 2 3v6"/><path d="M13 15l-3 2-2-3"/><path d="M14 12l4 1"/></svg>;
    case 'ruler':
      return <svg {...common}><rect x="2" y="9" width="20" height="6" rx="1" transform="rotate(-12 12 12)"/><path d="M6 10v2M9 9v3M12 8v3M15 7v3M18 6v3" stroke="currentColor"/></svg>;
    case 'cube':
      return <svg {...common}><path d="M12 3 3 7.5v9L12 21l9-4.5v-9L12 3Z"/><path d="M3 7.5 12 12l9-4.5M12 12v9"/></svg>;
    case 'square.stack':
      return <svg {...common}><rect x="3" y="3" width="14" height="14" rx="2"/><path d="M7 21h12a2 2 0 0 0 2-2V7"/></svg>;
    case 'square.and.arrow.up':
      return <svg {...common}><path d="M12 3v13"/><path d="m8 7 4-4 4 4"/><path d="M5 12v8h14v-8"/></svg>;
    case 'ellipsis':
      return <svg {...common}><circle cx="5" cy="12" r="1.2" fill="currentColor"/><circle cx="12" cy="12" r="1.2" fill="currentColor"/><circle cx="19" cy="12" r="1.2" fill="currentColor"/></svg>;
    case 'arrow.left.arrow.right':
      return <svg {...common}><path d="M7 7h13l-3-3M17 17H4l3 3"/></svg>;
    case 'sparkles':
      return <svg {...common}><path d="M12 3v4M12 17v4M3 12h4M17 12h4"/><path d="m6 6 2 2M16 16l2 2M18 6l-2 2M8 16l-2 2"/></svg>;
    case 'trash':
      return <svg {...common}><path d="M4 7h16"/><path d="M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/><path d="m6 7 1 13h10l1-13"/></svg>;
    case 'pencil':
      return <svg {...common}><path d="M4 20l4-1 11-11-3-3L5 16l-1 4Z"/></svg>;
    default:
      return <svg {...common}><rect x="4" y="4" width="16" height="16" rx="2"/></svg>;
  }
}

// Status bar in dark/light variant — uses IOSStatusBar from ios-frame.

// Tiny chip used for badges (marketplace, provider, etc.)
function Chip({ children, bg, color, style }) {
  return (
    <div style={{
      display: 'inline-flex', alignItems: 'center', gap: 4,
      padding: '3px 8px', borderRadius: 6,
      background: bg, color: color,
      fontFamily: FONT_TEXT, fontSize: 11, fontWeight: 600,
      letterSpacing: 0.2, lineHeight: '14px', whiteSpace: 'nowrap',
      ...style,
    }}>{children}</div>
  );
}

// Soft-shadow card — 20pt radius, 16pt blur, 8pt Y, 0.08 opacity
function softShadow(dark) {
  return dark
    ? '0 8px 16px rgba(0,0,0,0.35), 0 1px 2px rgba(0,0,0,0.4)'
    : '0 8px 16px rgba(28,25,22,0.08), 0 1px 2px rgba(28,25,22,0.04)';
}

// Tinted placeholder photo block — used wherever a product/inspiration
// image goes. Warm earthy gradient + subtle stripe + monospace caption.
function PhotoSlot({ tone = 'sand', label, ratio = '4 / 3', radius = 14, style }) {
  const tones = {
    sand:      ['#E9D6B0', '#D9BC85'],
    terracotta:['#E8C9BC', '#D89B82'],
    sage:      ['#CFDCC8', '#A8C0A2'],
    taupe:     ['#D9CDB9', '#B8A88E'],
    clay:      ['#E0BFA8', '#C49479'],
    stone:     ['#D5CFC4', '#A9A294'],
    cream:     ['#F3EAD8', '#DDCDAF'],
    olive:     ['#C9C7A2', '#9DA67A'],
  };
  const [c1, c2] = tones[tone] || tones.sand;
  return (
    <div style={{
      aspectRatio: ratio, width: '100%', borderRadius: radius,
      background: `linear-gradient(135deg, ${c1}, ${c2})`,
      position: 'relative', overflow: 'hidden',
      ...style,
    }}>
      <div style={{
        position: 'absolute', inset: 0,
        backgroundImage: `repeating-linear-gradient(45deg, rgba(255,255,255,0.10) 0 2px, transparent 2px 14px)`,
      }} />
      {label && (
        <div style={{
          position: 'absolute', left: 10, bottom: 8,
          fontFamily: FONT_MONO, fontSize: 9, color: 'rgba(40,30,20,0.55)',
          letterSpacing: 0.3, textTransform: 'lowercase',
        }}>{label}</div>
      )}
    </div>
  );
}

// Status bar at the top of any screen — wraps IOSStatusBar so children can
// just render their content area.
function StatusBar({ dark }) {
  return (
    <div style={{ position: 'absolute', top: 0, left: 0, right: 0, zIndex: 10 }}>
      <IOSStatusBar dark={dark} />
    </div>
  );
}

// Dynamic island pill overlay — IOSDevice already paints it, so this is unused.

// Standard iOS tab bar — used by Home + Marketplace.
function TabBar({ dark, active = 'home' }) {
  const C = dark ? COLORS.dark : COLORS.light;
  const items = [
    { id: 'home', label: 'Главная', icon: 'house' },
    { id: 'scan', label: 'Сканы', icon: 'camera.viewfinder' },
    { id: 'market', label: 'Маркет', icon: 'bag' },
    { id: 'profile', label: 'Профиль', icon: 'person.circle' },
  ];
  return (
    <div style={{
      position: 'absolute', bottom: 0, left: 0, right: 0, zIndex: 30,
      paddingBottom: 24, paddingTop: 8,
      background: dark ? 'rgba(21,19,15,0.78)' : 'rgba(246,242,235,0.82)',
      backdropFilter: 'blur(24px) saturate(180%)',
      WebkitBackdropFilter: 'blur(24px) saturate(180%)',
      borderTop: `0.5px solid ${C.hairline}`,
      display: 'flex', justifyContent: 'space-around',
    }}>
      {items.map(it => {
        const on = active === it.id;
        return (
          <div key={it.id} style={{
            display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3,
            padding: '4px 12px', minWidth: 56,
            color: on ? C.terracotta : C.onSurfaceFaint,
          }}>
            <Icon name={on ? it.icon + '.fill' : it.icon} size={24} strokeWidth={1.8} />
            <div style={{
              fontFamily: FONT_TEXT, fontSize: 10, fontWeight: on ? 600 : 500,
              letterSpacing: 0.1, lineHeight: '12px',
            }}>{it.label}</div>
          </div>
        );
      })}
    </div>
  );
}

// Primary button (terracotta) + secondary.
function PrimaryButton({ children, dark, style, full = true }) {
  const C = dark ? COLORS.dark : COLORS.light;
  return (
    <div style={{
      background: C.terracotta, color: '#fff',
      padding: '15px 20px', borderRadius: 14,
      textAlign: 'center', width: full ? '100%' : 'auto',
      fontFamily: FONT_TEXT, fontSize: 17, fontWeight: 600,
      letterSpacing: -0.43, boxSizing: 'border-box',
      boxShadow: `0 4px 12px ${dark ? 'rgba(209,127,98,0.28)' : 'rgba(194,103,74,0.22)'}`,
      ...style,
    }}>{children}</div>
  );
}
function SecondaryButton({ children, dark, style, full = true }) {
  const C = dark ? COLORS.dark : COLORS.light;
  return (
    <div style={{
      background: dark ? 'rgba(241,236,226,0.08)' : 'rgba(28,25,22,0.05)',
      color: C.onSurface,
      padding: '15px 20px', borderRadius: 14,
      textAlign: 'center', width: full ? '100%' : 'auto',
      fontFamily: FONT_TEXT, fontSize: 17, fontWeight: 600,
      letterSpacing: -0.43, boxSizing: 'border-box',
      ...style,
    }}>{children}</div>
  );
}

// Marketplace badge
function MarketBadge({ market = 'ozon', dark }) {
  if (market === 'ozon') {
    return <Chip bg="rgba(0,90,210,0.92)" color="#fff">OZON</Chip>;
  }
  return <Chip bg="rgba(207,21,141,0.92)" color="#fff">WB</Chip>;
}

Object.assign(window, {
  COLORS, FONT_DISPLAY, FONT_TEXT, FONT_MONO, TYPE, typeStyle, fmtRub,
  Icon, Chip, softShadow, PhotoSlot, StatusBar, TabBar,
  PrimaryButton, SecondaryButton, MarketBadge,
});
