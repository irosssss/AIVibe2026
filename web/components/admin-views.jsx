/* ============================================================
   AIVibe — Админка: CRUD новостей и управление пользователями
   ============================================================ */
const { useState: useAV, useEffect: useAVE } = React;

/* ------------------------- НОВОСТИ (CRUD) ------------------------- */
function NewsAdmin() {
  const [rows, setRows] = useAV(null);
  const [editing, setEditing] = useAV(null);   // объект новости | null
  const [busy, setBusy] = useAV(false);

  const load = () => AIVibeAPI.news.list().then(setRows);
  useAVE(() => { load(); }, []);

  const save = async (form) => {
    setBusy(true);
    if (form.id) await AIVibeAPI.news.update(form.id, form);
    else await AIVibeAPI.news.create(form);
    await load();
    setBusy(false); setEditing(null);
  };
  const remove = async (id) => {
    if (!window.confirm("Удалить новость? Действие необратимо.")) return;
    await AIVibeAPI.news.remove(id); load();
  };
  const toggleStatus = async (n) => {
    await AIVibeAPI.news.update(n.id, { status: n.status === "published" ? "draft" : "published" });
    load();
  };

  return (
    <div>
      <PageHead title="Новости дизайна" sub="Создание, редактирование и публикация материалов журнала"
        right={<button className="btn btn-primary" onClick={() => setEditing({ title: "", category: "Тренды 2026", excerpt: "", cover: "warm", status: "draft", date: new Date().toISOString().slice(0, 10), views: 0 })}><I.plus size={17} /> Новая новость</button>} />

      <div className="glass" style={{ borderRadius: "var(--r-lg)", overflow: "hidden" }}>
        <div className="tbl-head news-cols">
          <span>Материал</span><span>Категория</span><span>Статус</span><span>Просмотры</span><span>Дата</span><span></span>
        </div>
        {!rows && <div style={{ padding: 40, textAlign: "center", color: "var(--muted)" }}>Загрузка…</div>}
        {rows && rows.map((n) => (
          <div key={n.id} className="tbl-row news-cols">
            <div style={{ display: "flex", alignItems: "center", gap: 13, minWidth: 0 }}>
              <div style={{ width: 46, height: 46, borderRadius: 10, overflow: "hidden", flex: "none" }}><Img src={PHOTOS[n.cover] || PHOTOS.warm} label="" /></div>
              <div style={{ minWidth: 0 }}>
                <div style={{ fontWeight: 600, fontSize: 14.5, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{n.title}</div>
                <div style={{ fontSize: 12.5, color: "var(--faint)" }}>{n.author}</div>
              </div>
            </div>
            <span style={{ color: "var(--muted)", fontSize: 13.5 }}>{n.category}</span>
            <button onClick={() => toggleStatus(n)} className="status-pill" style={{ background: n.status === "published" ? "rgba(31,138,107,.16)" : "var(--glass-2)", color: n.status === "published" ? "var(--accent-2)" : "var(--muted)", borderColor: n.status === "published" ? "rgba(31,138,107,.34)" : "var(--hairline)" }}>
              <span style={{ width: 7, height: 7, borderRadius: "50%", background: n.status === "published" ? "var(--accent-2)" : "var(--faint)" }} />
              {n.status === "published" ? "Опубликовано" : "Черновик"}
            </button>
            <span style={{ fontSize: 13.5, color: "var(--muted)" }}>{fmt(n.views)}</span>
            <span style={{ fontSize: 13.5, color: "var(--muted)" }}>{new Date(n.date).toLocaleDateString("ru-RU", { day: "2-digit", month: "2-digit", year: "2-digit" })}</span>
            <div style={{ display: "flex", gap: 6, justifyContent: "flex-end" }}>
              <button className="icon-btn sm" title="Редактировать" onClick={() => setEditing(n)}><I.edit size={16} /></button>
              <button className="icon-btn sm danger" title="Удалить" onClick={() => remove(n.id)}><I.trash size={16} /></button>
            </div>
          </div>
        ))}
      </div>

      {editing && <NewsModal initial={editing} onClose={() => setEditing(null)} onSave={save} busy={busy} />}
    </div>
  );
}

function NewsModal({ initial, onClose, onSave, busy }) {
  const [form, setForm] = useAV(initial);
  const set = (k, v) => setForm((f) => ({ ...f, [k]: v }));
  const cats = ["Тренды 2026", "Технологии", "Стили", "Гайды", "Идеи", "Кейсы"];
  const covers = ["warm", "ar", "deco", "market", "light", "studio", "living"];
  return (
    <div className="modal-back" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className="glass modal-card" style={{ borderRadius: "var(--r-xl)" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "22px 26px", borderBottom: "1px solid var(--hairline)" }}>
          <h3 className="display" style={{ fontSize: 21 }}>{form.id ? "Редактировать новость" : "Новая новость"}</h3>
          <button className="icon-btn" onClick={onClose}><I.close size={18} /></button>
        </div>
        <div style={{ padding: 26, display: "flex", flexDirection: "column", gap: 16, maxHeight: "60vh", overflow: "auto" }}>
          <label><span className="lbl">Заголовок</span><input className="fld" value={form.title} onChange={(e) => set("title", e.target.value)} placeholder="Заголовок материала" /></label>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 14 }}>
            <label><span className="lbl">Категория</span>
              <select className="fld" value={form.category} onChange={(e) => set("category", e.target.value)}>{cats.map((c) => <option key={c}>{c}</option>)}</select>
            </label>
            <label><span className="lbl">Дата</span><input type="date" className="fld" value={form.date} onChange={(e) => set("date", e.target.value)} /></label>
          </div>
          <label><span className="lbl">Краткое описание</span><textarea className="fld" rows={3} value={form.excerpt} onChange={(e) => set("excerpt", e.target.value)} placeholder="Анонс в ленте" style={{ resize: "vertical" }} /></label>
          <div>
            <span className="lbl">Обложка</span>
            <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
              {covers.map((c) => (
                <button key={c} onClick={() => set("cover", c)} style={{ width: 70, height: 50, borderRadius: 10, overflow: "hidden", outline: form.cover === c ? "2px solid var(--accent)" : "1px solid var(--hairline)", outlineOffset: form.cover === c ? 1 : 0 }}>
                  <Img src={PHOTOS[c]} label="" />
                </button>
              ))}
            </div>
          </div>
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, padding: "18px 26px", borderTop: "1px solid var(--hairline)" }}>
          <label style={{ display: "flex", alignItems: "center", gap: 9, fontSize: 14, cursor: "pointer" }}>
            <input type="checkbox" checked={form.status === "published"} onChange={(e) => set("status", e.target.checked ? "published" : "draft")} style={{ width: 17, height: 17, accentColor: "var(--accent-2)" }} />
            Опубликовать сразу
          </label>
          <div style={{ display: "flex", gap: 10 }}>
            <button className="btn btn-ghost" onClick={onClose}>Отмена</button>
            <button className="btn btn-primary" disabled={busy || !form.title} onClick={() => onSave(form)}>{busy ? "Сохранение…" : "Сохранить"}</button>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ------------------------- ПОЛЬЗОВАТЕЛИ ------------------------- */
function UsersAdmin() {
  const [rows, setRows] = useAV(null);
  const [q, setQ] = useAV("");
  const load = () => AIVibeAPI.users.list().then(setRows);
  useAVE(() => { load(); }, []);

  const toggle = async (u) => { await AIVibeAPI.users.setStatus(u.id, u.status === "active" ? "blocked" : "active"); load(); };
  const filtered = rows ? rows.filter((u) => (u.name + u.email).toLowerCase().includes(q.toLowerCase())) : null;

  return (
    <div>
      <PageHead title="Пользователи" sub="Аккаунты, роли и доступ"
        right={<div className="glass" style={{ display: "flex", alignItems: "center", gap: 9, padding: "10px 15px", borderRadius: 99, minWidth: 230 }}>
          <I.search size={16} style={{ color: "var(--muted)" }} />
          <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Поиск по имени или e-mail" style={{ background: "none", border: "none", outline: "none", color: "var(--text)", fontSize: 14, width: "100%" }} />
        </div>} />

      <div className="glass" style={{ borderRadius: "var(--r-lg)", overflow: "hidden" }}>
        <div className="tbl-head user-cols">
          <span>Пользователь</span><span>Вход</span><span>Роль</span><span>Проекты</span><span>Статус</span><span></span>
        </div>
        {!filtered && <div style={{ padding: 40, textAlign: "center", color: "var(--muted)" }}>Загрузка…</div>}
        {filtered && filtered.map((u) => (
          <div key={u.id} className="tbl-row user-cols">
            <div style={{ display: "flex", alignItems: "center", gap: 12, minWidth: 0 }}>
              <Avatar user={u} size={38} />
              <div style={{ minWidth: 0 }}>
                <div style={{ fontWeight: 600, fontSize: 14.5, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{u.name}</div>
                <div style={{ fontSize: 12.5, color: "var(--faint)" }}>{u.email}</div>
              </div>
            </div>
            <span style={{ display: "inline-flex", alignItems: "center", gap: 7, fontSize: 13.5, color: "var(--muted)" }}>
              <span style={{ width: 8, height: 8, borderRadius: "50%", background: u.provider === "yandex" ? "#FC3F1D" : "#0077FF" }} />
              {u.provider === "yandex" ? "Яндекс ID" : "VK ID"}
            </span>
            <span>{u.role === "admin"
              ? <span className="status-pill" style={{ background: "rgba(226,85,43,.16)", color: "var(--accent)", borderColor: "rgba(226,85,43,.32)" }}>Админ</span>
              : <span style={{ fontSize: 13.5, color: "var(--muted)" }}>Пользователь</span>}</span>
            <span style={{ fontSize: 13.5, color: "var(--muted)" }}>{u.projects}</span>
            <span><span className="status-pill" style={{ background: u.status === "active" ? "rgba(31,138,107,.16)" : "rgba(226,85,43,.14)", color: u.status === "active" ? "var(--accent-2)" : "var(--accent)", borderColor: u.status === "active" ? "rgba(31,138,107,.34)" : "rgba(226,85,43,.3)" }}>
              <span style={{ width: 7, height: 7, borderRadius: "50%", background: u.status === "active" ? "var(--accent-2)" : "var(--accent)" }} />
              {u.status === "active" ? "Активен" : "Заблокирован"}</span></span>
            <div style={{ display: "flex", justifyContent: "flex-end" }}>
              <button className="btn btn-ghost" style={{ padding: "7px 13px", fontSize: 12.5 }} onClick={() => toggle(u)} disabled={u.role === "admin"}>
                {u.status === "active" ? "Заблокировать" : "Разблокировать"}
              </button>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

window.NewsAdmin = NewsAdmin;
window.UsersAdmin = UsersAdmin;
