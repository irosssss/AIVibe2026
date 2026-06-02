// Product detail screen — light + dark.

function ProductDetail({ dark = false }) {
  const C = dark ? COLORS.dark : COLORS.light;

  return (
    <div style={{
      width: 402, height: 874, background: C.bg, color: C.onSurface, position: 'relative', overflow: 'hidden',
    }}>
      <StatusBar dark={dark} />

      {/* Floating top bar overlay */}
      <div style={{
        position: 'absolute', top: 60, left: 0, right: 0, zIndex: 20,
        padding: '0 16px', display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      }}>
        <div style={pillBtn(dark)}><Icon name="chevron.left" size={20} strokeWidth={2.4} /></div>
        <div style={{ display: 'flex', gap: 8 }}>
          <div style={pillBtn(dark)}><Icon name="square.and.arrow.up" size={18} /></div>
          <div style={pillBtn(dark)}><Icon name="heart.fill" size={18} style={{ color: C.terracotta }} /></div>
        </div>
      </div>

      {/* scrollable content */}
      <div style={{
        position: 'absolute', inset: 0, paddingBottom: 110, overflow: 'hidden',
      }}>
        {/* Hero photo */}
        <div style={{ position: 'relative', height: 384 }}>
          <PhotoSlot tone="sand" ratio={null} label="фото товара · ozon" radius={0}
            style={{ aspectRatio: 'auto', width: '100%', height: '100%', borderRadius: 0 }} />
          <div style={{
            position: 'absolute', top: 64, left: 16,
          }}>
            <Chip bg="rgba(0,90,210,0.95)" color="#fff" style={{ padding: '5px 10px', fontSize: 12 }}>OZON</Chip>
          </div>
          {/* page dots */}
          <div style={{
            position: 'absolute', bottom: 16, left: '50%', transform: 'translateX(-50%)',
            display: 'flex', gap: 6,
          }}>
            {[0,1,2,3,4].map(i => (
              <div key={i} style={{
                width: i === 0 ? 18 : 6, height: 6, borderRadius: 3,
                background: i === 0 ? 'rgba(255,255,255,0.95)' : 'rgba(255,255,255,0.45)',
                transition: 'all 0.2s',
              }} />
            ))}
          </div>
        </div>

        {/* Body content card overlapping bottom of hero */}
        <div style={{
          background: C.bg,
          marginTop: -20, position: 'relative',
          borderTopLeftRadius: 20, borderTopRightRadius: 20,
          padding: '20px 16px 0',
        }}>
          {/* Title block */}
          <div>
            <div style={{ ...typeStyle('caption', { color: C.onSurfaceMuted }) }}>IKEA · Угловой диван</div>
            <div style={{ ...typeStyle('title2', { color: C.onSurface, marginTop: 4 }) }}>
              Скандинавия, 240 см, светлый лён
            </div>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginTop: 12 }}>
              <div style={{ ...typeStyle('title1', { color: C.onSurface }) }}>{fmtRub(45990)}</div>
              <div style={{ ...typeStyle('callout', { color: C.onSurfaceFaint, textDecoration: 'line-through' }) }}>{fmtRub(56990)}</div>
              <Chip bg={C.sage} color="#fff" style={{ padding: '4px 8px', fontSize: 11 }}>−19%</Chip>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 4, marginTop: 8 }}>
              <Icon name="star.fill" size={14} style={{ color: C.amber }} />
              <span style={{ ...typeStyle('callout', { color: C.onSurface, fontWeight: 600 }) }}>4.8</span>
              <span style={{ ...typeStyle('callout', { color: C.onSurfaceMuted }) }}>· 124 отзыва</span>
            </div>
          </div>

          {/* Fits card */}
          <div style={{
            marginTop: 20, padding: 14,
            background: C.surface, borderRadius: 18,
            boxShadow: softShadow(dark),
            display: 'flex', alignItems: 'center', gap: 12,
          }}>
            <div style={{
              width: 40, height: 40, borderRadius: 12,
              background: dark ? 'rgba(156,180,151,0.18)' : 'rgba(136,160,132,0.16)',
              color: C.sage,
              display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
            }}>
              <Icon name="checkmark.circle.fill" size={28} style={{ color: C.sage }} />
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ ...typeStyle('headline', { color: C.onSurface }) }}>Помещается в вашу гостиную</div>
              <div style={{ ...typeStyle('caption', { color: C.onSurfaceMuted, marginTop: 2 }) }}>
                Займёт 58% свободного места у окна
              </div>
            </div>
            <Icon name="chevron.right" size={16} style={{ color: C.onSurfaceFaint }} />
          </div>

          {/* Dimensions */}
          <div style={{ marginTop: 20 }}>
            <div style={{ ...typeStyle('caption', { color: C.onSurfaceMuted, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.8 }) }}>
              Размеры
            </div>
            <div style={{
              marginTop: 8, padding: '16px 14px', background: C.surface, borderRadius: 16,
              boxShadow: softShadow(dark),
              display: 'flex', alignItems: 'center', gap: 14,
            }}>
              <div style={{
                width: 36, height: 36, borderRadius: 10,
                background: C.sandSoft, color: C.terracotta,
                display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
              }}>
                <Icon name="ruler" size={20} />
              </div>
              <div style={{ display: 'flex', flex: 1, gap: 18 }}>
                {[['Ш', '240'], ['Г', '95'], ['В', '82']].map(([k, v], i) => (
                  <div key={i}>
                    <div style={{ ...typeStyle('caption', { color: C.onSurfaceMuted }) }}>{k}</div>
                    <div style={{
                      ...typeStyle('title3', { color: C.onSurface, fontFamily: FONT_DISPLAY }),
                      marginTop: 2,
                    }}>{v}<span style={{ fontSize: 13, color: C.onSurfaceMuted, fontWeight: 400, marginLeft: 2 }}>см</span></div>
                  </div>
                ))}
              </div>
            </div>
          </div>

          {/* AI о товаре */}
          <div style={{ marginTop: 20 }}>
            <div style={{ ...typeStyle('caption', { color: C.onSurfaceMuted, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.8 }) }}>
              AI о товаре
            </div>
            <div style={{
              marginTop: 8, padding: 14, background: C.surface, borderRadius: 18,
              boxShadow: softShadow(dark),
              display: 'flex', gap: 12,
            }}>
              <div style={{
                width: 32, height: 32, borderRadius: 16, flexShrink: 0,
                background: `linear-gradient(135deg, ${C.sandSoft}, ${C.terracottaSoft})`,
                color: C.terracotta,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}>
                <Icon name="sparkles" size={18} />
              </div>
              <div style={{ flex: 1 }}>
                <div style={{ ...typeStyle('body', { color: C.onSurface }) }}>
                  Этот диван подходит к скандинавскому стилю вашей гостиной. Светлая льняная обивка визуально расширит пространство. Подушки можно стирать.
                </div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 8 }}>
                  <Icon name="arrow.left.arrow.right" size={10} style={{ color: C.onSurfaceFaint }} />
                  <div style={{ ...typeStyle('caption', { color: C.onSurfaceFaint, fontSize: 11 }) }}>OpenAI · design_advisor</div>
                </div>
              </div>
            </div>
          </div>

          {/* Description (collapsed) */}
          <div style={{ marginTop: 20 }}>
            <div style={{ ...typeStyle('caption', { color: C.onSurfaceMuted, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 0.8 }) }}>
              Описание
            </div>
            <div style={{
              marginTop: 8, padding: 14, background: C.surface, borderRadius: 18,
              boxShadow: softShadow(dark),
            }}>
              <div style={{
                ...typeStyle('body', { color: C.onSurface }),
                display: '-webkit-box', WebkitLineClamp: 3, WebkitBoxOrient: 'vertical', overflow: 'hidden',
              }}>
                Угловой диван-кровать с механизмом «дельфин». Обивка — лён 80%, хлопок 20%, плотность 230 г/м². Каркас из массива берёзы, наполнение — пружинный блок Bonnel плюс холлофайбер.
              </div>
              <div style={{
                ...typeStyle('callout', { color: C.terracotta, fontWeight: 600, marginTop: 8 }),
              }}>Подробнее</div>
            </div>
          </div>

          <div style={{ height: 40 }} />
        </div>
      </div>

      {/* Sticky bottom */}
      <div style={{
        position: 'absolute', bottom: 0, left: 0, right: 0, zIndex: 30,
        padding: '12px 16px 30px',
        background: dark ? 'rgba(21,19,15,0.92)' : 'rgba(246,242,235,0.94)',
        backdropFilter: 'blur(24px)', WebkitBackdropFilter: 'blur(24px)',
        borderTop: `0.5px solid ${C.hairline}`,
        display: 'flex', gap: 10,
      }}>
        <SecondaryButton dark={dark} style={{ flex: 1, padding: '14px 12px' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6 }}>
            <Icon name="camera.viewfinder" size={18} style={{ color: C.onSurface }} />
            <span>В AR</span>
          </div>
        </SecondaryButton>
        <PrimaryButton dark={dark} style={{ flex: 1.6, padding: '14px 12px' }}>
          Добавить в проект
        </PrimaryButton>
      </div>
    </div>
  );
}

function pillBtn(dark) {
  return {
    width: 36, height: 36, borderRadius: 18,
    background: dark ? 'rgba(0,0,0,0.55)' : 'rgba(255,255,255,0.85)',
    backdropFilter: 'blur(20px)', WebkitBackdropFilter: 'blur(20px)',
    border: `0.5px solid ${dark ? 'rgba(255,255,255,0.15)' : 'rgba(0,0,0,0.06)'}`,
    color: dark ? '#fff' : COLORS.light.onSurface,
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    boxShadow: dark ? '0 2px 8px rgba(0,0,0,0.3)' : '0 2px 8px rgba(28,25,22,0.08)',
  };
}

Object.assign(window, { ProductDetail });
