// AI Advisor chat screens — 3 states.

const W = 402;
const H = 874;

// ─── Shared chat chrome ────────────────────────────────────────────────────
function ChatTopBar({ dark, skill = 'design_advisor', thinking = false }) {
  const C = dark ? COLORS.dark : COLORS.light;
  return (
    <div style={{
      position: 'absolute', top: 54, left: 0, right: 0, zIndex: 20,
      background: dark ? 'rgba(21,19,15,0.85)' : 'rgba(246,242,235,0.88)',
      backdropFilter: 'blur(24px) saturate(180%)',
      WebkitBackdropFilter: 'blur(24px) saturate(180%)',
      borderBottom: `0.5px solid ${C.hairline}`,
    }}>
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '10px 16px 12px',
      }}>
        <div style={{ width: 40, display: 'flex', justifyContent: 'flex-start', color: C.terracotta }}>
          <Icon name="chevron.left" size={22} strokeWidth={2.2} />
        </div>
        <div style={{ flex: 1, textAlign: 'center' }}>
          <div style={{ ...typeStyle('headline', { color: C.onSurface }) }}>AI-помощник</div>
          <div style={{ ...typeStyle('caption', { color: C.onSurfaceMuted, marginTop: 1 }) }}>
            <span style={{ fontFamily: FONT_MONO, fontSize: 11 }}>{skill}</span>
          </div>
        </div>
        <div style={{ width: 40, display: 'flex', justifyContent: 'flex-end', color: C.onSurfaceMuted }}>
          <Icon name="info.circle" size={22} />
        </div>
      </div>
      {thinking && (
        <div style={{
          height: 2, width: '100%',
          background: dark ? 'rgba(241,236,226,0.06)' : 'rgba(28,25,22,0.05)',
          position: 'relative', overflow: 'hidden',
        }}>
          <div style={{
            position: 'absolute', top: 0, bottom: 0,
            width: '40%', background: C.terracotta,
            animation: 'thinkSlide 1.6s ease-in-out infinite',
          }} />
        </div>
      )}
    </div>
  );
}

function Composer({ dark, placeholder = 'Опишите вашу идею...', showBudgetBar = false, budget }) {
  const C = dark ? COLORS.dark : COLORS.light;
  return (
    <div style={{
      position: 'absolute', bottom: 0, left: 0, right: 0, zIndex: 30,
    }}>
      {showBudgetBar && budget && (
        <div style={{
          margin: '0 16px 8px', padding: '10px 14px',
          background: dark ? 'rgba(31,28,23,0.82)' : 'rgba(255,252,246,0.92)',
          backdropFilter: 'blur(20px)', WebkitBackdropFilter: 'blur(20px)',
          borderRadius: 14, boxShadow: softShadow(dark),
          display: 'flex', alignItems: 'center', gap: 10,
        }}>
          <Icon name="wallet" size={18} style={{ color: C.sage }} />
          <div style={{ flex: 1 }}>
            <div style={{ ...typeStyle('caption', { color: C.onSurface, fontWeight: 600 }) }}>
              {budget.current} / {budget.max} ₽
            </div>
            <div style={{ marginTop: 4 }}>
              <ProgressBar dark={dark} pct={budget.pct} color={budget.pct < 0.8 ? C.sage : budget.pct < 1 ? C.amber : C.danger} height={4} />
            </div>
          </div>
          <div style={{ ...typeStyle('caption', { color: C.onSurfaceMuted }) }}>{Math.round(budget.pct*100)}%</div>
        </div>
      )}
      <div style={{
        background: dark ? 'rgba(21,19,15,0.85)' : 'rgba(246,242,235,0.92)',
        backdropFilter: 'blur(24px)', WebkitBackdropFilter: 'blur(24px)',
        borderTop: `0.5px solid ${C.hairline}`,
        padding: '8px 12px 30px',
        display: 'flex', alignItems: 'flex-end', gap: 8,
      }}>
        <div style={{
          width: 36, height: 36, borderRadius: 18,
          background: dark ? 'rgba(241,236,226,0.08)' : 'rgba(28,25,22,0.06)',
          color: C.onSurfaceMuted,
          display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
        }}>
          <Icon name="paperclip" size={20} />
        </div>
        <div style={{
          flex: 1, minHeight: 36, borderRadius: 18,
          background: C.surface,
          border: `0.5px solid ${C.divider}`,
          padding: '8px 14px',
          ...typeStyle('body', { color: C.onSurfaceMuted }),
          lineHeight: '20px',
        }}>{placeholder}</div>
        <div style={{
          width: 36, height: 36, borderRadius: 18,
          background: C.terracotta, color: '#fff',
          display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
        }}>
          <Icon name="paperplane.fill" size={18} />
        </div>
      </div>
    </div>
  );
}

// ─── Bubbles ───────────────────────────────────────────────────────────────
function UserBubble({ dark, children }) {
  const C = dark ? COLORS.dark : COLORS.light;
  return (
    <div style={{ display: 'flex', justifyContent: 'flex-end', padding: '0 16px' }}>
      <div style={{
        maxWidth: '80%',
        background: C.terracotta, color: '#fff',
        padding: '10px 14px',
        borderRadius: 18, borderBottomRightRadius: 4,
        ...typeStyle('body', { color: '#fff' }),
      }}>{children}</div>
    </div>
  );
}

function AIBubble({ dark, children, provider, streaming = false }) {
  const C = dark ? COLORS.dark : COLORS.light;
  return (
    <div style={{ padding: '0 16px', display: 'flex', flexDirection: 'column', alignItems: 'flex-start', gap: 4 }}>
      <div style={{
        maxWidth: '85%',
        background: C.surface, color: C.onSurface,
        padding: '10px 14px',
        borderRadius: 18, borderBottomLeftRadius: 4,
        boxShadow: dark ? 'none' : '0 1px 2px rgba(28,25,22,0.04)',
        border: dark ? `0.5px solid ${C.hairline}` : 'none',
        ...typeStyle('body', { color: C.onSurface }),
      }}>
        {children}
        {streaming && (
          <span style={{
            display: 'inline-block', width: 9, height: 18, marginLeft: 2,
            background: C.onSurface, verticalAlign: 'text-bottom',
            animation: 'caretBlink 1s steps(2) infinite',
          }} />
        )}
      </div>
      {provider && (
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, paddingLeft: 4 }}>
          <Icon name="arrow.left.arrow.right" size={10} style={{ color: C.onSurfaceFaint }} />
          <div style={{ ...typeStyle('caption', { color: C.onSurfaceFaint, fontSize: 11 }) }}>{provider}</div>
        </div>
      )}
    </div>
  );
}

// ─── Inline rich cards ─────────────────────────────────────────────────────
function InlineFurniture({ dark, items }) {
  const C = dark ? COLORS.dark : COLORS.light;
  return (
    <div style={{
      padding: '0 16px',
      display: 'flex', gap: 10, overflowX: 'hidden',
    }}>
      {items.map((it, i) => (
        <div key={i} style={{
          width: 180, flexShrink: 0,
          background: C.surface, borderRadius: 16, padding: 10,
          boxShadow: softShadow(dark),
          display: 'flex', flexDirection: 'column', gap: 8,
        }}>
          <div style={{ position: 'relative' }}>
            <PhotoSlot tone={it.tone} ratio="4 / 3" radius={10} />
            <div style={{ position: 'absolute', top: 6, left: 6 }}>
              <MarketBadge market={it.market} />
            </div>
          </div>
          <div style={{
            ...typeStyle('caption', { color: C.onSurface, fontWeight: 600 }),
            lineHeight: '17px', minHeight: 34,
            display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden',
          }}>{it.title}</div>
          <div style={{ ...typeStyle('headline', { color: C.onSurface }) }}>{fmtRub(it.price)}</div>
        </div>
      ))}
    </div>
  );
}

function ApprovalCard({ dark }) {
  const C = dark ? COLORS.dark : COLORS.light;
  return (
    <div style={{ padding: '0 16px' }}>
      <div style={{
        background: C.surface, borderRadius: 18,
        border: `1px solid ${C.sandSoft}`,
        boxShadow: softShadow(dark),
        padding: 14,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
          <div style={{
            width: 24, height: 24, borderRadius: 12,
            background: C.sandSoft, color: C.terracotta,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Icon name="info.circle" size={16} />
          </div>
          <div style={{ ...typeStyle('headline', { color: C.onSurface }) }}>Подтвердить действие</div>
        </div>
        <div style={{ ...typeStyle('callout', { color: C.onSurfaceMuted, marginBottom: 12 }) }}>
          Добавить диван «Скандинавия 240 см» (45 990 ₽) в проект «Гостиная». Бюджет после: 290 990 ₽ из 350 000 ₽.
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <div style={{
            flex: 1,
            background: dark ? 'rgba(241,236,226,0.08)' : 'rgba(28,25,22,0.05)',
            color: C.onSurface,
            padding: '10px 12px', borderRadius: 10,
            textAlign: 'center', ...typeStyle('callout', { fontWeight: 600 }),
          }}>Отменить</div>
          <div style={{
            flex: 1,
            background: C.terracotta, color: '#fff',
            padding: '10px 12px', borderRadius: 10,
            textAlign: 'center', ...typeStyle('callout', { color: '#fff', fontWeight: 600 }),
          }}>Подтвердить</div>
        </div>
      </div>
    </div>
  );
}

// ─── STATE 1: Welcome ──────────────────────────────────────────────────────
function ChatWelcome({ dark = false }) {
  const C = dark ? COLORS.dark : COLORS.light;
  const suggestions = [
    { icon: 'sparkles', text: 'Как выбрать стиль для гостиной?' },
    { icon: 'cube',     text: 'Что делать с маленькой кухней 8 м²?' },
    { icon: 'bag',      text: 'Подбери диван до 50 000 ₽' },
    { icon: 'ruler',    text: 'Какая высота столешницы оптимальна?' },
  ];
  return (
    <div style={{
      width: W, height: H, background: C.bg, color: C.onSurface, position: 'relative', overflow: 'hidden',
    }}>
      <StatusBar dark={dark} />
      <ChatTopBar dark={dark} skill="design_advisor" />

      <div style={{
        position: 'absolute', top: 140, left: 0, right: 0, bottom: 100,
        padding: '24px 16px', display: 'flex', flexDirection: 'column',
        overflow: 'hidden',
      }}>
        <div style={{
          width: 64, height: 64, borderRadius: 32,
          background: `linear-gradient(135deg, ${C.sandSoft}, ${C.terracottaSoft})`,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          color: C.terracotta, marginBottom: 16,
        }}>
          <Icon name="sparkles" size={30} strokeWidth={1.6} />
        </div>
        <div style={{ ...typeStyle('title1', { color: C.onSurface }) }}>
          Помогу с дизайном
        </div>
        <div style={{ ...typeStyle('body', { color: C.onSurfaceMuted, marginTop: 6 }) }}>
          Опишите задачу или выберите подсказку. Я предложу варианты с реальными ценами на Ozon и Wildberries.
        </div>

        <div style={{ marginTop: 28, ...typeStyle('caption', { color: C.onSurfaceMuted, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.8, marginBottom: 10 }) }}>
          Примеры вопросов
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {suggestions.map((s, i) => (
            <div key={i} style={{
              background: C.surface, borderRadius: 14, padding: '12px 14px',
              display: 'flex', alignItems: 'center', gap: 12,
              boxShadow: softShadow(dark),
            }}>
              <div style={{
                width: 28, height: 28, borderRadius: 8,
                background: C.sandSoft, color: C.terracotta,
                display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
              }}>
                <Icon name={s.icon} size={16} strokeWidth={1.8} />
              </div>
              <div style={{ flex: 1, ...typeStyle('body', { color: C.onSurface }) }}>{s.text}</div>
              <Icon name="chevron.right" size={16} style={{ color: C.onSurfaceFaint }} />
            </div>
          ))}
        </div>
      </div>

      <Composer dark={dark} />
    </div>
  );
}

// ─── STATE 2: Active conversation ──────────────────────────────────────────
function ChatActive({ dark = false }) {
  const C = dark ? COLORS.dark : COLORS.light;
  return (
    <div style={{
      width: W, height: H, background: C.bg, color: C.onSurface, position: 'relative', overflow: 'hidden',
    }}>
      <StatusBar dark={dark} />
      <ChatTopBar dark={dark} skill="furniture_matcher" />

      <div style={{
        position: 'absolute', top: 140, left: 0, right: 0, bottom: 180,
        padding: '14px 0', display: 'flex', flexDirection: 'column', gap: 12,
        overflow: 'hidden',
      }}>
        <AIBubble dark={dark}>
          Для гостиной 18 м² в скандинавском стиле подойдёт угловой диван до 2.4 м шириной. Покажу 5 вариантов от 35 до 65 тысяч.
        </AIBubble>

        <InlineFurniture dark={dark} items={[
          { title: 'Угловой диван Скандинавия, 240 см', price: 45990, tone: 'sand', market: 'ozon' },
          { title: 'Диван Хюгге, рогожка, 230 см', price: 38500, tone: 'sage', market: 'wb' },
          { title: 'Угловой Mini, лён, 220 см', price: 52900, tone: 'taupe', market: 'ozon' },
        ]} />

        <UserBubble dark={dark}>Возьми первый. Что ещё нужно?</UserBubble>

        <AIBubble dark={dark}>
          Этот диван займёт 58% свободного места у окна. Останется проход 78 см — это комфортно. Добавить в проект?
        </AIBubble>

        <ApprovalCard dark={dark} />
      </div>

      <Composer dark={dark} placeholder="Опишите вашу идею..." showBudgetBar budget={{ current: '245 000', max: '350 000', pct: 0.70 }} />
    </div>
  );
}

// ─── STATE 3: Provider fallback ────────────────────────────────────────────
function ChatFallback({ dark = false }) {
  const C = dark ? COLORS.dark : COLORS.light;
  return (
    <div style={{
      width: W, height: H, background: C.bg, color: C.onSurface, position: 'relative', overflow: 'hidden',
    }}>
      <StatusBar dark={dark} />
      <ChatTopBar dark={dark} skill="budget_optimizer" thinking />

      {/* Subtle fallback banner under top bar */}
      <div style={{
        position: 'absolute', top: 144, left: 16, right: 16, zIndex: 15,
        background: dark ? 'rgba(229,172,95,0.12)' : 'rgba(221,159,74,0.10)',
        border: `0.5px solid ${dark ? 'rgba(229,172,95,0.3)' : 'rgba(221,159,74,0.35)'}`,
        borderRadius: 10, padding: '8px 12px',
        display: 'flex', alignItems: 'center', gap: 8,
      }}>
        <Icon name="arrow.left.arrow.right" size={14} style={{ color: C.amber }} />
        <div style={{ flex: 1, ...typeStyle('caption', { color: C.onSurface }) }}>
          OpenAI недоступен — переключился на <span style={{ fontFamily: FONT_MONO, fontSize: 11 }}>GigaChat</span>
        </div>
      </div>

      <div style={{
        position: 'absolute', top: 196, left: 0, right: 0, bottom: 110,
        padding: '8px 0', display: 'flex', flexDirection: 'column', gap: 12,
        overflow: 'hidden',
      }}>
        <UserBubble dark={dark}>Какой диван возьмёшь в бюджет 50 тысяч?</UserBubble>

        <AIBubble dark={dark} provider="GigaChat">
          В 50 000 ₽ помещаются 3 модели на Ozon и 2 на WB. Самый удачный по габаритам — IKEA Скандинавия, 45 990 ₽. Остаётся запас 4 010 ₽ на доставку.
        </AIBubble>

        <AIBubble dark={dark} provider="GigaChat" streaming>
          Не нашёл точный аналог в наличии на Москве. Есть похожий у того же бренда — на 8 000 дешевле. Показать
        </AIBubble>
      </div>

      <Composer dark={dark} placeholder="Опишите вашу идею..." />

      <style>{`
        @keyframes caretBlink { 0%, 50% { opacity: 1 } 51%, 100% { opacity: 0 } }
        @keyframes thinkSlide { 0% { left: -40% } 100% { left: 100% } }
      `}</style>
    </div>
  );
}

Object.assign(window, { ChatWelcome, ChatActive, ChatFallback });
