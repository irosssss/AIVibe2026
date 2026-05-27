// Voice & tone card — AI writing style guidelines as an artboard.

function VoiceCard() {
  const C = COLORS.light;
  const yes = [
    'Для гостиной 18 м² в скандинавском стиле подойдёт угловой диван до 2.4 м шириной. Покажу 5 вариантов от 35 до 65 тысяч.',
    'Этот стол займёт 60% свободного места. Проход к окну сузится до 65 см — это меньше комфортного минимума 70 см. Предложить альтернативы?',
    'Не нашёл диван этой модели в Москве. Есть аналог у того же бренда — на 8 000 дешевле. Показать?',
  ];
  const no = [
    'Замечательный выбор! Я очень рад помочь вам с этим прекрасным проектом.',
    'Этот стиль сейчас в тренде и очень популярен.',
    'Подберём для вас идеальное решение.',
  ];
  const rules = [
    ['Обращение', 'на «вы», вежливо, не подобострастно'],
    ['Длина', 'короткие предложения, без канцелярита'],
    ['Точность', 'конкретные цифры — не «недорого»'],
    ['Честность', 'если не уверен — говорит «не уверен»'],
    ['Тон', 'опытный дизайнер-консультант, не продавец'],
    ['Эмодзи', 'нет'],
  ];
  return (
    <div style={{
      width: 840, padding: '28px 32px', background: C.surface,
      borderRadius: 20, boxShadow: softShadow(false),
      display: 'flex', flexDirection: 'column', gap: 20,
    }}>
      <div>
        <div style={{ ...typeStyle('caption', { color: C.onSurfaceMuted, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.8 }) }}>Voice & tone</div>
        <div style={{ ...typeStyle('title1', { color: C.onSurface, marginTop: 4 }) }}>Как пишет AI</div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 12 }}>
        {rules.map(([k, v]) => (
          <div key={k} style={{
            padding: '12px 14px', borderRadius: 14,
            background: C.bgSubtle,
          }}>
            <div style={{ ...typeStyle('caption', { color: C.terracotta, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.6 }) }}>{k}</div>
            <div style={{ ...typeStyle('callout', { color: C.onSurface, marginTop: 4 }) }}>{v}</div>
          </div>
        ))}
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 8 }}>
            <Icon name="checkmark.circle.fill" size={16} style={{ color: C.sage }} />
            <div style={{ ...typeStyle('headline', { color: C.onSurface }) }}>Так — да</div>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {yes.map((t, i) => (
              <div key={i} style={{
                background: 'rgba(136,160,132,0.10)',
                border: `0.5px solid rgba(136,160,132,0.35)`,
                borderRadius: 12, padding: '10px 12px',
                ...typeStyle('body', { color: C.onSurface, fontSize: 15 }),
                lineHeight: '20px',
              }}>{t}</div>
            ))}
          </div>
        </div>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 8 }}>
            <Icon name="xmark.circle.fill" size={16} style={{ color: C.danger }} />
            <div style={{ ...typeStyle('headline', { color: C.onSurface }) }}>Так — нет</div>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {no.map((t, i) => (
              <div key={i} style={{
                background: 'rgba(181,80,58,0.08)',
                border: `0.5px solid rgba(181,80,58,0.30)`,
                borderRadius: 12, padding: '10px 12px',
                ...typeStyle('body', { color: C.onSurfaceMuted, fontSize: 15, textDecoration: 'line-through' }),
                lineHeight: '20px',
              }}>{t}</div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { VoiceCard });
