// Room scan flow — 3 screens.

// ─── Screen 1: Pre-scan invitation ─────────────────────────────────────────
function ScanIntro({ dark = false }) {
  const C = dark ? COLORS.dark : COLORS.light;
  const tips = [
    { icon: 'lightbulb',    text: 'Хорошее освещение' },
    { icon: 'figure.walk',  text: 'Двигайтесь медленно' },
    { icon: 'viewfinder',   text: 'Захватите углы' },
  ];
  return (
    <div style={{
      width: 402, height: 874, background: C.bg, color: C.onSurface, position: 'relative', overflow: 'hidden',
    }}>
      <StatusBar dark={dark} />

      {/* Close button */}
      <div style={{
        position: 'absolute', top: 60, right: 16, zIndex: 10,
        width: 32, height: 32, borderRadius: 16,
        background: dark ? 'rgba(241,236,226,0.10)' : 'rgba(28,25,22,0.06)',
        color: C.onSurfaceMuted,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <Icon name="xmark" size={18} strokeWidth={2.2} />
      </div>

      <div style={{
        position: 'absolute', top: 100, left: 0, right: 0, bottom: 0,
        padding: '20px 24px 100px',
        display: 'flex', flexDirection: 'column',
      }}>
        {/* Line-art illustration — person scanning */}
        <div style={{
          height: 240, width: '100%', borderRadius: 20,
          background: `linear-gradient(180deg, ${C.sandSoft} 0%, ${C.bg} 100%)`,
          position: 'relative', overflow: 'hidden',
        }}>
          <svg width="100%" height="100%" viewBox="0 0 320 240" preserveAspectRatio="xMidYMid meet" fill="none"
            stroke={dark ? 'rgba(241,236,226,0.55)' : 'rgba(28,25,22,0.55)'} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
            {/* room walls */}
            <path d="M40 200 L100 150 L240 150 L290 200 Z" />
            <path d="M40 80 L100 110 L240 110 L290 80" />
            <path d="M40 80 L40 200 M290 80 L290 200" />
            <path d="M100 110 L100 150 M240 110 L240 150" />
            {/* window */}
            <rect x="125" y="120" width="30" height="22" rx="1" />
            <path d="M140 120 L140 142 M125 131 L155 131" />
            {/* person silhouette */}
            <circle cx="170" cy="156" r="6" />
            <path d="M170 162 L170 188" />
            <path d="M170 170 L184 178" />
            <path d="M170 188 L162 210 M170 188 L178 210" />
            {/* phone */}
            <rect x="180" y="170" width="14" height="20" rx="2" fill={dark ? '#2A2620' : '#fff'} />
            <circle cx="187" cy="178" r="1.4" fill="currentColor" stroke="none" />
            {/* scan beam */}
            <path d="M194 178 L230 130" strokeDasharray="2 3" opacity="0.6" />
            <path d="M194 180 L235 140" strokeDasharray="2 3" opacity="0.4" />
          </svg>
        </div>

        <div style={{ marginTop: 24 }}>
          <div style={{ ...typeStyle('title1', { color: C.onSurface }) }}>Отсканируйте комнату</div>
          <div style={{ ...typeStyle('body', { color: C.onSurfaceMuted, marginTop: 8 }) }}>
            Медленно пройдитесь по периметру, направляя камеру на стены, окна и мебель. Занимает 2–3 минуты.
          </div>
        </div>

        <div style={{ marginTop: 28, display: 'flex', flexDirection: 'column', gap: 12 }}>
          {tips.map((t, i) => (
            <div key={i} style={{
              display: 'flex', alignItems: 'center', gap: 14,
              background: C.surface, borderRadius: 14, padding: '14px 16px',
              boxShadow: softShadow(dark),
            }}>
              <div style={{
                width: 36, height: 36, borderRadius: 10,
                background: C.sandSoft, color: C.terracotta,
                display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
              }}>
                <Icon name={t.icon} size={20} strokeWidth={1.8} />
              </div>
              <div style={{ flex: 1, ...typeStyle('body', { color: C.onSurface, fontWeight: 500 }) }}>{t.text}</div>
            </div>
          ))}
        </div>

        <div style={{ flex: 1 }} />

        <div style={{ display: 'flex', flexDirection: 'column', gap: 10, paddingBottom: 8 }}>
          <PrimaryButton dark={dark}>Начать сканирование</PrimaryButton>
          <div style={{
            textAlign: 'center', padding: 12,
            ...typeStyle('callout', { color: C.terracotta, fontWeight: 500 }),
          }}>Нет LiDAR? Ввести вручную</div>
        </div>
      </div>
    </div>
  );
}

// ─── Screen 2: Active scan AR view ─────────────────────────────────────────
function ScanActive() {
  return (
    <div style={{
      width: 402, height: 874, position: 'relative', overflow: 'hidden',
      // Neutral-toned simulated camera feed
      background: 'linear-gradient(165deg, #4a463d 0%, #2e2a23 60%, #1a1814 100%)',
    }}>
      {/* Simulated camera scene — room with wireframe overlay */}
      <div style={{ position: 'absolute', inset: 0 }}>
        {/* wall plane gradient */}
        <div style={{ position: 'absolute', inset: 0,
          background: 'radial-gradient(ellipse 80% 60% at 50% 45%, rgba(120,108,90,0.35), transparent 70%)' }} />

        {/* Wireframe overlay — terracotta lines on detected surfaces */}
        <svg width="100%" height="100%" viewBox="0 0 402 874" preserveAspectRatio="none"
          style={{ position: 'absolute', inset: 0 }} fill="none">
          {/* floor mesh */}
          <g stroke="rgba(209,127,98,0.6)" strokeWidth="1">
            <path d="M0 620 L402 620" />
            <path d="M0 700 L402 700" />
            <path d="M0 780 L402 780" />
            <path d="M70 500 L40 874" />
            <path d="M180 500 L160 874" />
            <path d="M290 500 L320 874" />
            <path d="M380 500 L440 874" />
          </g>
          {/* wall corner accents */}
          <g stroke="rgba(209,127,98,0.85)" strokeWidth="2" strokeLinecap="round">
            <path d="M30 200 L30 620" />
            <path d="M370 200 L370 620" />
            <path d="M30 200 L370 200" />
          </g>
          {/* detected object — sofa outline */}
          <g stroke="rgba(156,180,151,0.9)" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M90 540 L90 480 L300 480 L300 540 Z" />
            <path d="M90 480 L70 460 L70 520 L90 540" />
            <path d="M300 480 L320 460 L320 520 L300 540" />
            <path d="M70 460 L290 460" />
          </g>
          {/* sparkle dots — feature points */}
          <g fill="rgba(255,255,255,0.7)">
            {Array.from({ length: 35 }).map((_, i) => {
              const x = (i * 53) % 402;
              const y = ((i * 71) % 600) + 200;
              const r = 1 + (i % 2);
              return <circle key={i} cx={x} cy={y} r={r} />;
            })}
          </g>
        </svg>
      </div>

      <StatusBar dark />

      {/* Top status capsule */}
      <div style={{
        position: 'absolute', top: 70, left: '50%', transform: 'translateX(-50%)',
        zIndex: 10, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8,
      }}>
        <div style={{
          padding: '8px 16px', borderRadius: 20,
          background: 'rgba(0,0,0,0.55)',
          backdropFilter: 'blur(20px)', WebkitBackdropFilter: 'blur(20px)',
          border: '0.5px solid rgba(255,255,255,0.15)',
          display: 'flex', alignItems: 'center', gap: 8,
        }}>
          <div style={{ width: 6, height: 6, borderRadius: 3, background: '#D17F62', animation: 'scanPulse 1.4s infinite' }} />
          <div style={{ ...typeStyle('caption', { color: '#fff', fontWeight: 600 }) }}>Сканирую стену…</div>
        </div>
        <div style={{
          padding: '5px 12px', borderRadius: 14,
          background: 'rgba(0,0,0,0.4)',
          backdropFilter: 'blur(20px)', WebkitBackdropFilter: 'blur(20px)',
          ...typeStyle('caption', { color: 'rgba(255,255,255,0.85)' }),
        }}>Найдено: 3 стены · 5 объектов</div>
      </div>

      {/* Mini wireframe preview top-right */}
      <div style={{
        position: 'absolute', top: 144, right: 16, zIndex: 10,
        width: 88, height: 70, borderRadius: 12,
        background: 'rgba(0,0,0,0.55)',
        backdropFilter: 'blur(20px)', WebkitBackdropFilter: 'blur(20px)',
        border: '0.5px solid rgba(255,255,255,0.15)',
        padding: 6, overflow: 'hidden',
      }}>
        <svg width="100%" height="100%" viewBox="0 0 88 58" fill="none"
          stroke="rgba(209,127,98,0.9)" strokeWidth="1" strokeLinejoin="round">
          <path d="M10 50 L26 36 L70 36 L82 50 Z" />
          <path d="M10 14 L26 22 L70 22 L82 14" />
          <path d="M10 14 L10 50 M82 14 L82 50" />
          <path d="M26 22 L26 36 M70 22 L70 36" />
          <rect x="34" y="24" width="20" height="8" stroke="rgba(156,180,151,0.9)" />
        </svg>
      </div>

      {/* Big finish button */}
      <div style={{
        position: 'absolute', bottom: 60, left: '50%', transform: 'translateX(-50%)', zIndex: 10,
        display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10,
      }}>
        <div style={{
          width: 80, height: 80, borderRadius: 40,
          background: '#D17F62',
          border: '4px solid rgba(255,255,255,0.85)',
          boxShadow: '0 8px 28px rgba(0,0,0,0.4)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <Icon name="checkmark.circle.fill" size={36} style={{ color: '#fff' }} />
        </div>
        <div style={{
          padding: '4px 12px', borderRadius: 10,
          background: 'rgba(0,0,0,0.4)',
          backdropFilter: 'blur(20px)',
          ...typeStyle('caption', { color: '#fff', fontWeight: 600 }),
        }}>Завершить</div>
      </div>

      {/* Home indicator */}
      <div style={{
        position: 'absolute', bottom: 8, left: 0, right: 0, zIndex: 60,
        display: 'flex', justifyContent: 'center',
      }}>
        <div style={{ width: 139, height: 5, borderRadius: 100, background: 'rgba(255,255,255,0.7)' }} />
      </div>

      <style>{`@keyframes scanPulse { 0%,100% { opacity: 0.4 } 50% { opacity: 1 } }`}</style>
    </div>
  );
}

// ─── Screen 3: Scan result ─────────────────────────────────────────────────
function ScanResult({ dark = false }) {
  const C = dark ? COLORS.dark : COLORS.light;
  const objects = [
    { name: 'Окно', icon: 'square.stack' },
    { name: 'Дверь', icon: 'square.stack' },
    { name: 'Радиатор', icon: 'square.stack' },
    { name: 'Шкаф', icon: 'cube' },
    { name: 'Стол', icon: 'cube' },
  ];
  return (
    <div style={{
      width: 402, height: 874, background: C.bg, color: C.onSurface, position: 'relative', overflow: 'hidden',
    }}>
      <StatusBar dark={dark} />

      {/* top bar */}
      <div style={{
        position: 'absolute', top: 54, left: 0, right: 0, padding: '10px 16px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between', zIndex: 10,
      }}>
        <Icon name="chevron.left" size={22} strokeWidth={2.2} style={{ color: C.terracotta }} />
        <div style={{ ...typeStyle('headline', { color: C.onSurface }) }}>Результат</div>
        <Icon name="ellipsis" size={22} style={{ color: C.terracotta }} />
      </div>

      <div style={{
        position: 'absolute', top: 110, left: 0, right: 0, bottom: 110,
        padding: '8px 16px', overflow: 'hidden',
        display: 'flex', flexDirection: 'column', gap: 16,
      }}>
        {/* 3D wireframe model */}
        <div style={{
          height: 220, borderRadius: 20,
          background: dark
            ? `linear-gradient(160deg, #2A2620 0%, #1A1814 100%)`
            : `linear-gradient(160deg, ${C.sandSoft} 0%, ${C.bg} 100%)`,
          position: 'relative', overflow: 'hidden',
          boxShadow: softShadow(dark),
        }}>
          <svg width="100%" height="100%" viewBox="0 0 360 220" preserveAspectRatio="xMidYMid meet" fill="none"
            stroke={dark ? 'rgba(241,236,226,0.55)' : 'rgba(28,25,22,0.55)'} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
            {/* room box in iso perspective */}
            <path d="M50 180 L130 130 L290 130 L320 180 Z" stroke={C.terracotta} strokeWidth="1.8"/>
            <path d="M50 60 L130 80 L290 80 L320 60" />
            <path d="M50 60 L50 180" />
            <path d="M320 60 L320 180" />
            <path d="M130 80 L130 130" />
            <path d="M290 80 L290 130" />
            {/* Window */}
            <rect x="160" y="92" width="36" height="22" stroke={C.sage} strokeWidth="1.8"/>
            {/* Door */}
            <path d="M260 100 L280 92 L280 124 L260 130 Z" stroke={C.sage} strokeWidth="1.8"/>
            {/* sofa */}
            <path d="M80 165 L80 150 L180 150 L180 165 Z" stroke={C.sage} strokeWidth="1.8"/>
            <path d="M80 150 L70 142 L70 160 L80 165" />
            <path d="M180 150 L188 142 L188 160 L180 165" />
            {/* table */}
            <ellipse cx="230" cy="158" rx="22" ry="6" stroke={C.sage} strokeWidth="1.8"/>
          </svg>
          {/* rotate hint */}
          <div style={{
            position: 'absolute', bottom: 10, right: 10,
            padding: '4px 10px', borderRadius: 10,
            background: dark ? 'rgba(0,0,0,0.4)' : 'rgba(255,255,255,0.7)',
            backdropFilter: 'blur(8px)',
            ...typeStyle('caption', { color: C.onSurfaceMuted }),
            display: 'flex', alignItems: 'center', gap: 4,
          }}>
            <Icon name="cube" size={12} />
            <span>покрутите</span>
          </div>
        </div>

        {/* Metrics */}
        <div style={{
          display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 8,
        }}>
          {[
            { label: 'Площадь', value: '18 м²' },
            { label: 'Высота', value: '2.7 м' },
            { label: 'Объектов', value: '5' },
          ].map((m, i) => (
            <div key={i} style={{
              background: C.surface, borderRadius: 14, padding: '10px 12px',
              boxShadow: softShadow(dark),
            }}>
              <div style={{ ...typeStyle('caption', { color: C.onSurfaceMuted }) }}>{m.label}</div>
              <div style={{ ...typeStyle('title3', { color: C.onSurface, marginTop: 2 }) }}>{m.value}</div>
            </div>
          ))}
        </div>

        {/* Objects list */}
        <div style={{ flex: 1, overflow: 'hidden' }}>
          <div style={{ ...typeStyle('caption', { color: C.onSurfaceMuted, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.8, marginBottom: 8, padding: '0 4px' }) }}>
            Обнаружено
          </div>
          <div style={{
            background: C.surface, borderRadius: 16,
            boxShadow: softShadow(dark),
            overflow: 'hidden',
          }}>
            {objects.map((o, i) => (
              <div key={o.name} style={{
                display: 'flex', alignItems: 'center', gap: 12,
                padding: '12px 14px',
                borderBottom: i < objects.length - 1 ? `0.5px solid ${C.hairline}` : 'none',
              }}>
                <div style={{
                  width: 28, height: 28, borderRadius: 8,
                  background: C.sandSoft, color: C.terracotta,
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                }}>
                  <Icon name={o.icon} size={16} strokeWidth={1.8} />
                </div>
                <div style={{ flex: 1, ...typeStyle('body', { color: C.onSurface }) }}>{o.name}</div>
                <Icon name="pencil" size={16} style={{ color: C.onSurfaceFaint }} />
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Bottom actions */}
      <div style={{
        position: 'absolute', bottom: 0, left: 0, right: 0, zIndex: 30,
        padding: '12px 16px 30px',
        background: dark ? 'rgba(21,19,15,0.85)' : 'rgba(246,242,235,0.92)',
        backdropFilter: 'blur(20px)', WebkitBackdropFilter: 'blur(20px)',
        borderTop: `0.5px solid ${C.hairline}`,
        display: 'flex', gap: 10,
      }}>
        <SecondaryButton dark={dark} style={{ flex: 1 }}>Пересканировать</SecondaryButton>
        <PrimaryButton dark={dark} style={{ flex: 1.4 }}>Продолжить</PrimaryButton>
      </div>
    </div>
  );
}

Object.assign(window, { ScanIntro, ScanActive, ScanResult });
