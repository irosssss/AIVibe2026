/* ============================================================
   AIVibe — выгрузка спецификации в PDF (pdfmake, шрифт Roboto/кириллица)
   Экспортирует window.AIVibePDF.exportSpec(...)
   ============================================================ */
(function () {
  const money = (n) => new Intl.NumberFormat("ru-RU").format(Math.round(n)) + " ₽"; // ₽

  function exportSpec({ project, styleName, rows, total, budget, checks }) {
    if (!window.pdfMake) { alert("PDF-библиотека ещё загружается — попробуйте через секунду."); return false; }
    const over = total > budget;

    const tableBody = [
      [
        { text: "Категория", style: "th" },
        { text: "Предмет", style: "th" },
        { text: "Фабрика", style: "th" },
        { text: "Уровень", style: "th" },
        { text: "Цена", style: "th", alignment: "right" },
      ],
      ...rows.map((r) => [
        r.cat,
        r.title,
        r.factory || "—",
        r.tier || "—",
        { text: money(r.price), alignment: "right" },
      ]),
    ];

    const checkLines = (checks && checks.findings ? checks.findings : []).map((f) => ({
      text: (f.kind === "warn" ? "•  " : "•  ") + f.text,
      color: f.kind === "warn" ? "#B45309" : "#2F7A52",
      fontSize: 9, margin: [0, 1.5, 0, 1.5],
    }));
    const checkSummary = checks
      ? (checks.ok ? "Все нормы соблюдены" : checks.warns + " замечани" + (checks.warns === 1 ? "е" : checks.warns < 5 ? "я" : "й"))
      : "—";

    const doc = {
      pageMargins: [40, 46, 40, 44],
      content: [
        {
          columns: [
            { text: "AIVibe", style: "logo" },
            { text: "Спецификация проекта", alignment: "right", style: "muted", margin: [0, 6, 0, 0] },
          ],
        },
        { canvas: [{ type: "line", x1: 0, y1: 0, x2: 515, y2: 0, lineWidth: 1, lineColor: "#E2552B" }], margin: [0, 8, 0, 0] },
        { text: project || "Проект", style: "h1", margin: [0, 14, 0, 2] },
        { text: (styleName ? styleName + " · " : "") + "смета по каталогу фабрик-партнёров", style: "muted", margin: [0, 0, 0, 16] },

        { text: "Проверка эргономики — " + checkSummary, style: "h2" },
        ...(checkLines.length ? checkLines : [{ text: "—", fontSize: 9, color: "#999" }]),

        { text: "Спецификация", style: "h2", margin: [0, 16, 0, 6] },
        {
          table: { headerRows: 1, widths: ["*", "*", 58, 54, "auto"], body: tableBody },
          layout: {
            hLineWidth: (i) => (i === 1 ? 1 : 0.5),
            hLineColor: () => "#E5E0DA",
            vLineWidth: () => 0,
            paddingTop: () => 5, paddingBottom: () => 5,
          },
        },
        {
          columns: [
            { text: over ? "Превышение бюджета на " + money(total - budget) : "В рамках бюджета · остаток " + money(budget - total), color: over ? "#B45309" : "#2F7A52", fontSize: 10, margin: [0, 12, 0, 0] },
            { text: "Итого: " + money(total), alignment: "right", style: "total", margin: [0, 9, 0, 0] },
          ],
        },
        { text: "Цены, наличие и сроки — по каталогу фабрик-партнёров. Документ сформирован в AIVibe.", style: "foot", margin: [0, 20, 0, 0] },
      ],
      styles: {
        logo: { fontSize: 18, bold: true, color: "#E2552B" },
        h1: { fontSize: 20, bold: true, color: "#1A1417" },
        h2: { fontSize: 12, bold: true, color: "#3A3338", margin: [0, 8, 0, 4] },
        th: { bold: true, fontSize: 9, color: "#6B6168" },
        muted: { color: "#8A8088", fontSize: 10 },
        total: { fontSize: 14, bold: true, color: "#1A1417" },
        foot: { fontSize: 8, color: "#B0A8AE" },
      },
      defaultStyle: { fontSize: 10, color: "#241A26" },
    };

    const name = "smeta-" + String(project || "aivibe").replace(/\s+/g, "-").toLowerCase() + ".pdf";
    window.pdfMake.createPdf(doc).download(name);
    return true;
  }

  window.AIVibePDF = { exportSpec };
})();
