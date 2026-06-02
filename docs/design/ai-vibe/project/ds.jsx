// Design system specimen — color palette, typography, furniture card.

function Swatch({ color, name, hex, role, dark }) {
  const C = dark ? COLORS.dark : COLORS.light;
  const isLight = isLightColor(hex);
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12,
      padding: '8px 0',
    }}>
      <div style={{
        width: 44, height: 44, borderRadius: 10,
        background: color,
        boxShadow: `inset 0 0 0 0.5px ${C.divider}`,
        flexShrink: 0,
      }} />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ ...typeStyle('callout', { color: C.onSurface, fontWeight: 600 }), lineHeight: '20px' }}>{name}</div>
        <div style={{ fontFamily: FONT_MONO, fontSize: 11, color: C.onSurfaceMuted, marginTop: 1 }}>{hex}</div>
      </div>
      {role && (
        <div style={{ ...typeStyle('caption', { color: C.onSurfaceFaint }) }}>{role}</div>
      )}
    </div>
  );
}

function isLightColor(hex) {
  if (!hex || hex[0] !== '#') return true;
  const h = hex.slice(1);
  const r = parseInt(h.slice(0,2), 16), g = parseInt(h.slice(2,4), 16), b = parseInt(h.slice(4,6), 16);
  return (r*0.299 + g*0.587 + b*0.114) > 160;
}

function ColorColumn({ mode }) {
  const C = COLORS[mode];
  const dark = mode === 'dark';
  return (
    <div style={{
      flex: 1, background: C.bg, color: C.onSurface,
      padding: '24px 20px 28px', borderRadius: 0,
      display: 'flex', flexDirection: 'column', gap: 24,
    }}>
      <div>
        <div style={{ ...typeStyle('caption', { color: C.onSurfaceMuted, textTransform: 'uppercase', letterSpacing: 1.2, fontWeight: 600 }) }}>
          {dark ? 'Dark' : 'Light'}
        </div>
        <div style={{ ...typeStyle('title2', { color: C.onSurface, marginTop: 2 }) }}>
          {dark ? 'Тёплый charcoal' : 'Тёплый off-white'}
        </div>
      </div>

      <div>
        <div style={{ ...typeStyle('caption', { color: C.onSurfaceMuted, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.8, marginBottom: 8 }) }}>Основа</div>
        <Swatch color={C.bg} name="Background" hex={C.bg} dark={dark} />
        <Swatch color={C.surface} name="Surface" hex={C.surface} dark={dark} />
        <Swatch color={C.elevated} name="Elevated" hex={C.elevated} dark={dark} />
        <Swatch color={C.onSurface} name="On-surface" hex={C.onSurface} dark={dark} />
        <Swatch color={C.onSurfaceMuted} name="Secondary text" hex={C.onSurfaceMuted} dark={dark} />
      </div>

      <div>
        <div style={{ ...typeStyle('caption', { color: C.onSurfaceMuted, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.8, marginBottom: 8 }) }}>Акценты</div>
        <Swatch color={C.terracotta} name="Terracotta · primary" hex={C.terracotta} dark={dark} />
        <Swatch color={C.sage} name="Sage · secondary" hex={C.sage} dark={dark} />
        <Swatch color={C.sand} name="Sand · tertiary" hex={C.sand} dark={dark} />
      </div>

      <div>
        <div style={{ ...typeStyle('caption', { color: C.onSurfaceMuted, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.8, marginBottom: 8 }) }}>Бюджет · семафор</div>
        <Swatch color={C.sage} name="Success · < 80 %" hex={C.sage} dark={dark} />
        <Swatch color={C.amber} name="Warning · 80–100 %" hex={C.amber} dark={dark} />
        <Swatch color={C.danger} name="Danger · > 100 %" hex={C.danger} dark={dark} />
      </div>
    </div>
  );
}

function DSColors() {
  return (
    <div style={{
      width: 840, height: 880, borderRadius: 20, overflow: 'hidden',
      display: 'flex', boxShadow: softShadow(false),
    }}>
      <ColorColumn mode="light" />
      <ColorColumn mode="dark" />
    </div>
  );
}

// ─── Typography specimen ────────────────────────────────────────────────────
function DSType() {
  const C = COLORS.light;
  const roles = [
    { key: 'largeTitle', label: 'Large Title · SF Pro Display 34/700', sample: 'Привет, Анна' },
    { key: 'title1',     label: 'Title 1 · SF Pro Display 28/700',     sample: 'Скандинавская гостиная' },
    { key: 'title2',     label: 'Title 2 · SF Pro Display 22/700',     sample: 'Идеи дня' },
    { key: 'title3',     label: 'Title 3 · SF Pro Display 20/600',     sample: 'Текущие проекты' },
    { key: 'headline',   label: 'Headline · SF Pro Text 17/600',       sample: 'Подходит для вашей комнаты' },
    { key: 'body',       label: 'Body · SF Pro Text 17/400',           sample: 'Медленно пройдитесь по периметру комнаты, направляя камеру на стены и мебель.' },
    { key: 'callout',    label: 'Callout · SF Pro Text 16/400',        sample: 'IKEA · Угловой диван · светлая ткань' },
    { key: 'caption',    label: 'Caption · SF Pro Text 13/400',        sample: '245 000 / 350 000 ₽ · бюджет проекта' },
  ];
  return (
    <div style={{
      width: 700, padding: '28px 32px', background: C.surface,
      borderRadius: 20, boxShadow: softShadow(false),
    }}>
      <div style={{ marginBottom: 20 }}>
        <div style={{ ...typeStyle('caption', { color: C.onSurfaceMuted, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.8 }) }}>Type system</div>
        <div style={{ ...typeStyle('title1', { color: C.onSurface, marginTop: 4 }) }}>SF Pro · 8 ролей</div>
        <div style={{ ...typeStyle('callout', { color: C.onSurfaceMuted, marginTop: 6 }) }}>
          Tracking: tight для заголовков, default для body. Все размеры через Dynamic Type, поддержка до Accessibility 5.
        </div>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 18 }}>
        {roles.map(r => {
          const t = TYPE[r.key];
          return (
            <div key={r.key} style={{ display: 'flex', gap: 24, alignItems: 'baseline' }}>
              <div style={{ width: 130, flexShrink: 0 }}>
                <div style={{ fontFamily: FONT_MONO, fontSize: 11, color: C.onSurfaceMuted, lineHeight: '14px' }}>{r.key}</div>
                <div style={{ fontFamily: FONT_MONO, fontSize: 10, color: C.onSurfaceFaint, marginTop: 2 }}>{t.size}/{t.weight} · lh {t.leading}</div>
              </div>
              <div style={{
                flex: 1, ...typeStyle(r.key, { color: C.onSurface }),
              }}>{r.sample}</div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

// ─── Furniture card sample ─────────────────────────────────────────────────
function FurnitureCard({ dark = false, market = 'ozon', tone = 'sand', title, brand, price, oldPrice, rating, reviews, badge, style }) {
  const C = dark ? COLORS.dark : COLORS.light;
  return (
    <div style={{
      width: 240, background: C.surface, borderRadius: 20,
      boxShadow: softShadow(dark),
      padding: 12, boxSizing: 'border-box', display: 'flex', flexDirection: 'column', gap: 10,
      ...style,
    }}>
      <div style={{ position: 'relative' }}>
        <PhotoSlot tone={tone} ratio="4 / 3" label={brand?.toLowerCase()} radius={12} />
        <div style={{ position: 'absolute', top: 8, left: 8 }}>
          <MarketBadge market={market} dark={dark} />
        </div>
        {badge && (
          <div style={{ position: 'absolute', top: 8, right: 8 }}>
            <Chip bg={C.sage} color="#fff">{badge}</Chip>
          </div>
        )}
      </div>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 4 }}>
        <div style={{
          ...typeStyle('callout', { color: C.onSurface, fontWeight: 600 }),
          display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden',
          lineHeight: '20px', minHeight: 40,
        }}>{title}</div>
        <div style={{ ...typeStyle('caption', { color: C.onSurfaceMuted }) }}>{brand}</div>
      </div>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
        <div style={{ ...typeStyle('title3', { color: C.onSurface }) }}>{fmtRub(price)}</div>
        {oldPrice && (
          <div style={{ ...typeStyle('caption', { color: C.onSurfaceFaint, textDecoration: 'line-through' }) }}>{fmtRub(oldPrice)}</div>
        )}
      </div>
      {rating && (
        <div style={{ display: 'flex', alignItems: 'center', gap: 4, color: C.onSurfaceMuted }}>
          <Icon name="star.fill" size={12} style={{ color: C.amber }} />
          <span style={{ ...typeStyle('caption', { color: C.onSurface, fontWeight: 600 }) }}>{rating}</span>
          <span style={{ ...typeStyle('caption', { color: C.onSurfaceMuted }) }}>· {reviews} отзывов</span>
        </div>
      )}
    </div>
  );
}

function DSFurniture() {
  return (
    <div style={{
      padding: '28px 32px', background: COLORS.light.bg, borderRadius: 20,
      boxShadow: softShadow(false), width: 840,
    }}>
      <div style={{ marginBottom: 18 }}>
        <div style={{ ...typeStyle('caption', { color: COLORS.light.onSurfaceMuted, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.8 }) }}>Components</div>
        <div style={{ ...typeStyle('title1', { color: COLORS.light.onSurface, marginTop: 4 }) }}>Карточка товара</div>
        <div style={{ ...typeStyle('callout', { color: COLORS.light.onSurfaceMuted, marginTop: 6 }) }}>
          20pt радиус · тень 16/8/0.08 · фото 4:3 · цена жирная · бэйдж маркетплейса top-left
        </div>
      </div>
      <div style={{ display: 'flex', gap: 20, flexWrap: 'wrap' }}>
        <FurnitureCard market="ozon" tone="sand" title="Диван угловой Скандинавия, 240 см" brand="IKEA · ткань лён" price={45990} oldPrice={56990} rating="4.8" reviews="124" badge="Подходит" />
        <FurnitureCard market="wb" tone="sage" title="Кресло мягкое Хюгге, дуб светлый" brand="Hoff · обивка букле" price={18500} rating="4.6" reviews="87" />
        <FurnitureCard market="ozon" tone="terracotta" title="Стол обеденный круглый 110 см" brand="Divan.ru · массив" price={32400} rating="4.9" reviews="56" />
        <FurnitureCard dark market="wb" tone="taupe" title="Торшер напольный с тканевым абажуром" brand="La Redoute · 1.65 м" price={8990} rating="4.7" reviews="42" style={{ background: COLORS.dark.surface }} />
      </div>
    </div>
  );
}

Object.assign(window, { DSColors, DSType, DSFurniture, FurnitureCard });
