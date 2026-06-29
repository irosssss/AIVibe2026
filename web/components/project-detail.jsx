/* ============================================================
   AIVibe — ДЕТАЛЬ ПРОЕКТА
   Анализ помещения · Стиль и варианты · Бюджет · Спецификация
   (каталог фабрик-партнёров) · AI-чат с дизайнером.
   Открывается из раздела «Мои проекты».
   ============================================================ */
const { useState: usePD, useEffect: usePDE, useRef: usePDR } = React;

const MP_NAME = { f1: "Дубрава", f2: "Линея" };
const TIER_NAME = { eco: "Эконом", opt: "Оптимально", prem: "Премиум" };
const FIND_ICON = { plus: (p) => <I.check {...p} />, warn: (p) => <I.info {...p} />, idea: (p) => <I.spark {...p} /> };

/* материалы/отделка по стилю — подставляются в карточки товаров, чтобы подбор
   визуально перекрашивался под выбранное направление (категории идут по порядку) */
const STYLE_MATERIALS = {
  deco:    ["велюр", "латунь", "мрамор", "рифление", "винный бархат"],
  warm:    ["лён", "тёплое дерево", "букле", "керамика", "шерсть"],
  japandi: ["светлый дуб", "графит", "ротанг", "лён", "матовый металл"],
  scandi:  ["светлый дуб", "хлопок", "белёный ясень", "мята", "фетр"],
  modern:  ["шпон", "латунь", "молдинг", "бархат", "мрамор"],
  indust:  ["чёрный металл", "дуб", "бетон", "кожа", "сталь"],
  midmod:  ["орех", "горчичный велюр", "тик", "латунь", "шерсть"],
};
const DEFAULT_MATERIALS = ["дерево", "ткань", "металл", "стекло", "текстиль"];

/* варианты расстановки мебели — выбираются внутри стиля.
   plan[] — схема сверху (x,y,w,h в %), pins[] — AR-метки на фото [left%, top%, label] */
const LAYOUTS = [
  {
    id: "window", name: "У окна", note: "Зона отдыха развёрнута к свету — диван у окна, мягкий вечерний сценарий.",
    pros: ["Максимум естественного света", "Уютная зона чтения"],
    plan: [
      { x: 14, y: 12, w: 48, h: 16, k: "seat", label: "Диван" },
      { x: 30, y: 40, w: 26, h: 26, k: "rug", label: "Ковёр" },
      { x: 36, y: 46, w: 14, h: 12, k: "table", label: "Стол" },
      { x: 70, y: 34, w: 16, h: 22, k: "accent", label: "Кресло" },
    ],
    pins: [[30, 40, "Диван"], [72, 52, "Кресло"], [48, 70, "Свет"]],
  },
  {
    id: "media", name: "Медиа-стена", note: "ТВ-зона на глухой стене напротив окон, диван — фронтально к экрану.",
    pros: ["Кино-зона на всю стену", "Чёткое зонирование"],
    plan: [
      { x: 10, y: 70, w: 60, h: 12, k: "media", label: "ТВ-стена" },
      { x: 18, y: 30, w: 46, h: 15, k: "seat", label: "Диван" },
      { x: 26, y: 50, w: 24, h: 14, k: "table", label: "Стол" },
      { x: 74, y: 30, w: 14, h: 34, k: "accent", label: "Стеллаж" },
    ],
    pins: [[36, 58, "Диван"], [62, 40, "ТВ-стена"], [80, 52, "Стеллаж"]],
  },
  {
    id: "symmetry", name: "Симметрия", note: "Центральная ось: диван по центру и парные кресла напротив.",
    pros: ["Парадная гостиная", "Баланс и порядок"],
    plan: [
      { x: 26, y: 16, w: 48, h: 15, k: "seat", label: "Диван" },
      { x: 18, y: 58, w: 16, h: 20, k: "accent", label: "Кресло" },
      { x: 66, y: 58, w: 16, h: 20, k: "accent", label: "Кресло" },
      { x: 40, y: 44, w: 20, h: 16, k: "table", label: "Стол" },
    ],
    pins: [[50, 38, "Диван"], [26, 66, "Кресло"], [72, 66, "Кресло"]],
  },
];
const LAYOUT_K = { seat: "var(--accent)", media: "var(--info)", table: "var(--accent-2)", accent: "var(--chart)", rug: "rgba(255,255,255,.12)" };

/* цена предмета с поправкой на выбранный стиль (округляем до сотен) */
const adjustPrice = (price, factor) => (price == null ? price : Math.round((price * factor) / 100) * 100);

/* детерминированный «хеш» из строки — чтобы наличие/доставка были стабильны между рендерами */
const hashStr = (s) => { let h = 0; for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0; return h; };

/* наличие + срок поставки — выводим из id/тира/отзывов (имитация ответа каталога фабрики) */
function stockInfo(item) {
  const h = hashStr(item.id);
  const mode = h % 10; // 0..9
  if (mode === 0) return { state: "order", label: "Под заказ", eta: "4–6 недель", color: "var(--faint)" };
  if (mode === 1 || mode === 2) {
    const left = 2 + (h % 5); // 2..6
    return { state: "low", label: `Осталось ${left} шт`, eta: item.mp === "f1" ? "1–2 недели" : "2–3 недели", color: "var(--accent)" };
  }
  return { state: "in", label: "На складе", eta: item.mp === "f1" ? "1–2 недели" : "2–3 недели", color: "var(--accent-2)" };
}

/* первичный выбор по одному товару из каждой категории под тариф */
function pickByTier(catalog, tier) {
  const sel = {};
  catalog.forEach((c, i) => {
    const it = c.items.find((x) => x.tier === tier) || c.items[0];
    sel[i] = it.id;
  });
  return sel;
}

function ProjectDetail({ id, onClose, initialStyle }) {
  const [data, setData] = usePD(null);
  const [styleId, setStyleId] = usePD(null);
  const [tier, setTier] = usePD("opt");
  const [sel, setSel] = usePD({});
  const [layoutId, setLayoutId] = usePD("window");
  const [chatOpen, setChatOpen] = usePD(false);

  const mainRef = usePDR(null);
  const secRefs = { analysis: usePDR(null), styles: usePDR(null), budget: usePDR(null), products: usePDR(null) };

  usePDE(() => {
    let alive = true;
    AIVibeAPI.projects.get(id).then((d) => {
      if (!alive) return;
      setData(d);
      if (d.rooms) return; // проект-квартира: смета-комплектация по комнатам (отдельный рендер)
      const match = initialStyle && d.styles.find((s) => s.id === initialStyle);
      setStyleId((match || d.styles.find((s) => s.active) || d.styles[0]).id);
      setSel(pickByTier(d.catalog, "opt"));
    });
    return () => { alive = false; };
  }, [id]);

  const goto = (key) => {
    const el = secRefs[key] && secRefs[key].current, box = mainRef.current;
    if (!el || !box) return;
    const top = el.getBoundingClientRect().top - box.getBoundingClientRect().top + box.scrollTop - 8;
    box.scrollTo({ top, behavior: "smooth" });
  };
  const applyTier = (t) => { setTier(t); if (data) setSel(pickByTier(data.catalog, t)); };
  const onAction = (a) => {
    if (!a) return;
    if (a.type === "tier") applyTier(a.value);
    else if (a.type === "style") setStyleId(a.value);
    else if (a.type === "scroll") goto(a.value);
  };

  if (!data) {
    return (
      <div className="pd-overlay" style={{ alignItems: "center", justifyContent: "center" }}>
        <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 14, color: "var(--muted)" }}>
          <span className="spin" style={{ width: 30, height: 30 }} />
          Загружаю проект и анализ помещения…
        </div>
      </div>
    );
  }

  if (data.rooms) return <RoomSpecOverlay data={data} onClose={onClose} />;

  const activeStyle = data.styles.find((s) => s.id === styleId) || data.styles[0];
  const activeLayout = LAYOUTS.find((l) => l.id === layoutId) || LAYOUTS[0];
  const factor = activeStyle.factor || 1;
  const adj = (p) => adjustPrice(p, factor);
  const mats = STYLE_MATERIALS[activeStyle.id] || DEFAULT_MATERIALS;
  const cartItems = data.catalog.map((c, i) => c.items.find((x) => x.id === sel[i])).filter(Boolean);
  const total = cartItems.reduce((s, it) => s + adj(it.price), 0);
  const oldTotal = cartItems.reduce((s, it) => s + adj(it.old || it.price), 0);

  // Движок: проверка эргономики выбранной раскладки + строки сметы для PDF
  const checks = window.AIVibeEngine ? AIVibeEngine.checkErgonomics(activeLayout, data.analysis.plan) : { findings: [], ok: true, warns: 0 };
  const specRows = data.catalog.map((c, i) => {
    const it = c.items.find((x) => x.id === sel[i]);
    return it ? { cat: c.cat, title: it.title, factory: MP_NAME[it.mp], tier: TIER_NAME[it.tier], price: adj(it.price) } : null;
  }).filter(Boolean);
  const exportPDF = () => { if (window.AIVibePDF) AIVibePDF.exportSpec({ project: data.name, styleName: activeStyle.name, rows: specRows, total, budget: data.budget, checks }); };
  const optimize = () => { if (window.AIVibeEngine) setSel(AIVibeEngine.optimizeSpec(data.catalog, data.budget, factor).selection); };

  return (
    <div className="pd-overlay" role="dialog" aria-label={"Проект: " + data.name}>
      {/* шапка */}
      <header className="pd-head">
        <button className="icon-btn" onClick={onClose} title="Назад к проектам" aria-label="Назад"><I.arrow size={18} style={{ transform: "rotate(180deg)" }} /></button>
        <div className="pd-title" style={{ flex: 1 }}>
          <h2>{data.name}</h2>
          <div className="pd-sub">{data.room} · {activeStyle.name} · {data.area} м²</div>
        </div>
        <span className="glass" style={{ display: "flex", alignItems: "center", gap: 7, padding: "7px 13px", borderRadius: 99, fontSize: 12.5, fontWeight: 700, whiteSpace: "nowrap" }}>
          <I.wallet size={15} style={{ color: "var(--accent-2)" }} />Бюджет {fmtMoney(data.budget)}
        </span>
      </header>

      <div className="pd-body">
        <div className="pd-main" ref={mainRef}>
          <StyleHero data={data} style={activeStyle} />
          <RoomAnalysis a={data.analysis} sref={secRefs.analysis} />
          <StylePicker data={data} styleId={styleId} onPick={setStyleId} sref={secRefs.styles} />
          <LayoutPicker layout={activeLayout} onPick={setLayoutId} />
          <BeforeAfter data={data} style={activeStyle} pins={activeLayout.pins} />
          <NormsCheck checks={checks} />
          <BudgetPicker data={data} tier={tier} onTier={applyTier} total={total} onOptimize={optimize} sref={secRefs.budget} />
          <ProductCatalog data={data} sel={sel} adj={adj} style={activeStyle} mats={mats} onPick={(i, idv) => setSel((s) => ({ ...s, [i]: idv }))} sref={secRefs.products} />
          <CartBar items={cartItems} total={total} oldTotal={oldTotal} budget={data.budget} style={activeStyle} onExport={exportPDF} />
        </div>

        <aside className={"pd-rail" + (chatOpen ? " open" : "")}>
          <AdvisorChat id={id} hello={data.chatHello} onAction={onAction} onClose={() => setChatOpen(false)} />
        </aside>
      </div>

      <button className="pd-chat-fab" onClick={() => setChatOpen(true)} style={{ display: chatOpen ? "none" : undefined }}><I.chat size={19} />AI-дизайнер</button>
    </div>
  );
}

/* ---------------- СМЕТА-КОМПЛЕКТАЦИЯ ПО КОМНАТАМ (реальный дизайн-проект) ---------------- */
function RoomSpecOverlay({ data, onClose }) {
  const [markup, setMarkup] = usePD(25);
  const rooms = data.rooms || [];
  const roomTotal = (r) => r.items.reduce((s, it) => s + it.price * (it.qty || 1), 0);
  const grand = rooms.reduce((s, r) => s + roomTotal(r), 0);
  const client = Math.round(grand * (1 + markup / 100));
  const itemsCount = rooms.reduce((s, r) => s + r.items.length, 0);
  const over = grand > data.budget;
  const exportPDF = () => { if (window.AIVibePDF && AIVibePDF.exportRoomSpec) AIVibePDF.exportRoomSpec({ project: data.name, area: data.area, rooms, grand, markupPct: markup, clientTotal: client, budget: data.budget }); };

  return (
    <div className="pd-overlay" role="dialog" aria-label={"Смета: " + data.name}>
      <header className="pd-head">
        <button className="icon-btn" onClick={onClose} title="Назад к проектам" aria-label="Назад"><I.arrow size={18} style={{ transform: "rotate(180deg)" }} /></button>
        <div className="pd-title" style={{ flex: 1 }}>
          <h2>{data.name}</h2>
          <div className="pd-sub">Комплектация по дизайн-проекту · {data.area} м² · {itemsCount} позиций</div>
        </div>
        <span className="glass" style={{ display: "flex", alignItems: "center", gap: 7, padding: "7px 13px", borderRadius: 99, fontSize: 12.5, fontWeight: 700, whiteSpace: "nowrap" }}>
          <I.wallet size={15} style={{ color: "var(--accent-2)" }} />Бюджет {fmtMoney(data.budget)}
        </span>
      </header>

      <div className="pd-body">
        <div className="pd-main">
          <section className="pd-section" style={{ borderBottom: "none" }}>
            <div className="pd-eyebrow"><span className="dot" />Спецификация-комплектация</div>
            <h3 className="pd-h">Смета по комнатам</h3>
            <p style={{ color: "var(--muted)", fontSize: 14.5, marginTop: 4, marginBottom: 18, maxWidth: 820, lineHeight: 1.6 }}>{data.summaryShort}</p>

            {/* наценка дизайнера: себестоимость → цена клиента */}
            <div className="glass" style={{ borderRadius: "var(--r-lg)", padding: "16px 20px", marginBottom: 22, maxWidth: 640 }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
                <span style={{ fontWeight: 700, fontSize: 14.5 }}>Наценка дизайнера</span>
                <span style={{ fontFamily: "var(--font-display)", fontWeight: 800, fontSize: 18, color: "var(--accent)" }}>{markup}%</span>
              </div>
              <input type="range" min="0" max="100" step="5" value={markup} onChange={(e) => setMarkup(+e.target.value)} className="quiz-range" style={{ marginTop: 10 }} />
              <div style={{ display: "flex", justifyContent: "space-between", marginTop: 12, fontSize: 13.5, flexWrap: "wrap", gap: 8 }}>
                <span style={{ color: "var(--muted)" }}>Себестоимость (фабрика): <b style={{ color: "var(--text)" }}>{fmtMoney(grand)}</b></span>
                <span style={{ color: "var(--muted)" }}>Для клиента: <b style={{ color: "var(--accent-2)" }}>{fmtMoney(client)}</b></span>
              </div>
            </div>

            {/* комнаты */}
            <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
              {rooms.map((r) => (
                <div key={r.name} className="glass" style={{ borderRadius: "var(--r-lg)", padding: "16px 18px" }}>
                  <div style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between", gap: 12, marginBottom: 8, flexWrap: "wrap" }}>
                    <span style={{ fontWeight: 800, fontFamily: "var(--font-display)", fontSize: 16.5 }}>{r.name}{r.area ? <span style={{ color: "var(--faint)", fontWeight: 500, fontSize: 13 }}> · {r.area} м²</span> : null}</span>
                    <span style={{ fontFamily: "var(--font-display)", fontWeight: 800, fontSize: 15 }}>{fmtMoney(roomTotal(r))}</span>
                  </div>
                  <div style={{ display: "flex", flexDirection: "column" }}>
                    {r.items.map((it, i) => (
                      <div key={i} style={{ display: "flex", alignItems: "baseline", gap: 10, padding: "7px 0", borderTop: i ? "1px solid var(--hairline)" : "none", fontSize: 13.5 }}>
                        <span style={{ flex: 1, color: "var(--text)", lineHeight: 1.4 }}>{it.title}</span>
                        <span style={{ color: "var(--faint)", whiteSpace: "nowrap", fontSize: 12 }}>{it.cat}</span>
                        <span style={{ color: "var(--muted)", whiteSpace: "nowrap", width: 28, textAlign: "right" }}>×{it.qty || 1}</span>
                        <span style={{ fontWeight: 700, whiteSpace: "nowrap", width: 96, textAlign: "right" }}>{fmtMoney(it.price * (it.qty || 1))}</span>
                      </div>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          </section>

          {/* итог (sticky) */}
          <div className="pd-cart">
            <div style={{ display: "flex", alignItems: "center", gap: 16, flexWrap: "wrap" }}>
              <div style={{ display: "flex", alignItems: "center", gap: 11 }}>
                <span style={{ width: 40, height: 40, borderRadius: 12, background: "var(--accent)", color: "#1a0d08", display: "grid", placeItems: "center", flex: "none" }}><I.layers size={20} /></span>
                <div>
                  <div style={{ fontFamily: "var(--font-display)", fontWeight: 800, fontSize: 20, lineHeight: 1 }}>{fmtMoney(grand)}</div>
                  <div style={{ fontSize: 12, color: "var(--muted)", marginTop: 3 }}>{itemsCount} позиций · {over ? <span style={{ color: "var(--accent)" }}>сверх бюджета</span> : <span style={{ color: "var(--accent-2)" }}>в рамках бюджета</span>}</div>
                </div>
              </div>
              <span className="glass" style={{ padding: "7px 12px", borderRadius: 99, fontSize: 12.5, fontWeight: 700, color: "var(--accent-2)" }}>Клиенту (+{markup}%): {fmtMoney(client)}</span>
              <div style={{ marginLeft: "auto", display: "flex", gap: 10 }}>
                <button className="btn btn-ghost" style={{ padding: "11px 16px" }} onClick={exportPDF}><I.layers size={16} />Выгрузить PDF</button>
                <button className="btn btn-primary" style={{ padding: "11px 18px" }}><I.check size={16} />Сохранить смету</button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ---------------- ГЕРОЙ (обложка + активная палитра стиля) ---------------- */
function StyleHero({ data, style }) {
  return (
    <div style={{ position: "relative", height: 188, overflow: "hidden", borderBottom: "1px solid var(--hairline)" }}>
      <Img src={PHOTOS[data.cover] || PHOTOS.living} label={data.room} style={{ position: "absolute", inset: 0 }} />
      <div style={{ position: "absolute", inset: 0, background: "linear-gradient(90deg, rgba(14,10,16,.92) 0%, rgba(14,10,16,.55) 55%, rgba(14,10,16,.2) 100%)" }} />
      <div style={{ position: "relative", height: "100%", display: "flex", flexDirection: "column", justifyContent: "center", gap: 8, padding: "0 clamp(16px,3vw,40px)", maxWidth: 560 }}>
        <span style={{ fontSize: 12, fontWeight: 700, color: "var(--accent-2)", letterSpacing: ".06em" }}>{data.analysis.scannedAt}</span>
        <div className="display" style={{ fontSize: "clamp(22px,3vw,30px)", letterSpacing: "-0.02em" }}>Стиль: {style.name}</div>
        <div style={{ color: "var(--muted)", fontSize: 14 }}>{style.mood}</div>
        <div style={{ display: "flex", gap: 7, marginTop: 4 }}>
          {style.palette.map((c, i) => <span key={i} title={c} style={{ width: 30, height: 30, borderRadius: 7, background: c, border: "1px solid rgba(255,255,255,.2)" }} />)}
        </div>
      </div>
    </div>
  );
}

/* ---------------- АНАЛИЗ ПОМЕЩЕНИЯ ---------------- */
function RoomAnalysis({ a, sref }) {
  return (
    <section className="pd-section" ref={sref}>
      <div className="pd-eyebrow"><span className="dot" />Анализ помещения · по плану и габаритам</div>
      <h3 className="pd-h">Что AIVibe увидел в комнате</h3>

      <div style={{ display: "grid", gridTemplateColumns: "minmax(220px,300px) 1fr", gap: 22, alignItems: "start", marginTop: 18 }} className="pd-an-top">
        <div className="glass" style={{ borderRadius: "var(--r-lg)", padding: 18 }}>
          <FloorPlan plan={a.plan} />
          <div style={{ marginTop: 16 }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginBottom: 7 }}>
              <span style={{ display: "flex", alignItems: "center", gap: 7, fontSize: 13, fontWeight: 700 }}><I.sun size={15} style={{ color: "var(--accent)" }} />{a.light.label}</span>
              <span style={{ fontFamily: "var(--font-display)", fontWeight: 800, fontSize: 15 }}>{a.light.score}<span style={{ fontSize: 11, color: "var(--faint)" }}>/100</span></span>
            </div>
            <div className="light-meter"><i style={{ width: a.light.score + "%" }} /></div>
            <div style={{ fontSize: 12, color: "var(--muted)", marginTop: 7 }}>{a.light.note}</div>
          </div>
        </div>

        <div className="metric-grid">
          {a.metrics.map((m) => (
            <div className="m" key={m.label}><div className="k">{m.label}</div><div className="v">{m.value}</div></div>
          ))}
        </div>
      </div>

      <p style={{ marginTop: 20, fontSize: 15.5, lineHeight: 1.7, color: "var(--muted)", maxWidth: 880, textWrap: "pretty" }}>{a.summary}</p>

      <div style={{ marginTop: 22 }}>
        <div style={{ fontSize: 13, fontWeight: 700, color: "var(--faint)", textTransform: "uppercase", letterSpacing: ".1em", marginBottom: 12 }}>Зонирование</div>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(190px,1fr))", gap: 12 }}>
          {a.zones.map((z) => (
            <div key={z.name} className="glass" style={{ borderRadius: 12, padding: "14px 16px" }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 10 }}>
                <span style={{ fontWeight: 700, fontSize: 14.5 }}>{z.name}</span>
                <span style={{ fontSize: 12.5, color: "var(--accent-2)", fontWeight: 700, whiteSpace: "nowrap" }}>{z.area}</span>
              </div>
              <div style={{ fontSize: 13, color: "var(--muted)", marginTop: 5, lineHeight: 1.4 }}>{z.note}</div>
            </div>
          ))}
        </div>
      </div>

      <div style={{ marginTop: 22, display: "flex", flexDirection: "column", gap: 9 }}>
        <div style={{ fontSize: 13, fontWeight: 700, color: "var(--faint)", textTransform: "uppercase", letterSpacing: ".1em", marginBottom: 3 }}>Выводы советника</div>
        {a.findings.map((f, i) => {
          const Ico = FIND_ICON[f.kind] || FIND_ICON.idea;
          return (
            <div key={i} className={"find " + f.kind}>
              <span className="fi"><Ico size={15} /></span>
              <span style={{ fontSize: 14, lineHeight: 1.5, color: "var(--text)" }}>{f.text}</span>
            </div>
          );
        })}
      </div>
    </section>
  );
}

/* мини-план комнаты по пропорциям w:l + окна + дверь + ориентация */
function FloorPlan({ plan }) {
  const ratio = plan.w / plan.l;
  const winLeft = plan.door === "low-left" ? "62%" : "16%";
  return (
    <div>
      <div style={{ position: "relative", width: "100%", aspectRatio: String(ratio), maxHeight: 180, margin: "0 auto" }}>
        <div className="plan-box" style={{ position: "absolute", inset: 0 }}>
          {/* окна сверху */}
          {Array.from({ length: plan.windows }).map((_, i) => (
            <span key={i} className="pl-win" style={{ top: -2, height: 4, borderRadius: 2,
              left: `${22 + i * (56 / Math.max(1, plan.windows - 0))}%`, width: `${Math.min(34, 40 / plan.windows)}%` }} />
          ))}
          {/* дверь снизу */}
          <span className="pl-door" style={{ bottom: -1, width: "22%", height: 14, borderLeft: "2px solid var(--accent)", borderRadius: "0 0 0 10px", left: winLeft }} />
          {/* солнце/ориентация у окон */}
          <span className="pl-sun" style={{ top: 8, right: 8, display: "flex", alignItems: "center", gap: 4, fontSize: 11, fontWeight: 700 }}>
            <I.sun size={14} />{plan.side}
          </span>
          {/* размеры */}
          <span className="pl-dim" style={{ bottom: 5, left: "50%", transform: "translateX(-50%)" }}>{plan.w} м</span>
          <span className="pl-dim" style={{ top: "50%", right: 5, transform: "translateY(-50%) rotate(90deg)" }}>{plan.l} м</span>
        </div>
      </div>
      <div style={{ display: "flex", gap: 16, justifyContent: "center", marginTop: 12, fontSize: 11.5, color: "var(--faint)" }}>
        <span style={{ display: "flex", alignItems: "center", gap: 5 }}><span style={{ width: 12, height: 3, background: "var(--accent-2)", borderRadius: 2 }} />Окно</span>
        <span style={{ display: "flex", alignItems: "center", gap: 5 }}><span style={{ width: 10, height: 8, borderLeft: "2px solid var(--accent)", borderBottom: "2px solid var(--accent)" }} />Вход</span>
      </div>
    </div>
  );
}

/* ---------------- СТИЛЬ И ВАРИАНТЫ ---------------- */
function StylePicker({ data, styleId, onPick, sref }) {
  return (
    <section className="pd-section" ref={sref}>
      <div className="pd-eyebrow"><span className="dot" />Стиль и варианты</div>
      <h3 className="pd-h">Направления под эту комнату</h3>
      <p style={{ color: "var(--muted)", fontSize: 14.5, marginTop: 4, marginBottom: 18, maxWidth: 720 }}>
        AI подобрал стили под пропорции, свет и назначение помещения. Выберите направление — палитра и акценты обновятся, а рядом видно ориентировочное влияние на бюджет.
      </p>
      <div className="pd-styles" style={{ display: "grid", gridTemplateColumns: "repeat(3,1fr)", gap: 14 }}>
        {data.styles.map((s) => {
          const on = s.id === styleId;
          const delta = Math.round((s.factor - 1) * 100);
          const deltaLabel = delta === 0 ? "базовый бюджет" : (delta > 0 ? `≈ дороже на ${delta}%` : `≈ дешевле на ${Math.abs(delta)}%`);
          return (
            <button key={s.id} className={"style-card" + (on ? " sel" : "")} onClick={() => onPick(s.id)} aria-pressed={on}>
              <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10 }}>
                <span style={{ fontWeight: 800, fontFamily: "var(--font-display)", fontSize: 17 }}>{s.name}</span>
                {on && <span style={{ width: 22, height: 22, borderRadius: "50%", background: "var(--accent)", color: "#1a0d08", display: "grid", placeItems: "center", flex: "none" }}><I.check size={13} /></span>}
              </div>
              <div style={{ fontSize: 12.5, color: "var(--muted)", marginTop: 4 }}>{s.mood}</div>
              <div className="sw">{s.palette.map((c, i) => <span key={i} style={{ background: c }} />)}</div>
              <div style={{ fontSize: 13, color: "var(--muted)", marginTop: 12, lineHeight: 1.45 }}>{s.desc}</div>
              <div style={{ marginTop: 12, fontSize: 12, fontWeight: 700, color: delta > 0 ? "var(--accent)" : (delta < 0 ? "var(--accent-2)" : "var(--faint)") }}>{deltaLabel}</div>
            </button>
          );
        })}
      </div>
    </section>
  );
}

/* ---------------- РАССТАНОВКА (варианты раскладки) ---------------- */
function LayoutPicker({ layout, onPick }) {
  return (
    <section className="pd-section">
      <div className="pd-eyebrow"><span className="dot" />Расстановка</div>
      <h3 className="pd-h">Варианты раскладки мебели</h3>
      <p style={{ color: "var(--muted)", fontSize: 14.5, marginTop: 4, marginBottom: 18, maxWidth: 720 }}>
        AI предложил несколько схем расстановки под геометрию комнаты. Выберите раскладку — обновятся метки на визуализации «до/после» и акценты сцены.
      </p>
      <div className="pd-styles" style={{ display: "grid", gridTemplateColumns: "repeat(3,1fr)", gap: 14 }}>
        {LAYOUTS.map((l) => {
          const on = l.id === layout.id;
          return (
            <button key={l.id} className={"style-card" + (on ? " sel" : "")} onClick={() => onPick(l.id)} aria-pressed={on}>
              <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10, marginBottom: 12 }}>
                <span style={{ fontWeight: 800, fontFamily: "var(--font-display)", fontSize: 17 }}>{l.name}</span>
                {on && <span style={{ width: 22, height: 22, borderRadius: "50%", background: "var(--accent)", color: "#1a0d08", display: "grid", placeItems: "center", flex: "none" }}><I.check size={13} /></span>}
              </div>
              <MiniLayout plan={l.plan} />
              <div style={{ fontSize: 13, color: "var(--muted)", marginTop: 12, lineHeight: 1.45 }}>{l.note}</div>
              <div style={{ display: "flex", flexWrap: "wrap", gap: 6, marginTop: 12 }}>
                {l.pros.map((p) => (
                  <span key={p} style={{ display: "inline-flex", alignItems: "center", gap: 5, fontSize: 11.5, fontWeight: 700, color: "var(--accent-2)", padding: "3px 9px", borderRadius: 99, background: "rgba(31,138,107,.12)", border: "1px solid rgba(31,138,107,.28)" }}>
                    <I.check size={12} />{p}
                  </span>
                ))}
              </div>
            </button>
          );
        })}
      </div>
    </section>
  );
}

/* схема комнаты сверху: окно сверху, дверь снизу, блоки мебели */
function MiniLayout({ plan }) {
  return (
    <div className="plan-box" style={{ position: "relative", width: "100%", aspectRatio: "16/11", borderRadius: 12 }}>
      <span className="pl-win" style={{ position: "absolute", top: -2, height: 4, borderRadius: 2, left: "26%", width: "48%" }} />
      <span style={{ position: "absolute", bottom: -1, left: "8%", width: "20%", height: 12, borderLeft: "2px solid var(--accent)", borderRadius: "0 0 0 9px" }} />
      {plan.map((b, i) => (
        <span key={i} title={b.label} style={{ position: "absolute", left: b.x + "%", top: b.y + "%", width: b.w + "%", height: b.h + "%",
          borderRadius: b.k === "rug" ? 7 : 5, background: LAYOUT_K[b.k] || "var(--surface-2)",
          border: b.k === "rug" ? "1px dashed rgba(255,255,255,.3)" : "1px solid rgba(255,255,255,.18)",
          display: "grid", placeItems: "center", overflow: "hidden" }}>
          <span style={{ fontSize: 9.5, fontWeight: 700, color: b.k === "rug" ? "var(--faint)" : "#fff", opacity: .92, whiteSpace: "nowrap", padding: "0 2px" }}>{b.label}</span>
        </span>
      ))}
    </div>
  );
}

/* ---------------- ДО / ПОСЛЕ (слайдер визуализации) ---------------- */
function BeforeAfter({ data, style, pins }) {
  const [pos, setPos] = usePD(56);
  const [drag, setDrag] = usePD(false);
  const boxRef = usePDR(null);
  const img = PHOTOS[data.cover] || PHOTOS.living;
  const pal = style.palette;
  const arPins = pins || [[31, 60, "Диван"], [69, 45, "Стеллаж"], [50, 74, "Свет"]];

  const setFromX = (clientX) => {
    const el = boxRef.current; if (!el) return;
    const r = el.getBoundingClientRect();
    setPos(Math.max(6, Math.min(94, ((clientX - r.left) / r.width) * 100)));
  };
  usePDE(() => {
    if (!drag) return;
    const mv = (e) => { if (e.cancelable) e.preventDefault(); setFromX(e.clientX); };
    const up = () => setDrag(false);
    window.addEventListener("pointermove", mv, { passive: false });
    window.addEventListener("pointerup", up);
    return () => { window.removeEventListener("pointermove", mv); window.removeEventListener("pointerup", up); };
  }, [drag]);

  const badge = (extra) => ({ position: "absolute", display: "inline-flex", alignItems: "center", gap: 6, padding: "6px 11px", borderRadius: 99, fontSize: 11.5, fontWeight: 800, letterSpacing: ".04em", backdropFilter: "blur(6px)", WebkitBackdropFilter: "blur(6px)", ...extra });

  return (
    <section className="pd-section">
      <div className="pd-eyebrow"><span className="dot" />Визуализация</div>
      <div style={{ display: "flex", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
        <h3 className="pd-h" style={{ marginBottom: 0 }}>До и после</h3>
        <span className="glass" style={{ display: "inline-flex", alignItems: "center", gap: 7, padding: "6px 12px", borderRadius: 99, fontSize: 12.5, fontWeight: 700 }}>
          <span style={{ width: 9, height: 9, borderRadius: 3, background: pal[0], flex: "none" }} />{style.name}
        </span>
      </div>
      <p style={{ color: "var(--muted)", fontSize: 14.5, marginTop: 8, marginBottom: 18, maxWidth: 760 }}>
        Слева — исходное фото комнаты, справа — как AIVibe видит её в стиле «{style.name}». Перетащите ползунок, чтобы сравнить.
      </p>

      <div ref={boxRef} onPointerDown={(e) => { e.preventDefault(); setDrag(true); setFromX(e.clientX); }}
        style={{ position: "relative", borderRadius: "var(--r-xl)", overflow: "hidden", aspectRatio: "16/9", userSelect: "none", touchAction: "none", cursor: "ew-resize", boxShadow: "var(--shadow-pop)", border: "1px solid var(--hairline)" }}>

        {/* ПОСЛЕ — полный слой снизу, цветокоррекция + тон палитры стиля */}
        <div style={{ position: "absolute", inset: 0 }}>
          <Img src={img} label="после" style={{ position: "absolute", inset: 0, filter: "saturate(1.2) contrast(1.06) brightness(1.05)" }} />
          <div style={{ position: "absolute", inset: 0, background: `linear-gradient(125deg, ${pal[0]}66 0%, transparent 42%), linear-gradient(305deg, ${(pal[1] || pal[0])}55 0%, transparent 46%)`, mixBlendMode: "soft-light" }} />
          <div style={{ position: "absolute", inset: 0, background: "linear-gradient(180deg, transparent 50%, rgba(14,10,16,.55))" }} />
          {/* AR-метки расставленной мебели */}
          {arPins.map(([l, t, name], i) => (
            <span key={i} className="glass" style={{ position: "absolute", left: l + "%", top: t + "%", transform: "translate(-50%,-50%)", padding: "6px 11px", borderRadius: 9, fontSize: 12, fontWeight: 700, display: "flex", alignItems: "center", gap: 6, borderColor: "rgba(31,138,107,.55)", background: "rgba(31,138,107,.18)", whiteSpace: "nowrap" }}>
              <I.check size={13} style={{ color: "var(--accent-2)" }} />{name}
            </span>
          ))}
          <span style={badge({ right: 14, top: 14, background: "rgba(31,138,107,.22)", border: "1px solid rgba(31,138,107,.5)", color: "var(--accent-2)" })}>
            <I.spark size={13} />ПОСЛЕ · AIVibe
          </span>
          <div style={{ position: "absolute", left: 14, bottom: 14, display: "flex", gap: 6 }}>
            {pal.map((c, i) => <span key={i} style={{ width: 22, height: 22, borderRadius: 6, background: c, border: "1px solid rgba(255,255,255,.25)" }} />)}
          </div>
        </div>

        {/* ДО — верхний слой, обрезан по ползунку (показываем левую часть) */}
        <div style={{ position: "absolute", inset: 0, clipPath: `inset(0 ${100 - pos}% 0 0)` }}>
          <Img src={img} label="скан" style={{ position: "absolute", inset: 0, filter: "grayscale(.92) brightness(.58) contrast(1.06)" }} />
          <div style={{ position: "absolute", inset: 0, background: "linear-gradient(180deg, rgba(14,10,16,.3), rgba(14,10,16,.5))" }} />
          <div style={{ position: "absolute", inset: 0, backgroundImage: "linear-gradient(rgba(31,138,107,.22) 1px,transparent 1px),linear-gradient(90deg,rgba(31,138,107,.22) 1px,transparent 1px)", backgroundSize: "32px 32px" }} />
          <span style={badge({ left: 14, top: 14, background: "rgba(14,10,16,.6)", border: "1px solid var(--hairline)", color: "var(--text)" })}>
            <I.scan size={13} style={{ color: "var(--accent-2)" }} />ДО · исходное фото
          </span>
        </div>

        {/* разделитель + ручка */}
        <div style={{ position: "absolute", top: 0, bottom: 0, left: pos + "%", width: 2, background: "#fff", transform: "translateX(-1px)", boxShadow: "0 0 14px rgba(0,0,0,.55)" }}>
          <div style={{ position: "absolute", top: "50%", left: "50%", transform: "translate(-50%,-50%)", width: 42, height: 42, borderRadius: "50%", background: "#fff", color: "#1a0d08", display: "grid", placeItems: "center", boxShadow: "0 4px 18px rgba(0,0,0,.45)", cursor: "ew-resize" }}>
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M9 7l-4 5 4 5M15 7l4 5-4 5" /></svg>
          </div>
        </div>
      </div>
    </section>
  );
}

/* ---------------- ПРОВЕРКА НОРМ (движок эргономики) ---------------- */
function NormsCheck({ checks }) {
  const c = checks || { findings: [], ok: true, warns: 0 };
  return (
    <section className="pd-section">
      <div className="pd-eyebrow"><span className="dot" />Проверка норм</div>
      <div style={{ display: "flex", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
        <h3 className="pd-h" style={{ marginBottom: 0 }}>Эргономика расстановки</h3>
        <span className="glass" style={{ display: "inline-flex", alignItems: "center", gap: 7, padding: "6px 12px", borderRadius: 99, fontSize: 12.5, fontWeight: 700,
          color: c.ok ? "var(--accent-2)" : "var(--accent)", borderColor: c.ok ? "rgba(31,138,107,.4)" : "rgba(226,85,43,.4)" }}>
          <span style={{ width: 8, height: 8, borderRadius: "50%", background: c.ok ? "var(--accent-2)" : "var(--accent)", flex: "none" }} />
          {c.ok ? "Все нормы соблюдены" : c.warns + (c.warns === 1 ? " замечание" : c.warns < 5 ? " замечания" : " замечаний")}
        </span>
      </div>
      <p style={{ color: "var(--muted)", fontSize: 14.5, marginTop: 8, marginBottom: 18, maxWidth: 760 }}>
        Движок проверил проходы, дистанции и плотность по нормам эргономики — детерминированно, из геометрии выбранной раскладки. Меняете раскладку выше — проверка пересчитывается.
      </p>
      <div style={{ display: "flex", flexDirection: "column", gap: 9 }}>
        {c.findings.map((f, i) => {
          const Ico = FIND_ICON[f.kind] || FIND_ICON.idea;
          return (
            <div key={i} className={"find " + f.kind}>
              <span className="fi"><Ico size={15} /></span>
              <span style={{ fontSize: 14, lineHeight: 1.5, color: "var(--text)" }}>{f.text}</span>
            </div>
          );
        })}
      </div>
    </section>
  );
}

/* ---------------- БЮДЖЕТ ---------------- */
function BudgetPicker({ data, tier, onTier, total, onOptimize, sref }) {
  const budget = data.budget;
  const pct = Math.min(100, Math.round((total / budget) * 100));
  const over = total > budget;
  const cur = data.budgets.find((b) => b.id === tier) || data.budgets[1];
  return (
    <section className="pd-section" ref={sref}>
      <div className="pd-eyebrow"><span className="dot" />Бюджет</div>
      <h3 className="pd-h">Под какой бюджет собираем</h3>
      <p style={{ color: "var(--muted)", fontSize: 14.5, marginTop: 4, marginBottom: 18, maxWidth: 720 }}>
        Тариф меняет наполнение сметы целиком — AI пересобирает подбор под выбранный уровень. Отдельные предметы потом можно заменить вручную ниже.
      </p>

      <div className="pd-seg" style={{ maxWidth: 520 }} role="tablist" aria-label="Уровень бюджета">
        {data.budgets.map((b) => (
          <button key={b.id} className={b.id === tier ? "on" : ""} onClick={() => onTier(b.id)} role="tab" aria-selected={b.id === tier}>
            {b.name}{b.recommended && <span className="sn">рекомендация AI</span>}
          </button>
        ))}
      </div>
      <div style={{ fontSize: 13.5, color: "var(--muted)", marginTop: 12 }}>{cur.note}</div>

      <div className="glass" style={{ borderRadius: "var(--r-lg)", padding: "18px 20px", marginTop: 18, maxWidth: 640 }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginBottom: 12, flexWrap: "wrap", gap: 8 }}>
          <span style={{ fontSize: 14, color: "var(--muted)" }}>Подобрано на</span>
          <span className="display" style={{ fontSize: 24 }}>{fmtMoney(total)} <span style={{ fontSize: 14, color: "var(--faint)", fontWeight: 500 }}>из {fmtMoney(budget)}</span></span>
        </div>
        <div className="budget-bar"><i style={{ width: pct + "%", background: over ? "linear-gradient(90deg,#E2552B,#ff7849)" : "linear-gradient(90deg,var(--accent-2),#39b88c)" }} /></div>
        <div style={{ display: "flex", justifyContent: "space-between", marginTop: 10, fontSize: 13 }}>
          <span style={{ color: over ? "var(--accent)" : "var(--accent-2)", fontWeight: 700 }}>
            {over ? `Превышение на ${fmtMoney(total - budget)}` : `Остаток ${fmtMoney(budget - total)}`}
          </span>
          <span style={{ color: "var(--faint)" }}>{pct}% бюджета</span>
        </div>
      </div>

      <button className="btn btn-ghost" style={{ marginTop: 14, padding: "11px 18px" }} onClick={onOptimize}>
        <I.spark size={16} />Уложить в бюджет автоматически
      </button>
    </section>
  );
}

/* ---------------- СПЕЦИФИКАЦИЯ (каталог фабрик) ---------------- */
function ProductCatalog({ data, sel, onPick, sref, adj, style, mats }) {
  return (
    <section className="pd-section" ref={sref} style={{ borderBottom: "none" }}>
      <div className="pd-eyebrow"><span className="dot" />Спецификация</div>
      <div style={{ display: "flex", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
        <h3 className="pd-h" style={{ marginBottom: 0 }}>Подбор по каталогу фабрик</h3>
        <span className="mp f1">Дубрава</span><span className="mp f2">Линея</span>
      </div>
      <p style={{ color: "var(--muted)", fontSize: 14.5, marginTop: 8, marginBottom: 18, maxWidth: 760 }}>
        В каждой категории — 3 варианта по цене и фабрике. Нажмите на карточку, чтобы заменить предмет в смете: итог и полоса бюджета пересчитаются автоматически.
      </p>
      <div className="glass" style={{ display: "inline-flex", alignItems: "center", gap: 9, padding: "8px 14px", borderRadius: 99, marginBottom: 22, fontSize: 13 }}>
        <span style={{ width: 11, height: 11, borderRadius: 4, background: style.palette[0], border: "1px solid rgba(255,255,255,.25)", flex: "none" }} />
        Подбор и цены адаптированы под стиль <b style={{ color: "var(--text)" }}>{style.name}</b>
      </div>

      <div style={{ display: "flex", flexDirection: "column", gap: 26 }}>
        {data.catalog.map((c, ci) => {
          const Ico = I[c.icon] || I.layers;
          const selItem = c.items.find((x) => x.id === sel[ci]);
          // самый дешёвый «не под заказ» аналог в категории (для умного действия)
          const cheapest = c.items.filter((x) => stockInfo(x).state !== "order").sort((a, b) => a.price - b.price)[0] || c.items[0];
          const canSave = selItem && cheapest && cheapest.id !== selItem.id && adj(cheapest.price) < adj(selItem.price);
          const saving = canSave ? adj(selItem.price) - adj(cheapest.price) : 0;
          return (
            <div key={c.cat}>
              <div style={{ display: "flex", alignItems: "center", gap: 11, marginBottom: 12 }}>
                <span style={{ width: 34, height: 34, borderRadius: 10, background: "var(--surface-2)", color: "var(--accent)", display: "grid", placeItems: "center", flex: "none" }}><Ico size={18} /></span>
                <span style={{ fontWeight: 700, fontSize: 16 }}>{c.cat}</span>
                {selItem && <span style={{ marginLeft: "auto", fontFamily: "var(--font-display)", fontWeight: 800, fontSize: 16 }}>{fmtMoney(adj(selItem.price))}</span>}
              </div>

              {canSave && (
                <button onClick={() => onPick(ci, cheapest.id)} className="save-banner">
                  <span style={{ width: 30, height: 30, borderRadius: 9, background: "rgba(31,138,107,.18)", color: "var(--accent-2)", display: "grid", placeItems: "center", flex: "none" }}><I.spark size={16} /></span>
                  <span style={{ flex: 1, textAlign: "left", fontSize: 13.5, lineHeight: 1.4 }}>
                    <b style={{ color: "var(--text)" }}>AI нашёл аналог дешевле на {fmtMoney(saving)}</b>
                    <span style={{ color: "var(--muted)" }}> — «{cheapest.title}», рейтинг {cheapest.rating}</span>
                  </span>
                  <span style={{ display: "inline-flex", alignItems: "center", gap: 5, fontSize: 13, fontWeight: 800, color: "var(--accent-2)", whiteSpace: "nowrap" }}>Заменить<I.arrow size={15} /></span>
                </button>
              )}

              <div className="cat-row">
                {c.items.map((it) => (
                  <ProductCard key={it.id} item={it} selected={sel[ci] === it.id}
                    priceAdj={adj(it.price)} oldAdj={it.old ? adj(it.old) : null}
                    material={mats[ci % mats.length]} dot={style.palette[1] || style.palette[0]}
                    onClick={() => onPick(ci, it.id)} />
                ))}
              </div>
            </div>
          );
        })}
      </div>
    </section>
  );
}

function ProductCard({ item, selected, onClick, priceAdj, oldAdj, material, dot }) {
  const price = priceAdj != null ? priceAdj : item.price;
  const old = oldAdj != null ? oldAdj : item.old;
  const disc = old && old > price ? Math.round((1 - price / old) * 100) : 0;
  const stock = stockInfo(item);
  return (
    <button className={"prod-card" + (selected ? " sel" : "")} onClick={onClick} aria-pressed={selected}>
      <div className="pim">
        <Img src={item.img} label={MP_NAME[item.mp]} style={{ position: "absolute", inset: 0 }} />
        <span className={"mp mp-badge " + item.mp}>{MP_NAME[item.mp]}</span>
        {selected && <span className="selflag"><I.check size={13} /></span>}
      </div>
      <div className="pbody">
        <div style={{ display: "flex", alignItems: "center", gap: 7, flexWrap: "wrap" }}>
          <span className={"tier-tag " + item.tier}>{TIER_NAME[item.tier]}</span>
          {material && (
            <span style={{ display: "inline-flex", alignItems: "center", gap: 5, fontSize: 11.5, fontWeight: 700, color: "var(--muted)", padding: "3px 8px", borderRadius: 99, background: "var(--glass-2)", border: "1px solid var(--hairline)" }}>
              <span style={{ width: 9, height: 9, borderRadius: 3, background: dot, flex: "none" }} />{material}
            </span>
          )}
        </div>
        <div className="pt">{item.title}</div>
        <div style={{ display: "flex", alignItems: "center", gap: 5, fontSize: 12, color: "var(--muted)" }}>
          <I.star size={13} style={{ color: "var(--accent)" }} /><span style={{ fontWeight: 700, color: "var(--text)" }}>{item.rating}</span>
          <span style={{ color: "var(--faint)" }}>· {fmt(item.reviews)} отз.</span>
        </div>
        {/* наличие + доставка */}
        <div style={{ display: "flex", alignItems: "center", gap: 7, fontSize: 11.5, marginTop: "auto", flexWrap: "wrap" }}>
          <span style={{ display: "inline-flex", alignItems: "center", gap: 5, fontWeight: 700, color: stock.color }}>
            <span style={{ width: 7, height: 7, borderRadius: "50%", background: stock.color, flex: "none" }} />{stock.label}
          </span>
          <span style={{ display: "inline-flex", alignItems: "center", gap: 4, color: "var(--faint)" }}>
            <I.truck size={13} />{stock.eta}
          </span>
        </div>
        <div style={{ display: "flex", alignItems: "baseline", gap: 8 }}>
          <span className="pprice">{fmtMoney(price)}</span>
          {disc > 0 && <span className="pold">{fmtMoney(old)}</span>}
          {disc > 0 && <span style={{ marginLeft: "auto", fontSize: 11, fontWeight: 800, color: "var(--accent-2)" }}>−{disc}%</span>}
        </div>
      </div>
    </button>
  );
}

/* ---------------- СМЕТА (sticky) ---------------- */
function CartBar({ items, total, oldTotal, budget, style, onExport }) {
  const saved = oldTotal - total;
  const over = total > budget;
  return (
    <div className="pd-cart">
      <div style={{ display: "flex", alignItems: "center", gap: 18, flexWrap: "wrap" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 11 }}>
          <span style={{ width: 40, height: 40, borderRadius: 12, background: "var(--accent)", color: "#1a0d08", display: "grid", placeItems: "center", flex: "none" }}><I.layers size={20} /></span>
          <div>
            <div style={{ fontFamily: "var(--font-display)", fontWeight: 800, fontSize: 20, lineHeight: 1 }}>{fmtMoney(total)}</div>
            <div style={{ fontSize: 12, color: "var(--muted)", marginTop: 3 }}>{items.length} предметов · {over ? <span style={{ color: "var(--accent)" }}>сверх бюджета</span> : <span style={{ color: "var(--accent-2)" }}>в рамках бюджета</span>}</div>
          </div>
        </div>
        {style && <span className="glass" style={{ display: "inline-flex", alignItems: "center", gap: 7, padding: "7px 12px", borderRadius: 99, fontSize: 12.5, fontWeight: 700 }}>
          <span style={{ width: 9, height: 9, borderRadius: 3, background: style.palette[0], flex: "none" }} />{style.name}
        </span>}
        {saved > 0 && <span className="glass" style={{ padding: "7px 12px", borderRadius: 99, fontSize: 12.5, fontWeight: 700, color: "var(--accent-2)" }}>Скидка по каталогу: −{fmtMoney(saved)}</span>}
        <div style={{ marginLeft: "auto", display: "flex", gap: 10 }}>
          <button className="btn btn-ghost" style={{ padding: "11px 16px" }} onClick={onExport}><I.layers size={16} />Выгрузить PDF</button>
          <button className="btn btn-primary" style={{ padding: "11px 18px" }}><I.check size={16} />Сохранить смету</button>
        </div>
      </div>
    </div>
  );
}

/* ---------------- AI-ЧАТ ---------------- */
function AdvisorChat({ id, hello, onAction, onClose }) {
  const [msgs, setMsgs] = usePD([{ role: "ai", text: hello }]);
  const [val, setVal] = usePD("");
  const [busy, setBusy] = usePD(false);
  const scrollRef = usePDR(null);
  const chips = ["Сделай дешевле", "Собери премиум", "Что с освещением?", "Покажи стиль Japandi", "Итоговая смета"];

  usePDE(() => {
    const el = scrollRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [msgs, busy]);

  const send = async (text) => {
    const t = (text || "").trim();
    if (!t || busy) return;
    setMsgs((m) => [...m, { role: "me", text: t }]);
    setVal("");
    setBusy(true);
    const res = await AIVibeAPI.projects.chat(id, t);
    setBusy(false);
    setMsgs((m) => [...m, { role: "ai", text: res.text }]);
    if (res.action) setTimeout(() => onAction(res.action), 250);
  };

  return (
    <React.Fragment>
      <div className="pd-chat-head">
        <span style={{ width: 38, height: 38, borderRadius: 11, background: "var(--accent)", color: "#1a0d08", display: "grid", placeItems: "center", flex: "none" }}><I.spark size={20} /></span>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontWeight: 800, fontSize: 15 }}>AI-дизайнер</div>
          <div style={{ fontSize: 12, color: "var(--accent-2)", display: "flex", alignItems: "center", gap: 6 }}><span style={{ width: 7, height: 7, borderRadius: "50%", background: "var(--accent-2)" }} />на связи · YandexGPT</div>
        </div>
        <button className="icon-btn pd-rail-close" onClick={onClose} aria-label="Свернуть чат"><I.close size={18} /></button>
      </div>

      <div className="pd-chat-scroll" ref={scrollRef}>
        {msgs.map((m, i) => <div key={i} className={"pd-msg " + m.role}>{m.text}</div>)}
        {busy && <div className="pd-msg ai"><span className="pd-typing"><i /><i /><i /></span></div>}
      </div>

      <div className="pd-chips">
        {chips.map((c) => <button key={c} onClick={() => send(c)} disabled={busy}>{c}</button>)}
      </div>

      <form className="pd-chat-input" onSubmit={(e) => { e.preventDefault(); send(val); }}>
        <input value={val} onChange={(e) => setVal(e.target.value)} placeholder="Спросите дизайнера…" aria-label="Сообщение" />
        <button type="submit" className="btn btn-primary" disabled={busy || !val.trim()} style={{ padding: "0 16px" }} aria-label="Отправить"><I.send size={17} /></button>
      </form>
    </React.Fragment>
  );
}

window.ProjectDetail = ProjectDetail;
