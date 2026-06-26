/* ============================================================
   AIVibe — секции промо-сайта (часть 2)
   How-it-works (sticky scroll-сторителлинг) · Bento · Новости ·
   GitHub · Footer
   ============================================================ */
const { useState: useS2, useEffect: useE2, useRef: useR2 } = React;

const prefersReduced = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
/* На телефоне/планшете «приколотый» скролл-сторителлинг рвётся и тяжёл —
   там показываем секцию статично (как при reduce-motion). */
const narrowVP = window.matchMedia && window.matchMedia("(max-width: 860px)").matches;
const staticHow = prefersReduced || narrowVP;

/* --------------------------------------------------------------
   HOW IT WORKS — sticky-сцена, прогресс ведётся скроллом
-------------------------------------------------------------- */
const STEPS = [
  { n: "01", icon: I.ruler, tag: "Габариты",     title: "Введите план комнаты или габариты", text: "Загрузите обмеры или нарисуйте план — стены, окна, двери. Без сложных 3D-программ." },
  { n: "02", icon: I.spark, tag: "Смета и нормы", title: "AIVibe собирает спецификацию и проверяет расстановку", text: "Движок раскладывает мебель по нормам эргономики и собирает смету с артикулами и ценами под стиль и бюджет." },
  { n: "03", icon: I.layers, tag: "3 варианта",  title: "Готовая смета в трёх бюджетах", text: "Эконом, база, премиум — выгружайте спецификацию клиенту. Меняете предмет — итог и проверка пересчитываются." },
];

/* роутер: на узких экранах — свайп-степпер, иначе — sticky-сторителлинг */
function HowItWorks() {
  return narrowVP ? <HowMobile /> : <HowDesktop />;
}

function HowDesktop() {
  const wrapRef = useR2(null);
  const [p, setP] = useS2(0); // 0..1 прогресс по секции

  useE2(() => {
    if (prefersReduced) { setP(0.5); return; }
    let raf = 0;
    const onScroll = () => {
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(() => {
        const el = wrapRef.current; if (!el) return;
        const rect = el.getBoundingClientRect();
        const total = el.offsetHeight - window.innerHeight;
        const prog = Math.min(1, Math.max(0, -rect.top / total));
        setP(prog);
      });
    };
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll);
    return () => { window.removeEventListener("scroll", onScroll); window.removeEventListener("resize", onScroll); cancelAnimationFrame(raf); };
  }, []);

  const active = Math.min(2, Math.floor(p * 3 + (prefersReduced ? 0 : 0.0001)));
  const sub = Math.min(1, (p * 3) - active); // прогресс внутри активного шага

  return (
    <section id="how" ref={wrapRef} style={{ position: "relative", height: prefersReduced ? "auto" : "340vh" }}>
      <div className="minh-screen" style={{ position: prefersReduced ? "static" : "sticky", top: 0, minHeight: prefersReduced ? "auto" : undefined, display: "flex", alignItems: "center", paddingBlock: "clamp(60px,10vh,110px)" }}>
        <div className="container how-grid" style={{ display: "grid", gridTemplateColumns: "0.92fr 1.08fr", gap: "clamp(32px,5vw,72px)", width: "min(var(--maxw),100% - var(--gutter)*2)", alignItems: "center" }}>
          {/* левая колонка — шаги */}
          <div>
            <div className="eyebrow jade" style={{ marginBottom: 18 }}><span style={{ width: 22, height: 1, background: "var(--accent-2)" }} />КАК ЭТО РАБОТАЕТ</div>
            <h2 className="display" style={{ fontSize: "clamp(34px,4.4vw,60px)", marginBottom: 36 }}>От пустой комнаты<br />до готового дизайна</h2>
            <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
              {STEPS.map((s, i) => {
                const on = i === active;
                return (
                  <div key={s.n} className="glass" style={{ borderRadius: "var(--r-lg)", padding: "20px 22px", display: "flex", gap: 16,
                    borderColor: on ? "rgba(31,138,107,.45)" : "var(--hairline)",
                    background: on ? "rgba(31,138,107,.08)" : "var(--glass-2)",
                    opacity: on ? 1 : 0.5, transition: "all .45s ease" }}>
                    <div style={{ flex: "none", width: 44, height: 44, borderRadius: 12, display: "grid", placeItems: "center",
                      background: on ? "var(--accent-2)" : "var(--surface-2)", color: on ? "#06140f" : "var(--muted)", transition: "all .45s" }}>
                      <s.icon size={21} />
                    </div>
                    <div>
                      <div style={{ display: "flex", gap: 9, alignItems: "baseline", marginBottom: 4 }}>
                        <span className="display" style={{ fontSize: 14, color: on ? "var(--accent-2)" : "var(--faint)" }}>{s.n}</span>
                        <span style={{ fontWeight: 700, fontSize: 16.5 }}>{s.tag}</span>
                      </div>
                      <p style={{ fontSize: 14.5, color: "var(--muted)", lineHeight: 1.55 }}>{on ? s.title : s.text}</p>
                      {on && !prefersReduced && (
                        <div style={{ height: 3, borderRadius: 9, background: "var(--glass-2)", marginTop: 12, overflow: "hidden" }}>
                          <div style={{ height: "100%", width: sub * 100 + "%", background: "var(--accent-2)" }} />
                        </div>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
          {/* правая колонка — эволюционирующая сцена */}
          <DemoStage active={active} sub={sub} />
        </div>
      </div>
    </section>
  );
}

/* мобильный свайп-степпер: 3 слайда, демо-сцена заморожена на своём шаге */
function HowMobile() {
  const scRef = useR2(null);
  const [idx, setIdx] = useS2(0);
  const onScroll = () => {
    const el = scRef.current; if (!el) return;
    const i = Math.round(el.scrollLeft / el.clientWidth);
    setIdx((prev) => (prev !== i ? i : prev));
  };
  const goto = (i) => {
    const el = scRef.current; if (!el) return;
    el.scrollTo({ left: i * el.clientWidth, behavior: "smooth" });
  };
  return (
    <section id="how" style={{ paddingBlock: "clamp(56px,9vh,90px)" }}>
      <div className="container">
        <div className="eyebrow jade" style={{ marginBottom: 16 }}><span style={{ width: 22, height: 1, background: "var(--accent-2)" }} />КАК ЭТО РАБОТАЕТ</div>
        <h2 className="display" style={{ fontSize: "clamp(30px,8vw,44px)" }}>От пустой комнаты<br />до готового дизайна</h2>

        <div ref={scRef} onScroll={onScroll} className="how-scroller">
          {STEPS.map((s, i) => (
            <div key={s.n} className="how-slide">
              <DemoStage active={i} sub={1} />
              <div className="glass" style={{ borderRadius: "var(--r-lg)", padding: "18px 20px", display: "flex", gap: 15,
                borderColor: "rgba(31,138,107,.4)", background: "rgba(31,138,107,.07)" }}>
                <div style={{ flex: "none", width: 44, height: 44, borderRadius: 12, display: "grid", placeItems: "center", background: "var(--accent-2)", color: "#06140f" }}>
                  <s.icon size={21} />
                </div>
                <div>
                  <div style={{ display: "flex", gap: 9, alignItems: "baseline", marginBottom: 4 }}>
                    <span className="display" style={{ fontSize: 14, color: "var(--accent-2)" }}>{s.n}</span>
                    <span style={{ fontWeight: 700, fontSize: 16.5 }}>{s.tag}</span>
                  </div>
                  <p style={{ fontSize: 14.5, color: "var(--muted)", lineHeight: 1.55 }}>{s.title}</p>
                </div>
              </div>
            </div>
          ))}
        </div>

        <div className="how-dots" role="tablist" aria-label="Шаги">
          {STEPS.map((s, i) => (
            <button key={s.n} className={i === idx ? "on" : ""} aria-label={`Шаг ${s.n}: ${s.tag}`} aria-selected={i === idx} role="tab" onClick={() => goto(i)}><i /></button>
          ))}
        </div>
      </div>
    </section>
  );
}

/* центральная сцена: скан → AI-чат → AR-расстановка */
function DemoStage({ active, sub }) {
  const scanFill = active === 0 ? sub : 1;
  return (
    <div className="glass" style={{ position: "relative", borderRadius: "var(--r-xl)", overflow: "hidden", aspectRatio: "4/3.4", boxShadow: "var(--shadow-pop)" }}>
      <Img src={PHOTOS.living} label="визуализация комнаты" />
      <div style={{ position: "absolute", inset: 0, background: "linear-gradient(180deg, rgba(14,10,16,.15), rgba(14,10,16,.6))" }} />

      {/* СТАДИЯ 0 — скан */}
      <div style={{ position: "absolute", inset: 0, opacity: active === 0 ? 1 : 0.25, transition: "opacity .5s" }}>
        <div style={{ position: "absolute", inset: 0, backgroundImage: "linear-gradient(rgba(31,138,107,.22) 1px,transparent 1px),linear-gradient(90deg,rgba(31,138,107,.22) 1px,transparent 1px)", backgroundSize: "30px 30px",
          clipPath: `inset(0 ${(1 - scanFill) * 100}% 0 0)`, transition: "clip-path .2s linear" }} />
        <div style={{ position: "absolute", top: 0, bottom: 0, left: scanFill * 100 + "%", width: 2, background: "var(--accent-2)", boxShadow: "0 0 22px var(--accent-2)", opacity: active === 0 ? 1 : 0 }} />
      </div>

      {/* СТАДИЯ 1 — AI-чат */}
      <div style={{ position: "absolute", left: 18, right: 18, bottom: 18, display: "flex", flexDirection: "column", gap: 10,
        opacity: active === 1 ? 1 : 0, transform: active === 1 ? "none" : "translateY(14px)", transition: "all .5s", pointerEvents: "none" }}>
        <div className="glass" style={{ alignSelf: "flex-end", maxWidth: "70%", padding: "11px 15px", borderRadius: "16px 16px 4px 16px", fontSize: 14, background: "rgba(226,85,43,.16)", borderColor: "rgba(226,85,43,.3)" }}>
          Хочу уютную гостиную в тёплых тонах, бюджет 500к
        </div>
        <div className="glass" style={{ alignSelf: "flex-start", maxWidth: "82%", padding: "13px 16px", borderRadius: "16px 16px 16px 4px", fontSize: 14, lineHeight: 1.5 }}>
          <span style={{ display: "block", color: "var(--accent-2)", fontWeight: 700, fontSize: 11.5, letterSpacing: ".06em", marginBottom: 5 }}>СМЕТА AIVIBE · YANDEXGPT 5</span>
          Собрал смету: 38 позиций — диван-терракота, дубовый стеллаж, тёплый свет. Итог 480 000 ₽, расстановка по нормам.
        </div>
      </div>

      {/* СТАДИЯ 2 — AR-расстановка мебели */}
      <div style={{ position: "absolute", inset: 0, opacity: active === 2 ? 1 : 0, transition: "opacity .5s", pointerEvents: "none" }}>
        {[[34, 58, "Диван"], [66, 40, "Стеллаж"], [52, 72, "Лампа"]].map(([l, t, name], i) => (
          <div key={i} className="glass" style={{ position: "absolute", left: l + "%", top: t + "%", transform: "translate(-50%,-50%)",
            padding: "7px 12px", borderRadius: 10, fontSize: 12.5, fontWeight: 600, display: "flex", alignItems: "center", gap: 7,
            borderColor: "rgba(31,138,107,.5)", background: "rgba(31,138,107,.16)",
            opacity: sub > i * 0.28 ? 1 : 0, transition: `opacity .4s ${i * 0.05}s` }}>
            <I.check size={14} style={{ color: "var(--accent-2)" }} /> {name}
          </div>
        ))}
      </div>

      {/* верхний статус-бар сцены */}
      <div className="glass" style={{ position: "absolute", top: 16, left: 16, padding: "8px 14px", borderRadius: 99, fontSize: 12.5, fontWeight: 700, display: "flex", alignItems: "center", gap: 9 }}>
        <span style={{ width: 8, height: 8, borderRadius: "50%", background: "var(--accent-2)" }} />
        {["План комнаты", "Подбор и смета", "Проверка норм"][active]}
      </div>
    </div>
  );
}

/* --------------------------------------------------------------
   BENTO — 4 возможности
-------------------------------------------------------------- */
function Bento() {
  const ref = useReveal();
  return (
    <section id="features" style={{ paddingBlock: "clamp(80px,12vh,140px)" }} ref={ref}>
      <div className="container">
        <div className="reveal" style={{ maxWidth: 720 }}>
          <div className="eyebrow" style={{ marginBottom: 18 }}><span style={{ width: 22, height: 1, background: "var(--accent)" }} />ВОЗМОЖНОСТИ</div>
          <h2 className="display" style={{ fontSize: "clamp(34px,4.6vw,64px)" }}>Всё для дизайна<br />в одном приложении</h2>
        </div>
        <div className="bento reveal">
          {/* большая — Смета с артикулами */}
          <article className="bento-card b-lg" style={{ gridColumn: "span 2", gridRow: "span 2" }}>
            <Img src={PHOTOS.living} label="Смета по проекту" style={{ position: "absolute", inset: 0 }} />
            <div className="bento-shade" />
            <div className="bento-body">
              <I.layers size={26} style={{ color: "var(--accent-2)" }} />
              <h3>Смета с артикулами</h3>
              <p>Готовая спецификация: предметы, количество, цены — сразу на выгрузку клиенту, без ручного Excel.</p>
            </div>
            <span className="bento-badge" style={{ background: "rgba(31,138,107,.18)", borderColor: "rgba(31,138,107,.4)", color: "var(--accent-2)" }}>Спецификация</span>
          </article>

          {/* AI-дизайнер */}
          <article className="bento-card">
            <div className="bento-body">
              <I.spark size={24} style={{ color: "var(--accent)" }} />
              <h3>AI-дизайнер</h3>
              <p>YandexGPT 5 и GigaChat подбирают стиль, мебель и свет под запрос, бюджет и нормы.</p>
            </div>
          </article>

          {/* Проверка эргономики */}
          <article className="bento-card">
            <div className="bento-body">
              <I.ruler size={24} style={{ color: "var(--info)" }} />
              <h3>Проверка эргономики</h3>
              <p>Проходы, рабочие зоны, дистанции — движок ловит «летающие диваны» до того, как их увидит клиент.</p>
            </div>
          </article>

          {/* Три бюджета / широкая */}
          <article className="bento-card b-wide" style={{ gridColumn: "span 2" }}>
            <div className="bento-body" style={{ flexDirection: "row", alignItems: "center", gap: 22 }}>
              <div style={{ flex: "none", width: 54, height: 54, borderRadius: 14, background: "var(--surface-2)", display: "grid", placeItems: "center", color: "var(--chart)" }}>
                <I.wallet size={26} />
              </div>
              <div>
                <h3 style={{ marginBottom: 6 }}>Три бюджета в один клик</h3>
                <p>Эконом · база · премиум — пересборка сметы под уровень клиента, без ручного пересчёта.</p>
              </div>
            </div>
          </article>
        </div>
      </div>
    </section>
  );
}

/* --------------------------------------------------------------
   НОВОСТИ ДИЗАЙНА — лента карточек из mock-API
-------------------------------------------------------------- */
function NewsFeed() {
  const ref = useReveal();
  const [rows, setRows] = useS2(null);
  useE2(() => { AIVibeAPI.news.list({ status: "published" }).then((r) => setRows(r.slice(0, 4))); }, []);
  return (
    <section id="news" style={{ paddingBlock: "clamp(60px,9vh,110px)" }} ref={ref}>
      <div className="container">
        <div className="reveal" style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-end", flexWrap: "wrap", gap: 20, marginBottom: 44 }}>
          <div>
            <div className="eyebrow info" style={{ marginBottom: 18 }}><span style={{ width: 22, height: 1, background: "var(--info)" }} />ЖУРНАЛ</div>
            <h2 className="display" style={{ fontSize: "clamp(32px,4.2vw,58px)" }}>Новости дизайна</h2>
          </div>
          <a className="btn btn-ghost" href="#" onClick={(e) => e.preventDefault()}>Все материалы <I.arrow size={16} /></a>
        </div>
        <div className="news-grid reveal">
          {!rows && Array.from({ length: 4 }).map((_, i) => <div key={i} className="glass skel" style={{ borderRadius: "var(--r-lg)", height: 320 }} />)}
          {rows && rows.map((n, i) => (
            <article key={n.id} className="glass news-card" style={{ borderRadius: "var(--r-lg)", overflow: "hidden", display: "flex", flexDirection: "column", gridColumn: i === 0 ? "span 2" : "span 1" }}>
              <div style={{ position: "relative", aspectRatio: i === 0 ? "16/8" : "16/10", overflow: "hidden" }}>
                <Img src={PHOTOS[n.cover] || PHOTOS.warm} label={n.category} />
                <span style={{ position: "absolute", top: 13, left: 13, padding: "5px 11px", borderRadius: 99, fontSize: 11.5, fontWeight: 700, background: "rgba(14,10,16,.6)", backdropFilter: "blur(6px)", border: "1px solid var(--hairline)" }}>{n.category}</span>
              </div>
              <div style={{ padding: 22, display: "flex", flexDirection: "column", gap: 10, flex: 1 }}>
                <h3 style={{ fontSize: i === 0 ? 24 : 19, fontWeight: 700, lineHeight: 1.25, letterSpacing: "-0.01em" }}>{n.title}</h3>
                <p style={{ color: "var(--muted)", fontSize: 14.5, lineHeight: 1.55, flex: 1 }}>{n.excerpt}</p>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", color: "var(--faint)", fontSize: 13, marginTop: 4 }}>
                  <span>{new Date(n.date).toLocaleDateString("ru-RU", { day: "numeric", month: "long" })}</span>
                  <span>{fmt(n.views)} просмотров</span>
                </div>
              </div>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}

window.HowItWorks = HowItWorks;
window.Bento = Bento;
window.NewsFeed = NewsFeed;
