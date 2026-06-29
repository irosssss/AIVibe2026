/* ============================================================
   AIVibe — ПРОМО-САЙТ
   Nav · Hero · How-it-works (scroll-сторителлинг) · Bento ·
   Новости · GitHub · Footer
   ============================================================ */
const { useState: useStateS, useEffect: useEffectS, useRef: useRefS } = React;

/* нейтральные стоковые фото интерьеров (с graceful fallback на плейсхолдер) */
const U = (id, w = 1100) => `https://images.unsplash.com/${id}?q=80&w=${w}&auto=format&fit=crop`;
const PHOTOS = {
  hero:    U("photo-1618221195710-dd6b41faaea6", 1300),
  living:  U("photo-1586023492125-27b2c045efd7"),
  bedroom: U("photo-1505693416388-ac5ce068fe85"),
  kitchen: U("photo-1556911220-bff31c812dba"),
  office:  U("photo-1593476550610-87baa860004a"),
  deco:    U("photo-1618220179428-22790b461013"),
  studio:  U("photo-1502672260266-1c1ef2d93688"),
  light:   U("photo-1540932239986-30128078f3c5"),
  market:  U("photo-1540574163026-643ea20ade25"),
  warm:    U("photo-1567016432779-094069958ea5"),
  ar:      U("photo-1631679706909-1844bbd07221"),
};
window.PHOTOS = PHOTOS;

/* --------------------------------------------------------------
   NAV
-------------------------------------------------------------- */
function SiteNav({ go }) {
  const [solid, setSolid] = useStateS(false);
  const [open, setOpen] = useStateS(false);
  useEffectS(() => {
    const f = () => setSolid(window.scrollY > 40);
    f(); window.addEventListener("scroll", f, { passive: true });
    return () => window.removeEventListener("scroll", f);
  }, []);
  // блокируем прокрутку фона, пока открыто мобильное меню
  useEffectS(() => {
    document.body.style.overflow = open ? "hidden" : "";
    return () => { document.body.style.overflow = ""; };
  }, [open]);
  const links = [["Возможности", "#features"], ["Как работает", "#how"], ["Новости", "#news"]];
  const jump = (h) => { setOpen(false); document.querySelector(h)?.scrollIntoView({ behavior: "smooth" }); };
  return (
    <nav style={{ position: "fixed", top: 0, left: 0, right: 0, zIndex: 90,
      height: "var(--nav-h)", transition: "background .3s, border-color .3s, backdrop-filter .3s",
      background: (solid || open) ? "rgba(14,10,16,0.82)" : "transparent",
      backdropFilter: (solid || open) ? "blur(16px)" : "none", WebkitBackdropFilter: (solid || open) ? "blur(16px)" : "none",
      borderBottom: `1px solid ${(solid || open) ? "var(--hairline)" : "transparent"}` }}>
      <div className="container" style={{ height: "100%", display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <Logo size={25} onClick={() => window.scrollTo({ top: 0 })} />
        <div className="site-navlinks" style={{ display: "flex", gap: 34 }}>
          {links.map(([t, h]) => (
            <a key={h} href={h} style={{ color: "var(--muted)", fontSize: 15, fontWeight: 600, transition: ".2s" }}
               onMouseEnter={(e) => (e.target.style.color = "var(--text)")}
               onMouseLeave={(e) => (e.target.style.color = "var(--muted)")}>{t}</a>
          ))}
        </div>
        <div style={{ display: "flex", gap: 12, alignItems: "center" }}>
          <button className="btn btn-ghost site-cta" style={{ padding: "11px 20px" }} onClick={() => go("auth")}>Войти</button>
          <button className="btn btn-primary site-cta" style={{ padding: "11px 20px" }} onClick={() => go("auth")}>
            <I.layers size={17} /> Собрать смету
          </button>
          {/* бургер — только на мобильных (через CSS) */}
          <button className="icon-btn nav-burger" aria-label="Меню" aria-expanded={open} onClick={() => setOpen((o) => !o)}>
            {open ? <I.close size={20} /> : <Icon size={20} d="M4 7h16M4 12h16M4 17h16" />}
          </button>
        </div>
      </div>

      {/* мобильное выпадающее меню */}
      <div className="nav-sheet" data-open={open ? "1" : "0"}>
        <div style={{ display: "flex", flexDirection: "column", padding: "10px 0 18px" }}>
          {links.map(([t, h]) => (
            <button key={h} onClick={() => jump(h)} style={{ textAlign: "left", padding: "15px 4px", fontSize: 19, fontWeight: 700,
              fontFamily: "var(--font-display)", letterSpacing: "-0.01em", borderBottom: "1px solid var(--hairline-2)", color: "var(--text)" }}>{t}</button>
          ))}
          <div style={{ display: "flex", flexDirection: "column", gap: 12, marginTop: 22 }}>
            <button className="btn btn-primary btn-block" style={{ padding: "15px" }} onClick={() => { setOpen(false); go("auth"); }}>
              <I.layers size={18} /> Собрать смету
            </button>
            <button className="btn btn-ghost btn-block" style={{ padding: "15px" }} onClick={() => { setOpen(false); go("auth"); }}>Личный кабинет</button>
          </div>
        </div>
      </div>
    </nav>
  );
}

/* --------------------------------------------------------------
   HERO — кинетическая типографика + абстрактные glass-визуалы
-------------------------------------------------------------- */
function Hero({ go }) {
  return (
    <header className="minh-screen" style={{ position: "relative", display: "flex", alignItems: "center", paddingTop: "var(--nav-h)", overflow: "hidden" }}>
      <div className="container hero-grid" style={{ display: "grid", gridTemplateColumns: "1.05fr 0.95fr", gap: 56, alignItems: "center", position: "relative", zIndex: 2, paddingBlock: "clamp(40px,8vh,90px)" }}>
        <div>
          <div className="glass" style={{ display: "inline-flex", alignItems: "center", gap: 10, padding: "9px 16px", borderRadius: "var(--r-pill)", marginBottom: 30, fontSize: 13.5 }}>
            <span style={{ width: 8, height: 8, borderRadius: "50%", background: "var(--accent-2)", boxShadow: "var(--glow-jade)" }} />
            Для дизайнеров · смета и проверка норм
          </div>
          <h1 className="display hero-h1" style={{ fontSize: "clamp(44px, 5.7vw, 86px)", lineHeight: 0.98, letterSpacing: "-0.04em" }}>
            <span style={{ display: "block" }}>Спецификация,</span>
            <span style={{ display: "block" }}>которая <span style={{ color: "var(--accent)" }}>сходится</span></span>
            <span style={{ display: "block", color: "var(--muted)", WebkitTextStroke: "1px var(--hairline)" }}>сама</span>
          </h1>
          <p style={{ marginTop: 28, color: "var(--muted)", maxWidth: 540, fontSize: 19, lineHeight: 1.7 }}>
            Загрузите габариты комнаты, бюджет и стиль — AIVibe соберёт смету с артикулами и ценами и проверит расстановку по нормам эргономики. То, на что уходит вечер в таблицах, — за минуту.
          </p>
          <div style={{ marginTop: 36, display: "flex", gap: 14, flexWrap: "wrap" }} id="download">
            <button className="btn btn-primary" style={{ padding: "16px 28px", fontSize: 16 }} onClick={() => go("auth")}><I.layers size={19} /> Собрать смету</button>
            <a className="btn btn-ghost" style={{ padding: "16px 28px", fontSize: 16 }} href="#how">Как это работает <I.arrow size={17} /></a>
          </div>
          <div style={{ marginTop: 52, display: "flex", gap: 44, flexWrap: "wrap" }}>
            {[["1 мин", "Смета вместо вечера"], ["100%", "Предметов с ценой"], ["3", "Бюджета на выбор"]].map(([v, l]) => (
              <div key={l}>
                <div className="display" style={{ fontSize: 34 }}>{v}</div>
                <div style={{ color: "var(--muted)", fontSize: 14, marginTop: 4 }}>{l}</div>
              </div>
            ))}
          </div>
        </div>
        <HeroVisual />
      </div>
      <div style={{ position: "absolute", bottom: 26, left: "50%", transform: "translateX(-50%)", color: "var(--faint)", fontSize: 12, letterSpacing: ".2em", textTransform: "uppercase", display: "flex", flexDirection: "column", alignItems: "center", gap: 8 }}>
        прокрутите
        <span style={{ width: 1, height: 34, background: "linear-gradient(var(--accent), transparent)" }} />
      </div>
    </header>
  );
}

/* Абстрактный AR-визуал: «комната» + парящие стеклянные карточки */
function HeroVisual() {
  return (
    <div className="hero-visual" style={{ position: "relative", height: 600 }}>
      {/* основная панель-сцена */}
      <div className="glass" style={{ position: "absolute", inset: "40px 0 40px 30px", borderRadius: "var(--r-xl)", overflow: "hidden", boxShadow: "var(--shadow-pop)" }}>
        <Img src={PHOTOS.hero} label="визуализация интерьера" />
        <div style={{ position: "absolute", inset: 0, background: "linear-gradient(180deg, rgba(14,10,16,.1), rgba(14,10,16,.65))" }} />
        {/* скан-сетка */}
        <div style={{ position: "absolute", inset: 0, backgroundImage: "linear-gradient(rgba(31,138,107,.18) 1px,transparent 1px),linear-gradient(90deg,rgba(31,138,107,.18) 1px,transparent 1px)", backgroundSize: "34px 34px", maskImage: "linear-gradient(120deg,#000,transparent 75%)" }} />
        <div className="scan-sweep" style={{ position: "absolute", left: 0, right: 0, height: 60, background: "linear-gradient(transparent, rgba(31,138,107,.35), transparent)" }} />
        {/* угловые маркеры AR */}
        {[[18, 18], [18, "auto"], ["auto", 18], ["auto", "auto"]].map(([t, l], i) => (
          <span key={i} style={{ position: "absolute", top: t === "auto" ? "auto" : t, bottom: t === "auto" ? 18 : "auto", left: l === "auto" ? "auto" : l, right: l === "auto" ? 18 : "auto", width: 22, height: 22, border: "2px solid var(--accent-2)", borderRadius: 5, opacity: .85,
            borderRightColor: i % 2 ? "var(--accent-2)" : "transparent", borderBottomColor: i < 2 ? "transparent" : "var(--accent-2)" }} />
        ))}
      </div>
      {/* верхняя карточка-статус */}
      <div className="glass float-a" style={{ position: "absolute", top: 18, left: -6, padding: "13px 17px", borderRadius: "var(--r-md)", display: "flex", alignItems: "center", gap: 11, fontSize: 13.5, fontWeight: 600 }}>
        <span style={{ width: 9, height: 9, borderRadius: "50%", background: "var(--accent-2)", boxShadow: "var(--glow-jade)" }} />
        Эргономика · проверено
      </div>
      {/* нижняя AI-карточка */}
      <div className="glass float-b" style={{ position: "absolute", bottom: 14, right: -10, width: 270, padding: 18, borderRadius: "var(--r-lg)", boxShadow: "var(--shadow-card)" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 9 }}>
          <I.layers size={16} style={{ color: "var(--accent)" }} />
          <span style={{ fontSize: 12, fontWeight: 700, letterSpacing: ".08em", textTransform: "uppercase", color: "var(--accent)" }}>Смета AIVibe</span>
        </div>
        <p style={{ fontSize: 14, lineHeight: 1.55, color: "var(--text)" }}>38 позиций на 1 240 000 ₽. Проход у дивана 78 см — в норме.</p>
      </div>
    </div>
  );
}

window.SiteNav = SiteNav;
window.Hero = Hero;
