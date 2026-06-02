// AIVibe — design canvas assembly.

function PhoneSlot({ children }) {
  return (
    <div style={{
      width: 402, height: 874,
      // The screens render their own frame; we just provide the iOS bezel
      borderRadius: 48, overflow: 'hidden',
      boxShadow: '0 30px 60px rgba(0,0,0,0.18), 0 0 0 1px rgba(0,0,0,0.10)',
      position: 'relative',
      fontFamily: FONT_TEXT, WebkitFontSmoothing: 'antialiased',
    }}>
      {children}
      {/* Dynamic island painted on top of each screen */}
      <div style={{
        position: 'absolute', top: 11, left: '50%', transform: 'translateX(-50%)',
        width: 126, height: 37, borderRadius: 24, background: '#000', zIndex: 100, pointerEvents: 'none',
      }} />
    </div>
  );
}

function AIVibeCanvas() {
  return (
    <DesignCanvas>
      <DCSection id="system" title="01 · Design system" subtitle="Цвета, типографика, базовые компоненты">
        <DCArtboard id="colors" label="Colors · light + dark" width={840} height={880}>
          <DSColors />
        </DCArtboard>
        <DCArtboard id="type" label="Typography · 8 ролей" width={700} height={620}>
          <DSType />
        </DCArtboard>
        <DCArtboard id="furniture" label="Карточка товара" width={840} height={500}>
          <DSFurniture />
        </DCArtboard>
        <DCArtboard id="voice" label="Voice & tone" width={840} height={620}>
          <VoiceCard />
        </DCArtboard>
      </DCSection>

      <DCSection id="home" title="02 · Главная" subtitle="Возврат в приложение, текущие проекты, идеи дня">
        <DCArtboard id="home-light" label="Light" width={402} height={874}>
          <PhoneSlot><HomeScreen dark={false} /></PhoneSlot>
        </DCArtboard>
        <DCArtboard id="home-dark" label="Dark" width={402} height={874}>
          <PhoneSlot><HomeScreen dark /></PhoneSlot>
        </DCArtboard>
      </DCSection>

      <DCSection id="chat" title="03 · AI Advisor" subtitle="Чат с AI-агентом-дизайнером, три состояния">
        <DCArtboard id="chat-welcome" label="1 · Welcome" width={402} height={874}>
          <PhoneSlot><ChatWelcome dark={false} /></PhoneSlot>
        </DCArtboard>
        <DCArtboard id="chat-active" label="2 · Активный разговор + approval" width={402} height={874}>
          <PhoneSlot><ChatActive dark={false} /></PhoneSlot>
        </DCArtboard>
        <DCArtboard id="chat-fallback" label="3 · Provider fallback" width={402} height={874}>
          <PhoneSlot><ChatFallback dark={false} /></PhoneSlot>
        </DCArtboard>
        <DCArtboard id="chat-dark" label="Active · dark" width={402} height={874}>
          <PhoneSlot><ChatActive dark /></PhoneSlot>
        </DCArtboard>
      </DCSection>

      <DCSection id="scan" title="04 · RoomScan" subtitle="LiDAR-сканирование комнаты, три экрана flow">
        <DCArtboard id="scan-intro" label="1 · Приглашение" width={402} height={874}>
          <PhoneSlot><ScanIntro dark={false} /></PhoneSlot>
        </DCArtboard>
        <DCArtboard id="scan-active" label="2 · AR view" width={402} height={874}>
          <PhoneSlot><ScanActive /></PhoneSlot>
        </DCArtboard>
        <DCArtboard id="scan-result" label="3 · Результат" width={402} height={874}>
          <PhoneSlot><ScanResult dark={false} /></PhoneSlot>
        </DCArtboard>
      </DCSection>

      <DCSection id="ar" title="05 · ARDesigner" subtitle="Расстановка мебели поверх отсканированной комнаты">
        <DCArtboard id="ar-standard" label="1 · Стандартный вид · 4 предмета" width={402} height={874}>
          <PhoneSlot><ARStandard /></PhoneSlot>
        </DCArtboard>
        <DCArtboard id="ar-approval" label="2 · Approval sheet" width={402} height={874}>
          <PhoneSlot><ARApproval /></PhoneSlot>
        </DCArtboard>
      </DCSection>

      <DCSection id="product" title="06 · Деталь товара" subtitle="Карточка из маркетплейса с AI-комментарием">
        <DCArtboard id="product-light" label="Light" width={402} height={874}>
          <PhoneSlot><ProductDetail dark={false} /></PhoneSlot>
        </DCArtboard>
        <DCArtboard id="product-dark" label="Dark" width={402} height={874}>
          <PhoneSlot><ProductDetail dark /></PhoneSlot>
        </DCArtboard>
      </DCSection>
    </DesignCanvas>
  );
}

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<AIVibeCanvas />);
