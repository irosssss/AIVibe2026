// AR Designer — 2 states. Standard view + approval sheet open.

function ARSceneBg({ children }) {
  // Simulated camera + AR furniture overlay
  return (
    <div style={{
      position: 'absolute', inset: 0,
      background: 'linear-gradient(170deg, #6d6354 0%, #4a4339 50%, #2c2820 100%)',
    }}>
      {/* light from window */}
      <div style={{
        position: 'absolute', top: 80, left: 40, width: 200, height: 220,
        background: 'radial-gradient(ellipse, rgba(255,228,180,0.25), transparent 70%)',
        filter: 'blur(20px)',
      }} />
      {/* floor receding plane */}
      <svg width="100%" height="100%" viewBox="0 0 402 874" preserveAspectRatio="none"
        style={{ position: 'absolute', inset: 0 }} fill="none">
        <g stroke="rgba(255,255,255,0.05)" strokeWidth="1">
          {Array.from({ length: 12 }).map((_, i) => (
            <path key={i} d={`M0 ${500 + i * 35} L402 ${500 + i * 35}`} />
          ))}
        </g>
        {/* wall corner */}
        <path d="M30 200 L30 600" stroke="rgba(0,0,0,0.18)" strokeWidth="1.5" />
        <path d="M372 200 L372 600" stroke="rgba(0,0,0,0.18)" strokeWidth="1.5" />
        <path d="M30 200 L372 200" stroke="rgba(0,0,0,0.18)" strokeWidth="1.5" />
        {/* window outline */}
        <rect x="80" y="240" width="120" height="140" stroke="rgba(255,255,255,0.18)" strokeWidth="1" fill="rgba(245,225,180,0.18)" />
        <path d="M140 240 L140 380 M80 310 L200 310" stroke="rgba(255,255,255,0.15)" />
      </svg>
      {/* AR furniture — sofa, table, chair, lamp (semi-transparent w/ outline) */}
      <svg width="100%" height="100%" viewBox="0 0 402 874" preserveAspectRatio="none"
        style={{ position: 'absolute', inset: 0 }} fill="none">
        {/* sofa */}
        <g>
          <path d="M40 580 L40 510 L260 510 L260 580 Z"
            fill="rgba(216,201,170,0.55)" stroke="rgba(209,127,98,0.95)" strokeWidth="2" />
          <path d="M40 510 L25 495 L25 565 L40 580" fill="rgba(216,201,170,0.45)" stroke="rgba(209,127,98,0.95)" strokeWidth="2" />
          <path d="M260 510 L275 495 L275 565 L260 580" fill="rgba(216,201,170,0.45)" stroke="rgba(209,127,98,0.95)" strokeWidth="2" />
          <path d="M25 495 L245 495" stroke="rgba(209,127,98,0.95)" strokeWidth="2" />
        </g>
        {/* table */}
        <g>
          <ellipse cx="170" cy="700" rx="80" ry="22" fill="rgba(214,181,137,0.55)" stroke="rgba(209,127,98,0.9)" strokeWidth="2" />
          <path d="M120 718 L120 760 M220 718 L220 760 M170 720 L170 760"
            stroke="rgba(209,127,98,0.7)" strokeWidth="1.5" />
        </g>
        {/* chair right */}
        <g>
          <path d="M300 560 L300 510 L360 510 L360 580 L320 580 Z"
            fill="rgba(156,180,151,0.45)" stroke="rgba(156,180,151,0.95)" strokeWidth="2" />
          <path d="M300 510 L290 500 L290 575 L300 580" fill="rgba(156,180,151,0.4)" stroke="rgba(156,180,151,0.95)" strokeWidth="2" />
        </g>
        {/* floor lamp */}
        <g>
          <path d="M340 280 L340 580" stroke="rgba(209,127,98,0.85)" strokeWidth="1.6" />
          <ellipse cx="340" cy="270" rx="22" ry="14" fill="rgba(239,224,194,0.65)" stroke="rgba(209,127,98,0.9)" strokeWidth="2" />
          <path d="M335 580 L345 580" stroke="rgba(209,127,98,0.85)" strokeWidth="3" />
        </g>
        {/* selected indicator on sofa */}
        <rect x="22" y="490" width="256" height="95" fill="none" stroke="rgba(255,255,255,0.6)" strokeWidth="1" strokeDasharray="4 3" rx="2" />
      </svg>
      {children}
    </div>
  );
}

function ARTopBar({ title }) {
  return (
    <div style={{
      position: 'absolute', top: 54, left: 0, right: 0, zIndex: 30,
      padding: '8px 16px',
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
    }}>
      <div style={glassButton}>
        <Icon name="xmark" size={20} style={{ color: '#fff' }} strokeWidth={2.2} />
      </div>
      <div style={{
        padding: '8px 16px', borderRadius: 20,
        background: 'rgba(0,0,0,0.45)',
        backdropFilter: 'blur(20px)', WebkitBackdropFilter: 'blur(20px)',
        border: '0.5px solid rgba(255,255,255,0.15)',
        ...typeStyle('headline', { color: '#fff' }),
      }}>{title}</div>
      <div style={glassButton}>
        <Icon name="arrow.left.arrow.right" size={20} style={{ color: '#fff' }} strokeWidth={2} />
      </div>
    </div>
  );
}

const glassButton = {
  width: 40, height: 40, borderRadius: 20,
  background: 'rgba(0,0,0,0.45)',
  backdropFilter: 'blur(20px)', WebkitBackdropFilter: 'blur(20px)',
  border: '0.5px solid rgba(255,255,255,0.15)',
  display: 'flex', alignItems: 'center', justifyContent: 'center',
};

function BudgetBarSticky({ current, max, pct, danger }) {
  const color = danger ? COLORS.dark.danger : pct < 0.8 ? COLORS.dark.sage : pct < 1 ? COLORS.dark.amber : COLORS.dark.danger;
  return (
    <div style={{
      position: 'absolute', bottom: 308, left: 16, right: 16, zIndex: 40,
      padding: '10px 14px',
      background: 'rgba(0,0,0,0.55)',
      backdropFilter: 'blur(20px)', WebkitBackdropFilter: 'blur(20px)',
      border: '0.5px solid rgba(255,255,255,0.15)',
      borderRadius: 14,
      display: 'flex', alignItems: 'center', gap: 10,
    }}>
      <Icon name="wallet" size={18} style={{ color: color }} />
      <div style={{ flex: 1 }}>
        <div style={{ ...typeStyle('caption', { color: '#fff', fontWeight: 600 }) }}>
          {current} / {max} ₽
        </div>
        <div style={{ marginTop: 4, height: 4, borderRadius: 2, background: 'rgba(255,255,255,0.15)', overflow: 'hidden' }}>
          <div style={{ width: `${Math.min(pct,1)*100}%`, height: '100%', background: color }} />
        </div>
      </div>
      <div style={{ ...typeStyle('caption', { color: 'rgba(255,255,255,0.7)' }) }}>{Math.round(pct*100)}%</div>
    </div>
  );
}

const FURNITURE = [
  { title: 'Диван IKEA Скандинавия', sub: '240 см · лён', price: 45990, tone: 'sand', market: 'ozon' },
  { title: 'Стол круглый дуб',        sub: '110 см · массив', price: 12500, tone: 'taupe', market: 'wb' },
  { title: 'Кресло Хюгге',            sub: 'букле, светлое', price: 18500, tone: 'sage', market: 'wb' },
  { title: 'Торшер с абажуром',       sub: '165 см · ткань',  price: 8990,  tone: 'cream', market: 'ozon' },
];

function ARBottomSheet({ expanded = false }) {
  const total = FURNITURE.reduce((s, f) => s + f.price, 0);
  return (
    <div style={{
      position: 'absolute', bottom: 0, left: 0, right: 0, zIndex: 50,
      height: expanded ? 540 : 280,
      borderTopLeftRadius: 24, borderTopRightRadius: 24,
      background: 'rgba(31,28,23,0.88)',
      backdropFilter: 'blur(28px) saturate(180%)', WebkitBackdropFilter: 'blur(28px) saturate(180%)',
      border: '0.5px solid rgba(255,255,255,0.12)',
      paddingBottom: 30,
    }}>
      {/* drag handle */}
      <div style={{ display: 'flex', justifyContent: 'center', padding: '8px 0 6px' }}>
        <div style={{ width: 36, height: 5, borderRadius: 3, background: 'rgba(255,255,255,0.3)' }} />
      </div>

      <div style={{ padding: '4px 16px 10px', display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
        <div style={{ ...typeStyle('title3', { color: '#fff' }) }}>В подборке · {FURNITURE.length}</div>
        <div style={{ ...typeStyle('callout', { color: 'rgba(255,255,255,0.6)' }) }}>{fmtRub(total)}</div>
      </div>

      {expanded ? (
        // Expanded list
        <div style={{ padding: '0 16px', display: 'flex', flexDirection: 'column', gap: 8 }}>
          {FURNITURE.map((f, i) => (
            <div key={i} style={{
              display: 'flex', alignItems: 'center', gap: 12,
              background: 'rgba(255,255,255,0.06)',
              borderRadius: 14, padding: 10,
            }}>
              <div style={{ width: 56, flexShrink: 0 }}>
                <PhotoSlot tone={f.tone} ratio="1 / 1" radius={10} />
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                  <MarketBadge market={f.market} />
                  <div style={{ ...typeStyle('caption', { color: 'rgba(255,255,255,0.5)' }) }}>{f.sub}</div>
                </div>
                <div style={{ ...typeStyle('headline', { color: '#fff', marginTop: 4 }) }}>{f.title}</div>
                <div style={{ ...typeStyle('callout', { color: '#fff', fontWeight: 600, marginTop: 2 }) }}>{fmtRub(f.price)}</div>
              </div>
              <Icon name="trash" size={18} style={{ color: 'rgba(255,255,255,0.5)' }} />
            </div>
          ))}
          <div style={{
            marginTop: 6, padding: '12px 14px', borderRadius: 12,
            background: 'rgba(255,255,255,0.04)',
            display: 'flex', justifyContent: 'space-between', alignItems: 'center',
          }}>
            <div style={{ ...typeStyle('body', { color: '#fff' }) }}>Итого</div>
            <div style={{ ...typeStyle('title3', { color: '#fff' }) }}>{fmtRub(total)}</div>
          </div>
          <div style={{ marginTop: 4 }}>
            <PrimaryButton dark>Добавить в корзину</PrimaryButton>
          </div>
        </div>
      ) : (
        // Collapsed horizontal carousel
        <div style={{ padding: '0 16px', display: 'flex', gap: 10, overflow: 'hidden' }}>
          {FURNITURE.map((f, i) => (
            <div key={i} style={{
              width: 154, flexShrink: 0,
              background: 'rgba(255,255,255,0.06)',
              borderRadius: 14, padding: 8,
            }}>
              <div style={{ position: 'relative' }}>
                <PhotoSlot tone={f.tone} ratio="4 / 3" radius={10} />
                <div style={{ position: 'absolute', top: 6, left: 6 }}>
                  <MarketBadge market={f.market} />
                </div>
              </div>
              <div style={{
                ...typeStyle('caption', { color: '#fff', fontWeight: 600 }),
                marginTop: 6, lineHeight: '16px',
                display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden',
                minHeight: 32,
              }}>{f.title}</div>
              <div style={{ ...typeStyle('callout', { color: '#fff', fontWeight: 600, marginTop: 2 }) }}>{fmtRub(f.price)}</div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function FAB() {
  return (
    <div style={{
      position: 'absolute', bottom: 296, right: 16, zIndex: 45,
      width: 52, height: 52, borderRadius: 26,
      background: COLORS.dark.terracotta, color: '#fff',
      boxShadow: '0 8px 24px rgba(0,0,0,0.5)',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
    }}>
      <Icon name="plus" size={24} strokeWidth={2.4} />
    </div>
  );
}

// ─── STATE 1: AR with furniture + half sheet + green budget ────────────────
function ARStandard() {
  return (
    <div style={{
      width: 402, height: 874, position: 'relative', overflow: 'hidden',
      background: '#000',
    }}>
      <ARSceneBg />
      <StatusBar dark />
      <ARTopBar title="Гостиная · Скандинавский" />
      <BudgetBarSticky current="245 000" max="350 000" pct={0.70} />
      <FAB />
      <ARBottomSheet expanded={false} />
      <div style={{
        position: 'absolute', bottom: 8, left: 0, right: 0, zIndex: 60,
        display: 'flex', justifyContent: 'center',
      }}>
        <div style={{ width: 139, height: 5, borderRadius: 100, background: 'rgba(255,255,255,0.7)' }} />
      </div>
    </div>
  );
}

// ─── STATE 2: Approval sheet open ──────────────────────────────────────────
function ARApproval() {
  const total = FURNITURE.reduce((s, f) => s + f.price, 0);
  return (
    <div style={{
      width: 402, height: 874, position: 'relative', overflow: 'hidden', background: '#000',
    }}>
      <ARSceneBg />
      <StatusBar dark />
      {/* dim overlay */}
      <div style={{
        position: 'absolute', inset: 0, zIndex: 40,
        background: 'rgba(0,0,0,0.45)',
      }} />

      {/* Approval sheet */}
      <div style={{
        position: 'absolute', bottom: 0, left: 0, right: 0, zIndex: 50,
        borderTopLeftRadius: 24, borderTopRightRadius: 24,
        background: COLORS.dark.surface,
        paddingBottom: 30,
        boxShadow: '0 -20px 60px rgba(0,0,0,0.5)',
      }}>
        <div style={{ display: 'flex', justifyContent: 'center', padding: '8px 0 4px' }}>
          <div style={{ width: 36, height: 5, borderRadius: 3, background: 'rgba(255,255,255,0.25)' }} />
        </div>
        <div style={{ padding: '14px 16px 8px' }}>
          <div style={{ ...typeStyle('caption', { color: COLORS.dark.terracotta, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.8 }) }}>
            Подтверждение перед оплатой
          </div>
          <div style={{ ...typeStyle('title2', { color: '#fff', marginTop: 4 }) }}>4 товара в Ozon</div>
          <div style={{ ...typeStyle('callout', { color: 'rgba(255,255,255,0.6)', marginTop: 4 }) }}>
            После подтверждения откроется приложение Ozon с готовой корзиной.
          </div>
        </div>

        <div style={{ padding: '8px 16px', display: 'flex', flexDirection: 'column', gap: 8 }}>
          {FURNITURE.map((f, i) => (
            <div key={i} style={{
              display: 'flex', alignItems: 'center', gap: 12,
              background: 'rgba(255,255,255,0.04)',
              borderRadius: 12, padding: 10,
            }}>
              <div style={{ width: 48, flexShrink: 0 }}>
                <PhotoSlot tone={f.tone} ratio="1 / 1" radius={8} />
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ ...typeStyle('callout', { color: '#fff', fontWeight: 500 }), lineHeight: '18px' }}>{f.title}</div>
                <div style={{ ...typeStyle('caption', { color: 'rgba(255,255,255,0.5)', marginTop: 2 }) }}>{f.sub}</div>
              </div>
              <div style={{ ...typeStyle('callout', { color: '#fff', fontWeight: 600 }) }}>{fmtRub(f.price)}</div>
            </div>
          ))}
        </div>

        <div style={{
          padding: '12px 16px', display: 'flex', flexDirection: 'column', gap: 6,
          borderTop: `0.5px solid ${COLORS.dark.hairline}`, marginTop: 10,
        }}>
          <div style={{ display: 'flex', justifyContent: 'space-between' }}>
            <div style={{ ...typeStyle('callout', { color: 'rgba(255,255,255,0.6)' }) }}>Товары</div>
            <div style={{ ...typeStyle('callout', { color: '#fff' }) }}>{fmtRub(total)}</div>
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between' }}>
            <div style={{ ...typeStyle('callout', { color: 'rgba(255,255,255,0.6)' }) }}>Доставка</div>
            <div style={{ ...typeStyle('callout', { color: '#fff' }) }}>от 590 ₽</div>
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 4 }}>
            <div style={{ ...typeStyle('headline', { color: '#fff' }) }}>Итого</div>
            <div style={{ ...typeStyle('title2', { color: '#fff' }) }}>{fmtRub(total + 590)}</div>
          </div>
        </div>

        <div style={{ padding: '8px 16px 0', display: 'flex', flexDirection: 'column', gap: 8 }}>
          <PrimaryButton dark>
            Подтвердить · открыть Ozon
          </PrimaryButton>
          <div style={{
            textAlign: 'center', padding: '10px',
            ...typeStyle('callout', { color: 'rgba(255,255,255,0.7)' }),
          }}>Отмена</div>
        </div>
      </div>

      <div style={{
        position: 'absolute', bottom: 8, left: 0, right: 0, zIndex: 60,
        display: 'flex', justifyContent: 'center',
      }}>
        <div style={{ width: 139, height: 5, borderRadius: 100, background: 'rgba(255,255,255,0.7)' }} />
      </div>
    </div>
  );
}

Object.assign(window, { ARStandard, ARApproval });
