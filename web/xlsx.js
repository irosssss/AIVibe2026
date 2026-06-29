/* ============================================================
   AIVibe — выгрузка сметы-комплектации в Excel (SheetJS, client-side)
   Экспортирует window.AIVibeXLSX.exportRoomSpec(...)
   Структура книги:
     • «Свод»        — итоги по помещениям и по разделам + бюджет;
     • «Все позиции» — плоская мастер-таблица (фильтр/сводная по любой оси);
     • лист на каждую комнату — детально, с итогом по комнате.
   Везде две цены: себестоимость (фабрика) и цена клиента (с наценкой).
   Бэклог §9 docs/SMETA_BENCHMARK_2026-06.md — вход в рабочий процесс дизайнера.
   ============================================================ */
(function () {
  const MONEY = '#,##0" ₽"';            // формат суммы (разделитель тысяч — по локали Excel)

  // SheetJS запрещает в имени листа символы \ / ? * [ ] : и длину > 31
  const cleanName = (s) => String(s).replace(/[\\/?*[\]:]/g, " ").replace(/\s+/g, " ").trim().slice(0, 31) || "Лист";

  // ширины колонок (в символах)
  const setCols = (ws, widths) => { ws["!cols"] = widths.map((w) => ({ wch: w })); };

  // денежный формат на перечисленные ячейки [r,c]
  const fmtMoney = (ws, cells) => cells.forEach(([r, c]) => {
    const ref = XLSX.utils.encode_cell({ r, c });
    if (ws[ref] && typeof ws[ref].v === "number") ws[ref].z = MONEY;
  });

  // денежный формат на колонки cols в диапазоне строк [r0..r1] (нечисловые пропускаются)
  const fmtMoneyCols = (ws, cols, r0, r1) => {
    const cells = [];
    for (let r = r0; r <= r1; r++) for (const c of cols) cells.push([r, c]);
    fmtMoney(ws, cells);
  };

  function exportRoomSpec({ project, area, rooms, grand, markupPct, clientTotal, budget }) {
    if (!window.XLSX) { alert("Excel-библиотека ещё загружается — попробуйте через секунду."); return false; }
    rooms = rooms || [];
    const mk = 1 + (markupPct || 0) / 100;
    const lineCost = (it) => it.price * (it.qty || 1);
    const roomCost = (r) => r.items.reduce((s, it) => s + lineCost(it), 0);
    const client = (n) => Math.round(n * mk);

    const wb = XLSX.utils.book_new();
    const used = new Set();
    const uniqueSheet = (s) => {
      let name = cleanName(s), i = 2;
      while (used.has(name)) { const suf = " (" + i++ + ")"; name = cleanName(s).slice(0, 31 - suf.length) + suf; }
      used.add(name);
      return name;
    };

    /* ---------- Лист «Свод» ---------- */
    const over = grand > budget;
    const svod = [], mc = [];
    const push = (row) => { svod.push(row); return svod.length - 1; };

    push(["AIVibe — смета-комплектация"]);
    push([project || "Проект", "", area ? area + " м²" : ""]);
    push([]);
    push(["Наценка дизайнера, %", markupPct || 0]);   // процент, не деньги
    push([]);
    push(["По помещениям", "Себестоимость", "Для клиента"]);
    rooms.forEach((r) => {
      const c = roomCost(r);
      const ri = push([r.name + (r.area ? "  ·  " + r.area + " м²" : ""), c, client(c)]);
      mc.push([ri, 1], [ri, 2]);
    });
    { const ri = push(["Итого", grand, clientTotal]); mc.push([ri, 1], [ri, 2]); }
    push([]);
    // по разделам (закупочным категориям) — по убыванию суммы
    const byCat = {};
    rooms.forEach((r) => r.items.forEach((it) => { const k = it.cat || "—"; byCat[k] = (byCat[k] || 0) + lineCost(it); }));
    push(["По разделам", "Себестоимость", "Для клиента"]);
    Object.keys(byCat).sort((a, b) => byCat[b] - byCat[a]).forEach((cat) => {
      const ri = push([cat, byCat[cat], client(byCat[cat])]);
      mc.push([ri, 1], [ri, 2]);
    });
    push([]);
    { const ri = push(["Бюджет проекта", budget]); mc.push([ri, 1]); }
    { const ri = push([over ? "Превышение бюджета" : "Остаток бюджета", Math.abs(budget - grand)]); mc.push([ri, 1]); }

    const wsS = XLSX.utils.aoa_to_sheet(svod);
    setCols(wsS, [42, 16, 16]);
    fmtMoney(wsS, mc);
    XLSX.utils.book_append_sheet(wb, wsS, uniqueSheet("Свод"));

    /* ---------- Лист «Все позиции» (плоская мастер-таблица) ---------- */
    const allHead = ["№", "Помещение", "Раздел", "Наименование", "Кол-во", "Цена, ₽", "Сумма, ₽", "Цена клиенту, ₽", "Сумма клиенту, ₽"];
    const all = [allHead];
    let n = 0;
    rooms.forEach((r) => r.items.forEach((it) => {
      const lc = lineCost(it);
      all.push([++n, r.name, it.cat || "", it.title, it.qty || 1, it.price, lc, client(it.price), client(lc)]);
    }));
    all.push(["", "", "", "Итого", "", "", grand, "", clientTotal]);
    const wsA = XLSX.utils.aoa_to_sheet(all);
    setCols(wsA, [5, 18, 16, 46, 7, 13, 14, 15, 16]);
    fmtMoneyCols(wsA, [5, 6, 7, 8], 1, all.length - 1);
    wsA["!autofilter"] = { ref: "A1:I1" };   // фильтр по шапке — дизайнер крутит сводную как хочет
    XLSX.utils.book_append_sheet(wb, wsA, uniqueSheet("Все позиции"));

    /* ---------- Лист на каждую комнату ---------- */
    const rHead = ["№", "Раздел", "Наименование", "Кол-во", "Цена, ₽", "Сумма, ₽", "Цена клиенту, ₽", "Сумма клиенту, ₽"];
    rooms.forEach((r) => {
      const rows = [[r.name + (r.area ? "  ·  " + r.area + " м²" : "")], [], rHead];
      let m = 0;
      r.items.forEach((it) => {
        const lc = lineCost(it);
        rows.push([++m, it.cat || "", it.title, it.qty || 1, it.price, lc, client(it.price), client(lc)]);
      });
      const rc = roomCost(r);
      rows.push(["", "", "Итого по комнате", "", "", rc, "", client(rc)]);
      const ws = XLSX.utils.aoa_to_sheet(rows);
      setCols(ws, [5, 16, 46, 7, 13, 14, 15, 16]);
      fmtMoneyCols(ws, [4, 5, 6, 7], 2, rows.length - 1);
      XLSX.utils.book_append_sheet(wb, ws, uniqueSheet(r.name));
    });

    XLSX.writeFile(wb, "smeta-" + String(project || "aivibe").replace(/\s+/g, "-").toLowerCase() + ".xlsx");
    return true;
  }

  window.AIVibeXLSX = { exportRoomSpec };
})();
