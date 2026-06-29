/* ============================================================
   AIVibe — App shell: роутинг между промо / кабинет / админка
   + прототип-навигация (свитчер)
   ============================================================ */
const { useState: useApp, useEffect: useAppE } = React;

function App() {
  const [view, setView] = useApp("site");   // site | auth | cabinet | admin
  const [user, setUser] = useApp(null);

  // синтетический админ для прямого входа в админку из свитчера
  const ADMIN = { id: "u_1", name: "Ирина Соколова", email: "irina@aivibe.ru", role: "admin", provider: "yandex", avatar: "#E2552B" };

  const go = (v) => {
    if (v === "cabinet") return setView(user ? "cabinet" : "auth");
    if (v === "admin") {
      if (!user || user.role !== "admin") setUser(ADMIN);
      return setView("admin");
    }
    setView(v);
  };

  const onAuthed = (u) => { setUser(u); setView("cabinet"); };
  const onLogout = () => { AIVibeAPI.auth.logout(); setUser(null); setView("site"); };

  let screen;
  if (view === "auth") screen = <AuthScreen onAuthed={onAuthed} go={go} />;
  else if (view === "cabinet") screen = user ? <Cabinet user={user} onLogout={onLogout} go={go} /> : <AuthScreen onAuthed={onAuthed} go={go} />;
  else if (view === "admin") screen = <Admin user={user || ADMIN} onLogout={onLogout} go={go} />;
  else screen = <SitePage go={go} />;

  return (
    <React.Fragment>
      {screen}
      <ProtoSwitch view={view} go={go} user={user} />
    </React.Fragment>
  );
}

/* свитчер областей прототипа */
function ProtoSwitch({ view, go, user }) {
  const cur = view === "auth" ? "cabinet" : view;
  const items = [["site", "Промо"], ["cabinet", "Кабинет"], ["admin", "Админка"]];
  return (
    <div className="proto-switch" role="tablist" aria-label="Навигация по прототипу">
      <span className="pl">AIVibe</span>
      {items.map(([k, t]) => (
        <button key={k} className={cur === k ? "on" : ""} onClick={() => go(k)} role="tab" aria-selected={cur === k}>{t}</button>
      ))}
    </div>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
