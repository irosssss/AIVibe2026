/* ============================================================
   AIVibe — Кабинет: Профиль и Сохранённые проекты
   ============================================================ */
const { useState: useCV, useEffect: useCVE } = React;

/* ---------- общие карточки аналитики (паттерн дашборда: Stripe / Linear / Metabase) ---------- */
function AnalyCard({ title, source, accent, children, style }) {
  return (
    <div className="glass" style={{ borderRadius: "var(--r-lg)", padding: 24, ...style }}>
      {(title || source) && (
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 12, marginBottom: 18 }}>
          {title && <h3 style={{ fontSize: 16.5, fontWeight: 700, minWidth: 0 }}>{title}</h3>}
          {source && <span style={{ fontSize: 11.5, fontWeight: 700, letterSpacing: ".06em", textTransform: "uppercase", color: accent || "var(--faint)", whiteSpace: "nowrap", flex: "none" }}>{source}</span>}
        </div>
      )}
      {children}
    </div>
  );
}

/* KPI-плитка с дельтой (как в Stripe/Linear: число + изменение к прошлому периоду) */
function KpiCard({ k }) {
  const val = k.unit === "₽" ? fmtMoney(k.value) : (k.unit === "abs" ? fmt(k.value) : fmt(k.value) + (k.unit || ""));
  const big = val.length > 9 ? 22 : (val.length > 7 ? 26 : 30);
  return (
    <div className="glass" style={{ borderRadius: "var(--r-lg)", padding: 22 }}>
      <div style={{ color: "var(--muted)", fontSize: 13.5, marginBottom: 12 }}>{k.label}</div>
      <div style={{ display: "flex", alignItems: "baseline", gap: 10, flexWrap: "wrap" }}>
        <span className="display" style={{ fontSize: big, letterSpacing: "-0.02em", whiteSpace: "nowrap" }}>{val}</span>
        {k.delta != null && (
          <span style={{ fontSize: 13, fontWeight: 700, color: k.delta >= 0 ? "var(--accent-2)" : "var(--accent)", display: "inline-flex", alignItems: "center", gap: 2 }}>
            <I.arrowUp size={13} style={{ transform: k.delta >= 0 ? "none" : "rotate(180deg)" }} />{Math.abs(k.delta)}{k.unit === "abs" ? "" : "%"}
          </span>
        )}
      </div>
    </div>
  );
}
function ChartSkel({ h = 150 }) { return <div className="skel" style={{ height: h, borderRadius: 12 }} />; }

function Profile({ user }) {
  const [an, setAn] = useCV(null);
  useCVE(() => { AIVibeAPI.profile.analytics().then(setAn); }, []);
  return (
    <div className="reveal in" style={{ display: "flex", flexDirection: "column", gap: 22 }} ref={useReveal()}>
      {/* ── верх: карточка профиля + KPI ── */}
      <div className="profile-grid" style={{ display: "grid", gridTemplateColumns: "0.8fr 1.2fr", gap: 22, alignItems: "start" }}>
        {/* карточка профиля */}
        <div className="glass cab-col" style={{ borderRadius: "var(--r-xl)", padding: 30, height: "fit-content" }}>
          <div style={{ display: "flex", flexDirection: "column", alignItems: "center", textAlign: "center", gap: 14, paddingBottom: 24, borderBottom: "1px solid var(--hairline)" }}>
            <Avatar user={user} size={84} />
            <div>
              <div className="display" style={{ fontSize: 23 }}>{user.name}</div>
              <div style={{ color: "var(--muted)", fontSize: 14, marginTop: 4 }}>{user.email}</div>
            </div>
            <div style={{ display: "flex", gap: 8 }}>
              <span className="glass" style={{ padding: "6px 13px", borderRadius: 99, fontSize: 12.5, fontWeight: 700, display: "flex", alignItems: "center", gap: 7 }}>
                <span style={{ width: 8, height: 8, borderRadius: "50%", background: user.provider === "yandex" ? "#FC3F1D" : "#0077FF" }} />
                {user.provider === "yandex" ? "Яндекс ID" : "VK ID"}
              </span>
              {user.role === "admin" && <span style={{ padding: "6px 13px", borderRadius: 99, fontSize: 12.5, fontWeight: 700, background: "rgba(226,85,43,.16)", color: "var(--accent)", border: "1px solid rgba(226,85,43,.32)" }}>Администратор</span>}
            </div>
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 14, marginTop: 22 }}>
            <Row k="Тариф" v="AIVibe Pro" />
            <Row k="Регион" v="Москва, РФ" />
            <Row k="С нами с" v="январь 2026" />
            <Row k="Синхронизация" v={<span style={{ color: "var(--accent-2)" }}>● включена</span>} />
          </div>
          <button className="btn btn-ghost btn-block" style={{ marginTop: 24 }}>Редактировать профиль</button>
        </div>

        {/* KPI 2×2 с дельтами */}
        <div className="cab-stats" style={{ display: "grid", gridTemplateColumns: "repeat(2,1fr)", gap: 14 }}>
          {!an && Array.from({ length: 4 }).map((_, i) => <div key={i} className="glass skel" style={{ borderRadius: "var(--r-lg)", height: 110 }} />)}
          {an && an.kpis.map((k) => <KpiCard key={k.key} k={k} />)}
        </div>
      </div>

      {/* ── аналитика профиля ── */}
      <div>
        <div style={{ display: "flex", alignItems: "center", gap: 9, margin: "4px 2px 14px", flexWrap: "wrap" }}>
          <I.chart size={18} style={{ color: "var(--accent)", flex: "none" }} />
          <h2 style={{ fontSize: 18, fontWeight: 700, whiteSpace: "nowrap" }}>Ваша аналитика</h2>
          <span style={{ fontSize: 12.5, color: "var(--faint)" }}>· за последние 12 недель</span>
        </div>

        <div className="chart-row" style={{ display: "grid", gridTemplateColumns: "1.5fr 1fr", gap: 16, marginBottom: 16 }}>
          <AnalyCard title="Активность" source="AI-сессии" accent="var(--chart)">
            {an ? (
              <React.Fragment>
                <AreaChart data={an.activity} color="var(--chart)" id="prof-act" height={160} />
                <div style={{ display: "flex", gap: 20, marginTop: 12, fontSize: 12.5, color: "var(--muted)" }}>
                  <span style={{ display: "inline-flex", alignItems: "center", gap: 6 }}><span style={{ width: 12, height: 3, background: "var(--chart)", borderRadius: 2 }} />AI-сессии</span>
                  <span>Пик: {Math.max(...an.activity)} сессий в неделю</span>
                </div>
              </React.Fragment>
            ) : <ChartSkel h={160} />}
          </AnalyCard>
          <AnalyCard title="Стили в проектах" source="доля бюджета">
            {an ? <div style={{ paddingTop: 4 }}><Donut data={an.styleSplit} size={150} /></div> : <ChartSkel h={150} />}
          </AnalyCard>
        </div>

        <AnalyCard title="Бюджет по проектам" source="подобрано через AIVibe" accent="var(--accent-2)">
          {an ? <BarList data={an.spendByProject} color="var(--accent-2)" money /> : <ChartSkel h={120} />}
        </AnalyCard>
      </div>

      {/* ── настройки + последняя сессия ── */}
      <div className="chart-row" style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 22, alignItems: "start" }}>
        {/* настройки */}
        <div className="glass" style={{ borderRadius: "var(--r-xl)", padding: 30 }}>
          <h3 style={{ fontSize: 18, fontWeight: 700, marginBottom: 20 }}>Настройки приложения</h3>
          <div style={{ display: "flex", flexDirection: "column" }}>
            <Toggle label="Push о готовности AI-дизайна" sub="Уведомлять, когда советник закончит проект" on />
            <Toggle label="Подбор по каталогу фабрик" sub="Артикулы и цены фабрик-партнёров в смете" on />
            <Toggle label="Автопроверка норм" sub="Подсвечивать узкие проходы и зоны в расстановке" on />
            <Toggle label="Публичные ссылки на проекты" sub="Делиться сметой и расстановкой по ссылке" last />
          </div>
        </div>

        {/* недавняя AI-сессия */}
        <div className="glass" style={{ borderRadius: "var(--r-xl)", padding: 30 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 9, marginBottom: 16 }}>
            <I.spark size={18} style={{ color: "var(--accent)" }} />
            <h3 style={{ fontSize: 18, fontWeight: 700 }}>Последняя сессия с AI-дизайнером</h3>
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
            <div className="glass" style={{ alignSelf: "flex-end", maxWidth: "75%", padding: "11px 15px", borderRadius: "14px 14px 4px 14px", fontSize: 14, background: "rgba(226,85,43,.14)" }}>Сделай гостиную теплее, добавь текстиль</div>
            <div className="glass" style={{ alignSelf: "flex-start", maxWidth: "82%", padding: "11px 15px", borderRadius: "14px 14px 14px 4px", fontSize: 14, lineHeight: 1.5 }}>Добавил шерстяной плед, льняные шторы и ковёр терракотового тона. Обновил расстановку и смету — посмотрите в проекте «Гостиная на Патриках».</div>
          </div>
        </div>
      </div>
    </div>
  );
}

function Row({ k, v }) {
  return <div style={{ display: "flex", justifyContent: "space-between", gap: 16, fontSize: 14.5 }}><span style={{ color: "var(--muted)", whiteSpace: "nowrap" }}>{k}</span><span style={{ fontWeight: 600, whiteSpace: "nowrap", textAlign: "right" }}>{v}</span></div>;
}

function Toggle({ label, sub, on: initOn, last }) {
  const [on, setOn] = useCV(!!initOn);
  return (
    <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 16, paddingBlock: 14, borderBottom: last ? "none" : "1px solid var(--hairline)" }}>
      <div style={{ minWidth: 0 }}><div style={{ fontWeight: 600, fontSize: 14.5, lineHeight: 1.3 }}>{label}</div><div style={{ color: "var(--muted)", fontSize: 13, marginTop: 3, lineHeight: 1.4 }}>{sub}</div></div>
      <button onClick={() => setOn(!on)} aria-pressed={on} style={{ width: 48, height: 28, borderRadius: 99, padding: 3, flex: "none",
        background: on ? "var(--accent-2)" : "var(--surface-2)", transition: ".25s" }}>
        <span style={{ display: "block", width: 22, height: 22, borderRadius: "50%", background: "#fff", transform: on ? "translateX(20px)" : "none", transition: ".25s" }} />
      </button>
    </div>
  );
}

/* стиль-квиз → проект, в котором этот стиль доступен */
const QUIZ_STYLE_PROJECT = { deco: "p_1", warm: "p_2", japandi: "p_1", scandi: "p_3", indust: "p_4", midmod: "p_4" };

/* ---------------- СОХРАНЁННЫЕ ПРОЕКТЫ ---------------- */
function Projects() {
  const [rows, setRows] = useCV(null);
  const [sum, setSum] = useCV(null);          // сводная аналитика
  const [openId, setOpenId] = useCV(null);   // открытая деталь проекта
  const [openStyle, setOpenStyle] = useCV(null); // стиль, с которым открыть проект (из квиза)
  const [newOpen, setNewOpen] = useCV(false); // модалка «Новый проект»
  const [quizOpen, setQuizOpen] = useCV(false);
  useCVE(() => {
    AIVibeAPI.projects.list().then(setRows);
    AIVibeAPI.projects.summary().then(setSum);
    // авто-показ квиза при первом входе
    try { if (!localStorage.getItem("aivibe_quiz_done")) setTimeout(() => setQuizOpen(true), 700); } catch (e) {}
  }, []);
  const finishQuiz = (styleId) => {
    try { localStorage.setItem("aivibe_quiz_done", "1"); } catch (e) {}
    setQuizOpen(false);
    setOpenStyle(styleId);
    setOpenId(QUIZ_STYLE_PROJECT[styleId] || "p_1");
  };
  const statusColor = { "В работе": "var(--info)", "Готов": "var(--accent-2)", "Архив": "var(--faint)" };
  return (
    <div className="reveal in" ref={useReveal()}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 24, flexWrap: "wrap", gap: 14 }}>
        <div>
          <h1 className="display" style={{ fontSize: 30 }}>Мои проекты</h1>
          <p style={{ color: "var(--muted)", fontSize: 14.5, marginTop: 4 }}>Сохранённые комнаты, расстановки и сметы</p>
        </div>
        <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
          <button className="btn btn-ghost" onClick={() => setQuizOpen(true)}><I.spark size={16} /> Пройти стиль-квиз</button>
          <button className="btn btn-primary" onClick={() => setNewOpen(true)}><I.plus size={17} /> Новый проект</button>
        </div>
      </div>

      {/* ── сводная аналитика по проектам ── */}
      <div className="kpi-grid" style={{ display: "grid", gridTemplateColumns: "repeat(4,1fr)", gap: 14, marginBottom: 16 }}>
        {!sum && Array.from({ length: 4 }).map((_, i) => <div key={i} className="glass skel" style={{ borderRadius: "var(--r-lg)", height: 104 }} />)}
        {sum && sum.kpis.map((k) => <KpiCard key={k.key} k={k} />)}
      </div>
      <div className="chart-row" style={{ display: "grid", gridTemplateColumns: "1.4fr 1fr", gap: 16, marginBottom: 30 }}>
        <AnalyCard title="Бюджет по проектам" source="смета AIVibe" accent="var(--accent-2)">
          {sum ? <BarList data={sum.budgetByProject} color="var(--accent-2)" money /> : <ChartSkel h={120} />}
        </AnalyCard>
        <AnalyCard title="Статус проектов" source="портфель">
          {sum ? <div style={{ paddingTop: 4 }}><Donut data={sum.statusSplit} size={150} /></div> : <ChartSkel h={150} />}
        </AnalyCard>
      </div>

      <div className="proj-grid" style={{ display: "grid", gridTemplateColumns: "repeat(3,1fr)", gap: 18 }}>
        {!rows && Array.from({ length: 4 }).map((_, i) => <div key={i} className="glass skel" style={{ borderRadius: "var(--r-lg)", height: 280 }} />)}
        {rows && rows.map((p) => (
          <article key={p.id} className="glass news-card" style={{ borderRadius: "var(--r-lg)", overflow: "hidden", display: "flex", flexDirection: "column", cursor: "pointer" }} onClick={() => setOpenId(p.id)}>
            <div style={{ position: "relative", aspectRatio: "16/10", overflow: "hidden" }}>
              <Img src={PHOTOS[p.cover] || PHOTOS.living} label={p.room} />
              <span style={{ position: "absolute", top: 12, left: 12, padding: "5px 11px", borderRadius: 99, fontSize: 11.5, fontWeight: 700, background: "rgba(14,10,16,.62)", backdropFilter: "blur(6px)", border: "1px solid var(--hairline)", display: "flex", alignItems: "center", gap: 6 }}>
                <span style={{ width: 7, height: 7, borderRadius: "50%", background: statusColor[p.status] }} />{p.status}
              </span>
            </div>
            <div style={{ padding: 20, display: "flex", flexDirection: "column", gap: 12, flex: 1 }}>
              <div>
                <h3 style={{ fontSize: 18, fontWeight: 700, letterSpacing: "-0.01em" }}>{p.name}</h3>
                <div style={{ color: "var(--muted)", fontSize: 13.5, marginTop: 3 }}>{p.style} · {p.room}</div>
              </div>
              <div style={{ display: "flex", gap: 16, fontSize: 13, color: "var(--muted)", marginTop: "auto" }}>
                <span style={{ display: "flex", alignItems: "center", gap: 6 }}><I.ruler size={15} />{p.area} м²</span>
                <span style={{ display: "flex", alignItems: "center", gap: 6 }}><I.layers size={15} />{p.items} предм.</span>
              </div>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", paddingTop: 12, borderTop: "1px solid var(--hairline)" }}>
                <span style={{ fontWeight: 800, fontFamily: "var(--font-display)", fontSize: 16 }}>{fmtMoney(p.budget)}</span>
                <span className="btn btn-ghost" style={{ padding: "8px 14px", fontSize: 13 }}>Открыть <I.arrow size={14} /></span>
              </div>
            </div>
          </article>
        ))}
      </div>
      {openId && <ProjectDetail id={openId} initialStyle={openStyle} onClose={() => { setOpenId(null); setOpenStyle(null); }} />}
      {newOpen && <NewProjectModal onClose={() => setNewOpen(false)} onExample={() => { setNewOpen(false); setOpenId("p_1"); }} />}
      {quizOpen && <StyleQuiz onClose={() => { setQuizOpen(false); try { localStorage.setItem("aivibe_quiz_done", "1"); } catch (e) {} }} onDone={finishQuiz} />}
    </div>
  );
}

/* модалка «Новый проект» — объясняет путь скан → анализ → подбор */
function NewProjectModal({ onClose, onExample }) {
  const steps = [
    { icon: I.ruler, t: "Задайте габариты", s: "Загрузите план или введите размеры комнаты" },
    { icon: I.spark, t: "AI проанализирует", s: "Свет, пропорции, зоны и подходящие стили" },
    { icon: I.layers, t: "Смета под бюджет", s: "Спецификация с ценами по каталогу фабрик" },
  ];
  return (
    <div className="modal-back" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className="glass modal-card" style={{ borderRadius: "var(--r-xl)" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "22px 26px", borderBottom: "1px solid var(--hairline)" }}>
          <h3 className="display" style={{ fontSize: 21 }}>Новый проект</h3>
          <button className="icon-btn" onClick={onClose} aria-label="Закрыть"><I.close size={18} /></button>
        </div>
        <div style={{ padding: 26, display: "flex", flexDirection: "column", gap: 14 }}>
          <p style={{ color: "var(--muted)", fontSize: 14.5, lineHeight: 1.6 }}>Проект начинается с габаритов комнаты — загрузите план или введите размеры. Дальше всё собирает AI — от анализа до сметы.</p>
          {steps.map((st, i) => (
            <div key={i} style={{ display: "flex", gap: 14, alignItems: "center" }}>
              <span style={{ flex: "none", width: 44, height: 44, borderRadius: 12, background: "var(--surface-2)", color: "var(--accent)", display: "grid", placeItems: "center" }}><st.icon size={21} /></span>
              <div><div style={{ fontWeight: 700, fontSize: 15 }}>{st.t}</div><div style={{ color: "var(--muted)", fontSize: 13.5, marginTop: 2 }}>{st.s}</div></div>
            </div>
          ))}
        </div>
        <div style={{ display: "flex", justifyContent: "flex-end", gap: 10, padding: "18px 26px", borderTop: "1px solid var(--hairline)" }}>
          <button className="btn btn-ghost" onClick={onClose}>Позже</button>
          <button className="btn btn-primary" onClick={onExample}><I.arrow size={16} />Открыть пример проекта</button>
        </div>
      </div>
    </div>
  );
}

/* ---------------- ИЗБРАННОЕ / МУДБОРД ---------------- */
const FAV_MP = { f1: "Дубрава", f2: "Линея" };

function Favorites() {
  const [items, setItems] = useCV(null);
  const [room, setRoom] = useCV("Все");
  useCVE(() => { AIVibeAPI.favorites.list().then(setItems); }, []);

  const remove = async (id) => {
    setItems((arr) => arr.filter((f) => f.id !== id));   // оптимистично
    AIVibeAPI.favorites.remove(id);
  };

  const rooms = items ? ["Все", ...Array.from(new Set(items.map((f) => f.room)))] : ["Все"];
  const shown = items ? (room === "Все" ? items : items.filter((f) => f.room === room)) : null;
  const total = shown ? shown.reduce((s, f) => s + f.price, 0) : 0;
  const saved = shown ? shown.reduce((s, f) => s + ((f.old || f.price) - f.price), 0) : 0;

  return (
    <div className="reveal in" ref={useReveal()}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-end", marginBottom: 22, flexWrap: "wrap", gap: 14 }}>
        <div>
          <h1 className="display" style={{ fontSize: 30 }}>Избранное</h1>
          <p style={{ color: "var(--muted)", fontSize: 14.5, marginTop: 4 }}>Мудборд сохранённых вещей и готовый список покупок</p>
        </div>
        <div className="glass" style={{ display: "inline-flex", alignItems: "center", gap: 8, padding: "9px 15px", borderRadius: 99, fontSize: 13.5, fontWeight: 700 }}>
          <I.heart size={15} style={{ color: "var(--accent)" }} />{items ? items.length : "…"} в избранном
        </div>
      </div>

      {/* фильтр по комнатам */}
      <div className="fav-chips" style={{ display: "flex", gap: 8, flexWrap: "wrap", marginBottom: 20 }}>
        {rooms.map((r) => (
          <button key={r} onClick={() => setRoom(r)} aria-pressed={room === r} style={{ padding: "8px 15px", borderRadius: 99, fontSize: 13.5, fontWeight: 700, border: "1px solid var(--hairline)",
            background: room === r ? "var(--accent)" : "var(--glass-2)", color: room === r ? "#1a0d08" : "var(--muted)", transition: ".18s" }}>{r}</button>
        ))}
      </div>

      <div className="fav-layout" style={{ display: "grid", gridTemplateColumns: "1.55fr 1fr", gap: 22, alignItems: "start" }}>
        {/* мудборд */}
        <div>
          {!shown && <div className="glass skel" style={{ borderRadius: "var(--r-lg)", height: 460 }} />}
          {shown && shown.length === 0 && (
            <div className="glass" style={{ borderRadius: "var(--r-lg)", padding: 48, textAlign: "center", color: "var(--muted)" }}>
              <I.heart size={28} style={{ color: "var(--faint)" }} /><div style={{ marginTop: 10, fontSize: 14.5 }}>В этой комнате пока нет избранного.</div>
            </div>
          )}
          {shown && shown.length > 0 && (
            <div className="fav-board" style={{ columnCount: 2, columnGap: 14 }}>
              {shown.map((f, i) => <FavCard key={f.id} item={f} ar={["3 / 4", "4 / 5", "1 / 1", "5 / 6"][i % 4]} onRemove={() => remove(f.id)} />)}
            </div>
          )}
        </div>

        {/* шоп-лист */}
        <div className="glass fav-shop" style={{ borderRadius: "var(--r-xl)", padding: 24, position: "sticky", top: "calc(var(--nav-h) + 20px)" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 9, marginBottom: 16 }}>
            <I.cart size={18} style={{ color: "var(--accent)" }} />
            <h3 style={{ fontSize: 17, fontWeight: 700 }}>Список покупок</h3>
            <span style={{ marginLeft: "auto", fontSize: 13, color: "var(--faint)" }}>{shown ? shown.length : 0} шт.</span>
          </div>

          <div style={{ display: "flex", flexDirection: "column", maxHeight: 320, overflow: "auto", marginInline: -4, paddingInline: 4 }}>
            {!shown && Array.from({ length: 4 }).map((_, i) => <div key={i} className="skel" style={{ height: 56, borderRadius: 10, marginBottom: 8 }} />)}
            {shown && shown.map((f, i) => (
              <div key={f.id} style={{ display: "flex", alignItems: "center", gap: 12, padding: "11px 0", borderBottom: i === shown.length - 1 ? "none" : "1px solid var(--hairline)" }}>
                <div style={{ width: 46, height: 46, borderRadius: 9, overflow: "hidden", flex: "none" }}><Img src={f.img} label="" /></div>
                <div style={{ minWidth: 0, flex: 1 }}>
                  <div style={{ fontSize: 13.5, fontWeight: 600, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{f.title}</div>
                  <div style={{ fontSize: 12, color: "var(--faint)", marginTop: 2 }}>{FAV_MP[f.mp]}</div>
                </div>
                <div style={{ fontWeight: 700, fontSize: 13.5, whiteSpace: "nowrap" }}>{fmtMoney(f.price)}</div>
                <button className="icon-btn sm" title="Убрать" onClick={() => remove(f.id)} style={{ flex: "none" }}><I.close size={15} /></button>
              </div>
            ))}
          </div>

          <div style={{ borderTop: "1px solid var(--hairline)", marginTop: 14, paddingTop: 16, display: "flex", flexDirection: "column", gap: 8 }}>
            {saved > 0 && <div style={{ display: "flex", justifyContent: "space-between", fontSize: 13, color: "var(--accent-2)", fontWeight: 700 }}><span>Скидка по каталогу</span><span>−{fmtMoney(saved)}</span></div>}
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
              <span style={{ color: "var(--muted)", fontSize: 14 }}>Итого</span>
              <span className="display" style={{ fontSize: 24 }}>{fmtMoney(total)}</span>
            </div>
          </div>
          <button className="btn btn-primary btn-block" style={{ marginTop: 16 }}><I.layers size={16} />Перенести в проект</button>
          <button className="btn btn-ghost btn-block" style={{ marginTop: 10 }}>Поделиться доской</button>
        </div>
      </div>
    </div>
  );
}

function FavCard({ item, onRemove, ar }) {
  const disc = item.old && item.old > item.price ? Math.round((1 - item.price / item.old) * 100) : 0;
  return (
    <div className="glass" style={{ breakInside: "avoid", marginBottom: 14, borderRadius: "var(--r-lg)", overflow: "hidden", position: "relative" }}>
      <div style={{ position: "relative", aspectRatio: ar || "3 / 4" }}>
        <Img src={item.img} label={item.room} style={{ position: "absolute", inset: 0 }} />
        <div style={{ position: "absolute", inset: 0, background: "linear-gradient(180deg, transparent 45%, rgba(14,10,16,.78))" }} />
        <button onClick={onRemove} aria-label="Убрать из избранного" style={{ position: "absolute", top: 10, right: 10, width: 34, height: 34, borderRadius: "50%", background: "rgba(14,10,16,.6)", backdropFilter: "blur(6px)", border: "1px solid var(--hairline)", color: "var(--accent)", display: "grid", placeItems: "center" }}>
          <I.heart size={16} fill="var(--accent)" stroke="var(--accent)" />
        </button>
        <span className={"mp mp-badge " + item.mp} style={{ position: "absolute", top: 12, left: 12 }}>{FAV_MP[item.mp]}</span>
        <div style={{ position: "absolute", left: 13, right: 13, bottom: 12 }}>
          <div style={{ fontSize: 14, fontWeight: 700, lineHeight: 1.3, textShadow: "0 1px 8px rgba(0,0,0,.5)" }}>{item.title}</div>
          <div style={{ display: "flex", alignItems: "baseline", gap: 8, marginTop: 6 }}>
            <span style={{ fontFamily: "var(--font-display)", fontWeight: 800, fontSize: 16 }}>{fmtMoney(item.price)}</span>
            {disc > 0 && <span style={{ fontSize: 12, color: "var(--faint)", textDecoration: "line-through" }}>{fmtMoney(item.old)}</span>}
            {disc > 0 && <span style={{ marginLeft: "auto", fontSize: 11, fontWeight: 800, color: "var(--accent-2)" }}>−{disc}%</span>}
          </div>
        </div>
      </div>
    </div>
  );
}

window.Profile = Profile;
window.Projects = Projects;
window.Favorites = Favorites;
window.Toggle = Toggle;
window.NewProjectModal = NewProjectModal;
