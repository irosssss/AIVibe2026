// Print layout — each artboard on its own page, no canvas chrome.

function PhoneSlot({ children }) {
  return (
    <div style={{
      width: 402, height: 874,
      borderRadius: 48, overflow: 'hidden',
      boxShadow: '0 0 0 1px rgba(0,0,0,0.10)',
      position: 'relative',
      fontFamily: FONT_TEXT, WebkitFontSmoothing: 'antialiased',
    }}>
      {children}
      <div style={{
        position: 'absolute', top: 11, left: '50%', transform: 'translateX(-50%)',
        width: 126, height: 37, borderRadius: 24, background: '#000', zIndex: 100, pointerEvents: 'none',
      }} />
    </div>
  );
}

function Page({ section, title, subtitle, w, h, children }) {
  // Letter landscape ~ 11x8.5in. We'll just use a sized page.
  return (
    <div className="print-page" style={{
      width: '100%', minHeight: '100vh', boxSizing: 'border-box',
      padding: '32px 40px 40px',
      display: 'flex', flexDirection: 'column',
      background: '#f3efe7',
      breakAfter: 'page', pageBreakAfter: 'always',
    }}>
      <div style={{ marginBottom: 18, display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end' }}>
        <div>
          <div style={{ fontFamily: FONT_TEXT, fontSize: 11, fontWeight: 600, letterSpacing: 1.2, textTransform: 'uppercase', color: '#6E665B' }}>
            {section}
          </div>
          <div style={{ fontFamily: FONT_DISPLAY, fontSize: 26, fontWeight: 700, color: '#1C1916', marginTop: 2, letterSpacing: -0.2 }}>{title}</div>
          {subtitle && (
            <div style={{ fontFamily: FONT_TEXT, fontSize: 14, color: '#6E665B', marginTop: 4 }}>{subtitle}</div>
          )}
        </div>
        <div style={{ fontFamily: FONT_TEXT, fontSize: 11, color: '#A39B8E', letterSpacing: 0.6 }}>AIVibe · design system</div>
      </div>
      <div style={{
        flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center',
        minHeight: 0,
      }}>
        <div style={{
          // scale-to-fit handled by browser since content sized; just contain
          display: 'inline-block',
        }}>{children}</div>
      </div>
    </div>
  );
}

const PAGES = [
  { section: '01 · Design system', title: 'Цветовая палитра', subtitle: 'Светлая и тёмная темы — основа, акценты, бюджет', render: () => <DSColors /> },
  { section: '01 · Design system', title: 'Типографика', subtitle: 'SF Pro Display + SF Pro Text · 8 ролей', render: () => <DSType /> },
  { section: '01 · Design system', title: 'Карточка товара', subtitle: '20pt радиус · тень 16/8/0.08 · фото 4:3', render: () => <DSFurniture /> },
  { section: '01 · Design system', title: 'Voice & tone', subtitle: 'Стиль текстов AI-агента', render: () => <VoiceCard /> },

  { section: '02 · Главная', title: 'Home · Light', render: () => <PhoneSlot><HomeScreen dark={false} /></PhoneSlot> },
  { section: '02 · Главная', title: 'Home · Dark', render: () => <PhoneSlot><HomeScreen dark /></PhoneSlot> },

  { section: '03 · AI Advisor', title: '1 · Welcome', subtitle: 'Пустой чат с примерами вопросов', render: () => <PhoneSlot><ChatWelcome dark={false} /></PhoneSlot> },
  { section: '03 · AI Advisor', title: '2 · Активный разговор', subtitle: 'Inline-карточки товаров + approval', render: () => <PhoneSlot><ChatActive dark={false} /></PhoneSlot> },
  { section: '03 · AI Advisor', title: '3 · Provider fallback', subtitle: 'Streaming · GigaChat badge', render: () => <PhoneSlot><ChatFallback dark={false} /></PhoneSlot> },
  { section: '03 · AI Advisor', title: 'Активный разговор · Dark', render: () => <PhoneSlot><ChatActive dark /></PhoneSlot> },

  { section: '04 · RoomScan', title: '1 · Приглашение к сканированию', render: () => <PhoneSlot><ScanIntro dark={false} /></PhoneSlot> },
  { section: '04 · RoomScan', title: '2 · Активный AR-сканер', render: () => <PhoneSlot><ScanActive /></PhoneSlot> },
  { section: '04 · RoomScan', title: '3 · Результат скана', render: () => <PhoneSlot><ScanResult dark={false} /></PhoneSlot> },

  { section: '05 · ARDesigner', title: '1 · Стандартный вид', subtitle: 'Полузакрытый bottom sheet, бюджет зелёный', render: () => <PhoneSlot><ARStandard /></PhoneSlot> },
  { section: '05 · ARDesigner', title: '2 · Approval sheet', subtitle: 'Финальный список перед переходом в Ozon', render: () => <PhoneSlot><ARApproval /></PhoneSlot> },

  { section: '06 · Деталь товара', title: 'Product · Light', render: () => <PhoneSlot><ProductDetail dark={false} /></PhoneSlot> },
  { section: '06 · Деталь товара', title: 'Product · Dark', render: () => <PhoneSlot><ProductDetail dark /></PhoneSlot> },
];

function PrintBook() {
  return (
    <>
      {/* Cover */}
      <div className="print-page" style={{
        width: '100%', minHeight: '100vh', boxSizing: 'border-box',
        background: '#F6F2EB', color: '#1C1916',
        padding: '60px 60px 50px',
        display: 'flex', flexDirection: 'column', justifyContent: 'space-between',
        breakAfter: 'page', pageBreakAfter: 'always',
      }}>
        <div style={{ fontFamily: FONT_TEXT, fontSize: 13, fontWeight: 600, letterSpacing: 1.4, textTransform: 'uppercase', color: '#6E665B' }}>
          AIVibe · iOS · 2026
        </div>
        <div>
          <div style={{ fontFamily: FONT_DISPLAY, fontSize: 96, fontWeight: 700, lineHeight: 1, letterSpacing: -2, color: '#1C1916' }}>
            AIVibe
          </div>
          <div style={{ fontFamily: FONT_DISPLAY, fontSize: 32, fontWeight: 600, lineHeight: 1.2, color: '#C2674A', marginTop: 18, letterSpacing: -0.6 }}>
            AI-помощник по дизайну интерьеров
          </div>
          <div style={{ fontFamily: FONT_TEXT, fontSize: 18, color: '#6E665B', marginTop: 18, maxWidth: 700, lineHeight: 1.5 }}>
            Дизайн-система и ключевые экраны. Scandinavian-warm, SF Pro, нативный iOS-look, тёплые нейтральные тона с акцентами терракоты и шалфея.
          </div>
        </div>
        <div style={{ display: 'flex', gap: 14 }}>
          {['#C2674A', '#88A084', '#D6B589', '#DD9F4A', '#B5503A', '#F6F2EB', '#15130F'].map(c => (
            <div key={c} style={{
              width: 56, height: 56, borderRadius: 14, background: c,
              boxShadow: 'inset 0 0 0 0.5px rgba(28,25,22,0.12)',
            }} />
          ))}
        </div>
      </div>

      {PAGES.map((p, i) => (
        <Page key={i} section={p.section} title={p.title} subtitle={p.subtitle}>
          {p.render()}
        </Page>
      ))}
    </>
  );
}

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<PrintBook />);

// Auto-print after fonts, scripts, layout settle.
(async () => {
  try { if (document.fonts && document.fonts.ready) await document.fonts.ready; } catch (e) {}
  // wait an extra moment for React render + Babel
  await new Promise(r => setTimeout(r, 800));
  window.print();
})();
