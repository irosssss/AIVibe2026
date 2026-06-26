/* ============================================================
   AIVibe — единый mock-слой данных (AIVibeAPI)
   ------------------------------------------------------------
   Все экраны ходят ТОЛЬКО сюда. Сигнатуры методов совпадают с
   будущим реальным API (Yandex Cloud Functions + YDB), поэтому
   при подключении бэкенда UI переписывать не придётся — достаточно
   заменить тела методов на fetch(...).

   Точки замены помечены  // → API:  с предполагаемым эндпоинтом.
   ============================================================ */
(function () {
  const LATENCY = 420; // имитация сети
  const delay = (ms) => new Promise((r) => setTimeout(r, ms));
  const clone = (x) => JSON.parse(JSON.stringify(x));

  /* ----------------------------- DB (in-memory) ----------------------------- */
  const db = {
    session: null, // { user } | null

    users: [
      { id: "u_1", name: "Ирина Соколова", email: "irina@aivibe.ru", role: "admin", provider: "yandex", status: "active", joined: "2026-01-12", projects: 14, avatar: "#E2552B" },
      { id: "u_2", name: "Максим Орлов", email: "max.orlov@vk.com", role: "user", provider: "vk", status: "active", joined: "2026-02-03", projects: 6, avatar: "#6B9BE8" },
      { id: "u_3", name: "Алина Гусева", email: "alina.g@yandex.ru", role: "user", provider: "yandex", status: "active", joined: "2026-02-21", projects: 9, avatar: "#1F8A6B" },
      { id: "u_4", name: "Дмитрий Лебедев", email: "d.lebedev@vk.com", role: "user", provider: "vk", status: "blocked", joined: "2026-03-01", projects: 2, avatar: "#A6B24E" },
      { id: "u_5", name: "Полина Зайцева", email: "polina.z@yandex.ru", role: "user", provider: "yandex", status: "active", joined: "2026-03-18", projects: 11, avatar: "#F0764F" },
      { id: "u_6", name: "Артём Волков", email: "artem.v@vk.com", role: "user", provider: "vk", status: "active", joined: "2026-04-02", projects: 4, avatar: "#8a6fb0" },
      { id: "u_7", name: "Ева Морозова", email: "eva.m@yandex.ru", role: "user", provider: "yandex", status: "active", joined: "2026-04-27", projects: 7, avatar: "#6B9BE8" },
    ],

    news: [
      { id: "n_1", title: "Тёплый минимализм вытесняет холодный сканди", category: "Тренды 2026", excerpt: "Природные текстуры, терракота и приглушённый плюм — палитра года по версии дизайн-сообщества.", body: "Полный текст материала о тёплом минимализме...", cover: "warm", author: "Редакция AIVibe", date: "2026-05-28", status: "published", views: 4820 },
      { id: "n_2", title: "Почему диван «не встаёт»: проверка эргономики", category: "Технологии", excerpt: "Детерминированный движок ловит узкие проходы и конфликты зон до того, как смета уйдёт клиенту — разбор на примерах.", body: "Полный текст про проверку норм...", cover: "ar", author: "Ирина Соколова", date: "2026-05-21", status: "published", views: 7310 },
      { id: "n_3", title: "Neo Deco: геометрия и латунь возвращаются", category: "Стили", excerpt: "Веерные мотивы, рифлёные поверхности и глубокие винные оттенки в интерьере 2026.", body: "Полный текст про Neo Deco...", cover: "deco", author: "Алина Гусева", date: "2026-05-14", status: "published", views: 3950 },
      { id: "n_4", title: "Смета за минуту: как не считать предметы вручную", category: "Гайды", excerpt: "Движок собирает спецификацию с ценами и проверяет расстановку по нормам — разбор на реальном проекте.", body: "Полный текст гайда по смете и проверке норм...", cover: "market", author: "Максим Орлов", date: "2026-05-06", status: "published", views: 2640 },
      { id: "n_5", title: "Свет как материал: сценарии освещения от AI", category: "Идеи", excerpt: "Тёплые сценарии вечером, холодные утром — советник строит световые схемы под образ жизни.", body: "Полный текст про освещение...", cover: "light", author: "Полина Зайцева", date: "2026-04-29", status: "draft", views: 0 },
      { id: "n_6", title: "Маленькая студия: 24 м² без потери воздуха", category: "Кейсы", excerpt: "Зонирование, зеркала и встроенное хранение — реальный кейс перепланировки в AIVibe.", body: "Полный текст кейса...", cover: "studio", author: "Ева Морозова", date: "2026-04-20", status: "published", views: 5180 },
    ],

    // сохранённые проекты текущего пользователя
    projects: [
      { id: "p_1", name: "Гостиная на Патриках", room: "Гостиная", style: "Neo Deco", area: 38, items: 12, budget: 480000, updated: "2026-05-27", cover: "living", status: "В работе" },
      { id: "p_2", name: "Спальня — тёплый минимализм", room: "Спальня", style: "Тёплый минимализм", area: 18, items: 8, budget: 210000, updated: "2026-05-19", cover: "bedroom", status: "Готов" },
      { id: "p_3", name: "Кухня-столовая", room: "Кухня", style: "Сканди", area: 22, items: 15, budget: 365000, updated: "2026-05-11", cover: "kitchen", status: "В работе" },
      { id: "p_4", name: "Домашний кабинет", room: "Кабинет", style: "Индустриальный", area: 12, items: 6, budget: 145000, updated: "2026-04-30", cover: "office", status: "Архив" },
    ],

    // избранные товары (мудборд + шоп-лист)
    favorites: (function () {
      const fu = (id, w = 600) => `https://images.unsplash.com/${id}?q=80&w=${w}&auto=format&fit=crop`;
      return [
        { id: "f_1", title: "Модульный диван, букле", mp: "f2", price: 164900, old: 219000, room: "Гостиная", tag: "Neo Deco", img: fu("photo-1555041469-a586c61ea9bc") },
        { id: "f_2", title: "Люстра латунь + бра", mp: "f2", price: 57000, old: 79000, room: "Гостиная", tag: "Neo Deco", img: fu("photo-1524758631624-e2822e304c36") },
        { id: "f_3", title: "Ковёр шерсть, геометрия", mp: "f1", price: 41900, old: 58000, room: "Гостиная", tag: "Neo Deco", img: fu("photo-1531837763904-5b1b2f6c1b59") },
        { id: "f_4", title: "Кровать с мягким изголовьем", mp: "f2", price: 58900, old: 79000, room: "Спальня", tag: "Тёплый минимализм", img: fu("photo-1522771739844-6a9f6d5f14af") },
        { id: "f_5", title: "Лён: шторы, плед, подушки", mp: "f2", price: 32900, old: 45000, room: "Спальня", tag: "Тёплый минимализм", img: fu("photo-1616486338812-3dadae4b4ace") },
        { id: "f_6", title: "Стол дуб шпон, 160 см", mp: "f2", price: 44900, old: 61000, room: "Кухня", tag: "Сканди", img: fu("photo-1530018607912-eff2daa1bac4") },
        { id: "f_7", title: "Кресло, эргономика", mp: "f1", price: 32900, old: 45000, room: "Кабинет", tag: "Индустриальный", img: fu("photo-1505740420928-5e560c06d30e") },
        { id: "f_8", title: "Стол мрамор + металл", mp: "f1", price: 37900, old: 52000, room: "Гостиная", tag: "Neo Deco", img: fu("photo-1567538096630-e0c55bd6374c") },
        { id: "f_9", title: "Стеллаж лофт, металл + дерево", mp: "f2", price: 27900, old: 38000, room: "Кабинет", tag: "Индустриальный", img: fu("photo-1558997519-83ea9252edf8") },
      ];
    })(),
  };

  /* ----------------------------- AUTH ----------------------------- */
  // → API: POST /api/auth/oauth/{provider}  (обмен кода на токен → сессия/JWT)
  async function oauth(provider) {
    await delay(700);
    const base = provider === "yandex"
      ? { id: "u_1", name: "Ирина Соколова", email: "irina@aivibe.ru", role: "admin" }
      : { id: "u_2", name: "Максим Орлов", email: "max.orlov@vk.com", role: "user" };
    db.session = { user: { ...base, provider, avatar: provider === "yandex" ? "#E2552B" : "#6B9BE8" } };
    return clone(db.session);
  }

  /* ----------------------------- API surface ----------------------------- */
  window.AIVibeAPI = {
    /* — Аутентификация (OAuth Яндекс ID / VK ID) — */
    auth: {
      loginWithYandex: () => oauth("yandex"),   // → POST /api/auth/oauth/yandex
      loginWithVK: () => oauth("vk"),            // → POST /api/auth/oauth/vk
      getSession: async () => { await delay(120); return clone(db.session); }, // → GET /api/auth/session
      logout: async () => { await delay(120); db.session = null; return { ok: true }; }, // → POST /api/auth/logout
    },

    /* — Подписка / оплата (ЮKassa) — */
    billing: {
      // → API: POST /billing/create  (бэкенд web-billing → ЮKassa)
      // Честный плейсхолдер: пока магазин ЮKassa не подключён, успех не имитируем.
      createPayment: async ({ plan } = {}) => {
        await delay(300);
        return { ok: false, reason: "not-configured", plan: plan || "pro_month",
          message: "Оплата подключится после регистрации магазина ЮKassa (см. docs/AUTH_PAYMENT_INTEGRATION.md)." };
      },
    },

    /* — Профиль + сохранённые проекты — */
    profile: {
      get: async () => { await delay(LATENCY); return clone(db.session && db.session.user); }, // → GET /api/profile

      // → GET /api/profile/analytics  (персональная аналитика по проектам пользователя)
      // Паттерн «личный кабинет-аналитика»: KPI с дельтами, тренд активности,
      // распределение по стилям (доля бюджета), траты по проектам.
      analytics: async () => {
        await delay(LATENCY);
        const projects = db.projects;
        const totalBudget = projects.reduce((s, p) => s + p.budget, 0);
        const totalItems = projects.reduce((s, p) => s + p.items, 0);

        // доля бюджета по стилям (донат)
        const byStyle = {};
        projects.forEach((p) => { byStyle[p.style] = (byStyle[p.style] || 0) + p.budget; });
        const styleSplit = Object.entries(byStyle)
          .map(([label, v]) => ({ label, value: Math.round((v / totalBudget) * 100) }))
          .sort((a, b) => b.value - a.value);

        // траты по проектам (бары)
        const spendByProject = projects
          .map((p) => ({ label: p.name, value: p.budget }))
          .sort((a, b) => b.value - a.value);

        return clone({
          kpis: [
            { key: "scans", label: "Смет собрано", value: 12, delta: +25, unit: "" },
            { key: "ai", label: "AI-сессий с дизайнером", value: 38, delta: +31, unit: "" },
            { key: "proj", label: "Проектов сохранено", value: projects.length, delta: +1, unit: "abs" },
            { key: "spend", label: "Подобрано на сумму", value: totalBudget, delta: +18.4, unit: "₽" },
          ],
          activity: [4, 6, 5, 8, 7, 6, 9, 8, 11, 9, 12, 14],   // AI-сессии по неделям
          scans:    [1, 1, 2, 1, 2, 2, 1, 3, 2, 2, 3, 2],       // сметы по неделям
          styleSplit,
          spendByProject,
          totalItems,
        });
      },
    },
    projects: {
      list: async () => { await delay(LATENCY); return clone(db.projects); }, // → GET /api/projects

      // → GET /api/projects/summary  (сводная аналитика по сохранённым проектам)
      summary: async () => {
        await delay(LATENCY);
        const projects = db.projects;
        const totalBudget = projects.reduce((s, p) => s + p.budget, 0);
        const totalItems = projects.reduce((s, p) => s + p.items, 0);
        const avg = Math.round(totalBudget / projects.length);

        // распределение по статусу (донат)
        const byStatus = {};
        projects.forEach((p) => { byStatus[p.status] = (byStatus[p.status] || 0) + 1; });
        const statusOrder = ["В работе", "Готов", "Архив"];
        const statusSplit = statusOrder
          .filter((s) => byStatus[s])
          .map((s) => ({ label: s, value: Math.round((byStatus[s] / projects.length) * 100) }));

        return clone({
          kpis: [
            { key: "count", label: "Проектов", value: projects.length, unit: "abs" },
            { key: "budget", label: "Общий бюджет", value: totalBudget, unit: "₽" },
            { key: "avg", label: "Средний бюджет", value: avg, unit: "₽" },
            { key: "items", label: "Предметов подобрано", value: totalItems, unit: "abs" },
          ],
          statusSplit,
          budgetByProject: projects.map((p) => ({ label: p.name, value: p.budget })).sort((a, b) => b.value - a.value),
          areaByRoom: projects.map((p) => ({ label: p.room, value: p.area })).sort((a, b) => b.value - a.value),
        });
      },
    },

    /* — Избранное (мудборд + шоп-лист) — */
    favorites: {
      list: async () => { await delay(LATENCY); return clone(db.favorites); }, // → GET /api/favorites
      remove: async (id) => {                                                   // → DELETE /api/favorites/:id
        await delay(180);
        db.favorites = db.favorites.filter((f) => f.id !== id);
        return { ok: true };
      },
    },

    /* — Новости дизайна (CRUD) — */
    news: {
      list: async ({ status } = {}) => {            // → GET /api/news
        await delay(LATENCY);
        let rows = clone(db.news);
        if (status) rows = rows.filter((n) => n.status === status);
        return rows.sort((a, b) => b.date.localeCompare(a.date));
      },
      get: async (id) => { await delay(200); return clone(db.news.find((n) => n.id === id)); }, // → GET /api/news/:id
      create: async (payload) => {                  // → POST /api/news
        await delay(300);
        const row = { id: "n_" + Date.now(), views: 0, author: (db.session && db.session.user.name) || "Редакция AIVibe", ...payload };
        db.news.unshift(row);
        return clone(row);
      },
      update: async (id, patch) => {                // → PUT /api/news/:id
        await delay(300);
        const i = db.news.findIndex((n) => n.id === id);
        if (i >= 0) db.news[i] = { ...db.news[i], ...patch };
        return clone(db.news[i]);
      },
      remove: async (id) => {                        // → DELETE /api/news/:id
        await delay(300);
        db.news = db.news.filter((n) => n.id !== id);
        return { ok: true };
      },
    },

    /* — Пользователи (админка) — */
    users: {
      list: async () => { await delay(LATENCY); return clone(db.users); }, // → GET /api/admin/users
      setStatus: async (id, status) => {            // → PATCH /api/admin/users/:id
        await delay(250);
        const u = db.users.find((x) => x.id === id);
        if (u) u.status = status;
        return clone(u);
      },
    },

    /* — Аналитика для админ-дашборда (Яндекс Метрика / AppMetrica) — */
    analytics: {
      // → GET /api/admin/analytics?range=30d
      overview: async () => {
        await delay(LATENCY);
        const days = 14;
        const mkSeries = (b, v) => Array.from({ length: days }, (_, i) =>
          Math.round(b + Math.sin(i / 2) * v * 0.4 + Math.random() * v));
        return clone({
          kpis: [
            { key: "mau", label: "Активные за месяц", value: 18420, delta: +12.4, unit: "" },
            { key: "scans", label: "Смет собрано", value: 9260, delta: +8.1, unit: "" },
            { key: "ai", label: "AI-запросов советнику", value: 41730, delta: +21.7, unit: "" },
            { key: "conv", label: "Конверсия в проект", value: 34.6, delta: +3.2, unit: "%" },
          ],
          traffic: mkSeries(620, 240),      // визиты в день (Яндекс Метрика)
          aiEvents: mkSeries(1400, 700),    // события AI (AppMetrica)
          sources: [
            { label: "App Store", value: 42 },
            { label: "Прямые", value: 23 },
            { label: "Соцсети", value: 18 },
            { label: "Поиск", value: 11 },
            { label: "Реферал", value: 6 },
          ],
          styles: [
            { label: "Тёплый минимализм", value: 28 },
            { label: "Neo Deco", value: 22 },
            { label: "Сканди", value: 19 },
            { label: "Индустриальный", value: 16 },
            { label: "Бохо", value: 9 },
            { label: "Другое", value: 6 },
          ],
        });
      },
    },

    /* — Профиль репозитория для блока GitHub (mock, → GitHub REST API) — */
    repo: async () => {
      await delay(200);
      return clone({
        full_name: "irosssss/AIVibe2026",
        url: "https://github.com/irosssss/AIVibe2026",
        description: "iOS-приложение для дизайна интерьеров с AR и российским AI",
        language: "Swift",
        stars: 248, forks: 31, issues: 7,
        license: "© 2026 AIVibe",
        sessions: [
          { tag: "SESSION_07", title: "Смета · движок эргономики + каталог фабрик" },
          { tag: "SESSION_05", title: "AI Advisor · agent loop + skills" },
          { tag: "SESSION_03", title: "AR RoomScan · RoomPlan 2 + LiDAR" },
        ],
      });
    },
  };
})();
