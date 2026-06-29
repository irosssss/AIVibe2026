/* ============================================================
   AIVibe — ЛИЧНЫЙ КАБИНЕТ
   Вход (OAuth Яндекс ID / VK ID) · Профиль · Сохранённые проекты
   ============================================================ */
const { useState: useC, useEffect: useCE } = React;

/* провайдерские кнопки */
function YandexBtn({ onClick, loading }) {
  return (
    <button className="btn btn-block oauth-btn" onClick={onClick} disabled={loading}
      style={{ padding: "15px 20px", background: "#FC3F1D", color: "#fff", fontSize: 15.5 }}>
      <span style={{ fontWeight: 900, fontSize: 19, fontFamily: "Arial,sans-serif", marginRight: 2 }}>Я</span>
      Войти через Яндекс ID
    </button>
  );
}
function VKBtn({ onClick, loading }) {
  return (
    <button className="btn btn-block oauth-btn" onClick={onClick} disabled={loading}
      style={{ padding: "15px 20px", background: "#0077FF", color: "#fff", fontSize: 15.5 }}>
      <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M13.2 17.5c-5.3 0-8.7-3.7-8.8-9.8h2.8c.1 4.5 2.2 6.4 3.7 6.8V7.7h2.7v3.9c1.5-.2 3.1-1.9 3.6-3.9h2.7c-.4 2.5-2 4.2-3.2 4.9 1.2.6 3 2.1 3.7 4.9h-3c-.5-1.8-1.9-3.2-3.8-3.4v3.4z" /></svg>
      Войти через VK ID
    </button>
  );
}

/* ---------------- ЭКРАН ВХОДА / РЕГИСТРАЦИИ ---------------- */
function AuthScreen({ onAuthed, go }) {
  const [mode, setMode] = useC("login");      // login | register
  const [loading, setLoading] = useC(null);   // 'yandex' | 'vk' | null

  const login = async (provider) => {
    setLoading(provider);
    const ses = await (provider === "yandex" ? AIVibeAPI.auth.loginWithYandex() : AIVibeAPI.auth.loginWithVK());
    setLoading(null);
    onAuthed(ses.user);
  };

  return (
    <div className="auth-wrap minh-screen" style={{ display: "grid", gridTemplateColumns: "1.05fr 0.95fr" }}>
      {/* левая — бренд-визуал */}
      <div className="auth-aside" style={{ position: "relative", overflow: "hidden", padding: "clamp(36px,5vw,64px)", display: "flex", flexDirection: "column", justifyContent: "space-between", borderRight: "1px solid var(--hairline)" }}>
        <Img src={PHOTOS.deco} label="интерьер" style={{ position: "absolute", inset: 0 }} />
        <div style={{ position: "absolute", inset: 0, background: "linear-gradient(160deg, rgba(14,10,16,.72), rgba(36,23,38,.9))" }} />
        <div style={{ position: "relative", zIndex: 2 }}><Logo size={27} onClick={() => go("site")} /></div>
        <div style={{ position: "relative", zIndex: 2 }}>
          <h2 className="display" style={{ fontSize: "clamp(30px,3.4vw,46px)", lineHeight: 1 }}>С возвращением<br />в студию</h2>
          <p style={{ color: "var(--muted)", marginTop: 18, maxWidth: 380, fontSize: 15.5, lineHeight: 1.6 }}>
            Ваши проекты, сметы и переписка с AI-дизайнером — синхронизированы и под рукой.
          </p>
          <div style={{ display: "flex", gap: 26, marginTop: 30 }}>
            {[["4", "проекта"], ["38", "AI-сессий"], ["12", "смет"]].map(([v, l]) => (
              <div key={l}><div className="display" style={{ fontSize: 26 }}>{v}</div><div style={{ color: "var(--muted)", fontSize: 13 }}>{l}</div></div>
            ))}
          </div>
        </div>
      </div>

      {/* правая — форма */}
      <div style={{ display: "flex", alignItems: "center", justifyContent: "center", padding: "clamp(28px,4vw,56px)" }}>
        <div style={{ width: "min(400px, 100%)" }}>
          <div style={{ display: "flex", gap: 4, padding: 4, background: "var(--glass-2)", border: "1px solid var(--hairline)", borderRadius: 99, marginBottom: 30 }}>
            {[["login", "Вход"], ["register", "Регистрация"]].map(([k, t]) => (
              <button key={k} onClick={() => setMode(k)} style={{ flex: 1, padding: "10px", borderRadius: 99, fontWeight: 700, fontSize: 14,
                background: mode === k ? "var(--accent)" : "transparent", color: mode === k ? "#1a0d08" : "var(--muted)", transition: ".2s" }}>{t}</button>
            ))}
          </div>

          <h1 className="display" style={{ fontSize: 30, marginBottom: 8 }}>{mode === "login" ? "Вход в AIVibe" : "Создать аккаунт"}</h1>
          <p style={{ color: "var(--muted)", fontSize: 14.5, marginBottom: 26 }}>{mode === "login" ? "Войдите через российские сервисы — быстро и без пароля." : "Регистрация в один тап через Яндекс ID или VK ID."}</p>

          <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
            <YandexBtn onClick={() => login("yandex")} loading={loading === "yandex"} />
            <VKBtn onClick={() => login("vk")} loading={loading === "vk"} />
          </div>

          {loading && <div style={{ marginTop: 16, fontSize: 13.5, color: "var(--accent-2)", display: "flex", alignItems: "center", gap: 8 }}><span className="spin" />Авторизация через {loading === "yandex" ? "Яндекс ID" : "VK ID"}…</div>}

          <div style={{ display: "flex", alignItems: "center", gap: 14, margin: "26px 0", color: "var(--faint)", fontSize: 12.5 }}>
            <span style={{ flex: 1, height: 1, background: "var(--hairline)" }} />или по e-mail<span style={{ flex: 1, height: 1, background: "var(--hairline)" }} />
          </div>

          <div style={{ display: "flex", flexDirection: "column", gap: 12, opacity: .9 }}>
            {mode === "register" && <Field label="Имя" placeholder="Как к вам обращаться" />}
            <Field label="E-mail" placeholder="you@example.ru" type="email" />
            <Field label="Пароль" placeholder="••••••••" type="password" />
            <button className="btn btn-ghost btn-block" style={{ padding: "14px", marginTop: 4 }} onClick={() => login("yandex")}>
              {mode === "login" ? "Войти" : "Зарегистрироваться"}
            </button>
          </div>

          <p style={{ color: "var(--faint)", fontSize: 12.5, marginTop: 22, textAlign: "center", lineHeight: 1.5 }}>
            Продолжая, вы соглашаетесь с условиями и политикой конфиденциальности AIVibe.
          </p>
          <div style={{ textAlign: "center", marginTop: 14 }}>
            <button onClick={() => go("site")} style={{ color: "var(--muted)", fontSize: 13.5, textDecoration: "underline" }}>← На главную</button>
          </div>
        </div>
      </div>
    </div>
  );
}

function Field({ label, ...p }) {
  return (
    <label style={{ display: "block" }}>
      <span style={{ display: "block", fontSize: 13, color: "var(--muted)", marginBottom: 7, fontWeight: 600 }}>{label}</span>
      <input {...p} className="fld" />
    </label>
  );
}

/* ---------------- КАБИНЕТ (профиль + проекты) ---------------- */
function Cabinet({ user, onLogout, go }) {
  const [tab, setTab] = useC("profile");
  return (
    <div className="minh-screen">
      <AppTopBar user={user} onLogout={onLogout} go={go}
        tabs={[["profile", "Профиль"], ["projects", "Мои проекты"], ["favorites", "Избранное"]]} tab={tab} setTab={setTab} />
      <main className="container" style={{ paddingBlock: "clamp(28px,4vh,48px)", paddingTop: "calc(var(--nav-h) + 28px)" }}>
        {tab === "profile" ? <Profile user={user} /> : tab === "favorites" ? <Favorites /> : <Projects />}
      </main>
    </div>
  );
}

/* верхняя панель приложения (кабинет) */
function AppTopBar({ user, onLogout, go, tabs, tab, setTab }) {
  return (
    <header style={{ position: "fixed", top: 0, left: 0, right: 0, zIndex: 80, height: "var(--nav-h)", background: "rgba(14,10,16,.78)", backdropFilter: "blur(16px)", borderBottom: "1px solid var(--hairline)" }}>
      <div className="container" style={{ height: "100%", display: "flex", alignItems: "center", justifyContent: "space-between", gap: 20 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 28 }}>
          <Logo size={23} onClick={() => go("site")} />
          {tabs && (
            <div className="cab-tabs" style={{ display: "flex", gap: 4, padding: 4, background: "var(--glass-2)", borderRadius: 99, border: "1px solid var(--hairline)" }}>
              {tabs.map(([k, t]) => (
                <button key={k} onClick={() => setTab(k)} aria-current={tab === k ? "page" : undefined} style={{ padding: "8px 16px", borderRadius: 99, fontWeight: 700, fontSize: 13.5,
                  background: tab === k ? "var(--surface-2)" : "transparent", color: tab === k ? "var(--text)" : "var(--muted)" }}>{t}</button>
              ))}
            </div>
          )}
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
          <Avatar user={user} size={36} />
          <div className="cab-username" style={{ lineHeight: 1.2 }}>
            <div style={{ fontWeight: 700, fontSize: 14 }}>{user.name}</div>
            <div style={{ fontSize: 12, color: "var(--muted)" }}>{user.provider === "yandex" ? "Яндекс ID" : "VK ID"}</div>
          </div>
          <button className="icon-btn" title="Выйти" onClick={onLogout}><I.logout size={18} /></button>
        </div>
      </div>
    </header>
  );
}

function Avatar({ user, size = 40 }) {
  const initials = user.name.split(" ").map((w) => w[0]).slice(0, 2).join("");
  return (
    <div style={{ width: size, height: size, borderRadius: "50%", background: user.avatar || "var(--accent)", color: "#1a0d08",
      display: "grid", placeItems: "center", fontWeight: 800, fontSize: size * 0.36, flex: "none", fontFamily: "var(--font-display)" }}>{initials}</div>
  );
}

window.AuthScreen = AuthScreen;
window.Cabinet = Cabinet;
window.AppTopBar = AppTopBar;
window.Avatar = Avatar;
window.Field = Field;
