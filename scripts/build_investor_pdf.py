#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Сборка инвест-меморандума AIVibe в PDF (reportlab, кириллица через Arial TTF)."""

import os
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_LEFT, TA_CENTER, TA_JUSTIFY
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate, PageTemplate, Frame, Paragraph, Spacer, Table, TableStyle,
    HRFlowable, KeepTogether,
)

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "docs", "AIVibe_Investor_Brief_2026-06.pdf")

# ── Шрифты (кириллица) ─────────────────────────────────────────────
SUP = "/System/Library/Fonts/Supplemental"
pdfmetrics.registerFont(TTFont("AR",   f"{SUP}/Arial.ttf"))
pdfmetrics.registerFont(TTFont("AR-B", f"{SUP}/Arial Bold.ttf"))
pdfmetrics.registerFont(TTFont("AR-I", f"{SUP}/Arial Italic.ttf"))
pdfmetrics.registerFontFamily("AR", normal="AR", bold="AR-B", italic="AR-I", boldItalic="AR-B")

# ── Палитра ────────────────────────────────────────────────────────
INK    = colors.HexColor("#14213D")  # тёмно-синий
ACCENT = colors.HexColor("#2A6F97")  # корпоративный синий
MUTED  = colors.HexColor("#5A6472")
LIGHT  = colors.HexColor("#EEF2F6")
LINE   = colors.HexColor("#C9D3DD")
KEEP   = colors.HexColor("#1E7A52")  # зелёный
KILL   = colors.HexColor("#9C3848")  # приглушённый красный
GOLD   = colors.HexColor("#B7892E")

# ── Стили ──────────────────────────────────────────────────────────
def S(name, **kw):
    base = dict(fontName="AR", fontSize=9.6, leading=14, textColor=INK, alignment=TA_JUSTIFY)
    base.update(kw)
    return ParagraphStyle(name, **base)

H1     = S("H1", fontName="AR-B", fontSize=15, leading=18, textColor=INK, alignment=TA_LEFT, spaceBefore=10, spaceAfter=6)
H2     = S("H2", fontName="AR-B", fontSize=11.5, leading=15, textColor=ACCENT, alignment=TA_LEFT, spaceBefore=8, spaceAfter=3)
BODY   = S("BODY", spaceAfter=5)
BODYL  = S("BODYL", alignment=TA_LEFT, spaceAfter=5)
SMALL  = S("SMALL", fontSize=8.2, leading=11, textColor=MUTED, alignment=TA_LEFT)
CELL   = S("CELL", fontSize=8.6, leading=11.5, alignment=TA_LEFT)
CELLB  = S("CELLB", fontName="AR-B", fontSize=8.6, leading=11.5, alignment=TA_LEFT)
CELLW  = S("CELLW", fontName="AR-B", fontSize=8.6, leading=11.5, alignment=TA_LEFT, textColor=colors.white)
CELLC  = S("CELLC", fontSize=8.6, leading=11.5, alignment=TA_CENTER)
THESIS = S("THESIS", fontName="AR-B", fontSize=10.6, leading=15.5, textColor=INK, alignment=TA_LEFT)

def bullet(text, style=BODYL):
    return Paragraph(f'<font color="#2A6F97"><b>—</b></font>&nbsp;&nbsp;{text}', style)

# ── Контент-конструкторы ──────────────────────────────────────────
story = []

def box(flowables, fill=LIGHT, border=LINE, pad=9):
    t = Table([[flowables]], colWidths=[170*mm])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0,0), (-1,-1), fill),
        ("BOX", (0,0), (-1,-1), 0.8, border),
        ("LEFTPADDING", (0,0), (-1,-1), pad), ("RIGHTPADDING", (0,0), (-1,-1), pad),
        ("TOPPADDING", (0,0), (-1,-1), pad), ("BOTTOMPADDING", (0,0), (-1,-1), pad),
    ]))
    return t

def accentbar():
    return HRFlowable(width="100%", thickness=2, color=ACCENT, spaceBefore=2, spaceAfter=8)

# ════════════════════════════════════════════════════════════════════
# 1. РЕЗЮМЕ
# ════════════════════════════════════════════════════════════════════
story.append(Paragraph("Резюме для инвестора", H1))
story.append(accentbar())
story.append(Paragraph(
    "AIVibe — RU-резидентный AI-продукт для дизайна интерьера с редким активом: "
    "<b>детерминированным движком расстановки мебели по эргономике</b>. Мы провели холодный разбор "
    "рынка — закрывшихся и выживших игроков 2017–2026 — и определили единственную конфигурацию выхода "
    "на рынок, юнит-экономика которой сходится. Этот документ — её обоснование, включая то, от чего мы "
    "сознательно отказались.", BODY))
story.append(Spacer(1, 4))
story.append(box([
    Paragraph("Тезис", S("t", fontName="AR-B", fontSize=9, textColor=ACCENT, alignment=TA_LEFT, spaceAfter=3)),
    Paragraph(
        "Рынок убивает не технология, а <b>событийный спрос</b>: мебель покупают раз в 5–10 лет, поэтому "
        "монетизация массового покупателя убыточна by design. Мы зарабатываем на <b>профессионале с "
        "повторяющимся спросом</b> — риелторе и застройщике (виртуальный стейджинг недвижимости) и "
        "дизайнере, — переиспользуя ~70% уже написанного и задеплоенного в прод кода.", THESIS),
]))

# ════════════════════════════════════════════════════════════════════
# 2. РЫНОК И ЕГО СМЕРТНОСТЬ
# ════════════════════════════════════════════════════════════════════
story.append(Paragraph("Рынок: большой спрос — и высокая смертность", H1))
story.append(accentbar())
story.append(Paragraph(
    "Мебель в РФ — рынок ~700 млрд руб. (2024, +20% г/г); смежный AI-interior растёт $1,47 → 6,96 млрд "
    "(2024 → 2032). Попутный ветер реален. Но конкретная ниша «AR/AI-дизайн интерьера» — кладбище: "
    "на ней по одной и той же причине легли проекты с любым размером финансирования.", BODY))

dead = [
    [Paragraph("Компания", CELLW), Paragraph("Итог", CELLW)],
    [Paragraph("<b>Modsy</b> (США)", CELL), Paragraph("Сожгла $72,7M, закрылась в 2022", CELL)],
    [Paragraph("<b>Hutch</b> (США)", CELL), Paragraph("Не вытянул комиссию → пивот в мобильные игры", CELL)],
    [Paragraph("<b>Havenly</b> (США)", CELL), Paragraph("Выжила, только став ритейл-холдингом (5 брендов)", CELL)],
    [Paragraph("<b>Faradise</b> (РФ)", CELL), Paragraph("AR-маркетплейс мебели умер ~2019; выжил как B2B AR/VR-студия", CELL)],
    [Paragraph("Laurel&amp;Wolf, Homepolish, Décor Aid", CELL), Paragraph("Закрылись 2019–2021 на той же модели", CELL)],
]
t = Table(dead, colWidths=[58*mm, 112*mm])
t.setStyle(TableStyle([
    ("BACKGROUND", (0,0), (-1,0), INK),
    ("ROWBACKGROUNDS", (0,1), (-1,-1), [colors.white, LIGHT]),
    ("GRID", (0,0), (-1,-1), 0.5, LINE),
    ("VALIGN", (0,0), (-1,-1), "MIDDLE"),
    ("LEFTPADDING", (0,0), (-1,-1), 7), ("RIGHTPADDING", (0,0), (-1,-1), 7),
    ("TOPPADDING", (0,0), (-1,-1), 4.5), ("BOTTOMPADDING", (0,0), (-1,-1), 4.5),
]))
story.append(t)
story.append(Spacer(1, 7))

story.append(Paragraph("Пять структурных причин смерти ниши", H2))
killers = [
    "<b>Разовый спрос меньше стоимости привлечения.</b> Повторных покупок в категории — лишь 14,7%; "
    "привлечение оплачиваешь сразу, отдача размазана на годы → экономика массового пользователя убыточна.",
    "<b>Комиссия с редкой покупки не масштабируется</b> даже на $72M: транзакций мало, атрибуция утекает, "
    "маржа мебели тонкая.",
    "<b>AR — паритетная фича, а не защита.</b> Маркетплейсы (Ozon, Я.Маркет, WB, Hoff) раздают AR бесплатно; "
    "«летающие диваны» отпугивают массового пользователя.",
    "<b>Пустой каталог и оцифровка дороже рынка</b> — двусторонняя платформа умирает с пустой стороной "
    "предложения.",
    "<b>Без аналитики и идентификации пользователя</b> компания управляет вслепую и льёт деньги в "
    "убыточные сегменты.",
]
for k in killers:
    story.append(bullet(k))
story.append(Spacer(1, 3))
story.append(Paragraph(
    "Вывод, который определяет нашу стратегию: <b>выживают только те, кто берёт деньги с профессионала "
    "с повторяющимся спросом</b> — InteriorAI (>99% маржа, команда 1 человек), Spacely (бьёт в "
    "дизайнеров/архитекторов), Styldod/REimagineHome (риелторы).", BODY))

# ════════════════════════════════════════════════════════════════════
# 3. НАШ EDGE
# ════════════════════════════════════════════════════════════════════
story.append(Paragraph("Наш edge: что у нас есть, чего нет у других", H1))
story.append(accentbar())
edges = [
    "<b>Детерминированный движок расстановки</b> (научные алгоритмы Kán&amp;Kaufmann + Make It Home). Он "
    "считает корректную расстановку <b>геометрией, а не нейросетью</b> → его нельзя скопировать «лучшим "
    "промптом», и его себестоимость <b>не зависит от цены AI-токенов</b>. Это единственный «физически "
    "валидный» результат против diffusion-конкурентов с «летающими диванами».",
    "<b>RU-резидентность как платёжный ров.</b> Западные лидеры (InteriorAI, Spacely) в России платно "
    "недоступны — нужна иностранная карта и VPN. Мы принимаем рубли (ЮKassa) и хостимся в Yandex Cloud. "
    "Конкурент юридически и платёжно не может войти в это окно.",
    "<b>Работающий production-backend</b> — 5 облачных функций уже задеплоено и проверено в проде; "
    "диалоговый AI-ассистент на отечественном стеке (YandexGPT → GigaChat → CoreML) с резервированием.",
]
for e in edges:
    story.append(bullet(e))

# ════════════════════════════════════════════════════════════════════
# 4. ПЯТЬ ПУТЕЙ И РЕШЕНИЕ
# ════════════════════════════════════════════════════════════════════
story.append(Paragraph("Пять путей, которые мы оценили", H1))
story.append(accentbar())
story.append(Paragraph(
    "Каждый сценарий проработан по экономике, защищённости и скорости выхода на деньги, затем "
    "проверён на прочность независимой «адвокатской» критикой. Шкала — качественная.", BODY))

hdr = [Paragraph(x, CELLW) for x in ["Путь", "Маржа", "Ров", "Скорость", "Решение"]]
def vcell(text, c):
    return Paragraph(text, ParagraphStyle("v", fontName="AR-B", fontSize=8.4, leading=10.5,
                                          alignment=TA_CENTER, textColor=c))
rows = [
    hdr,
    [Paragraph("<b>S1.</b> Чистый AI-рендер по подписке", CELL),
     Paragraph("высокая", CELLC), Paragraph("низкий", CELLC), Paragraph("высокая", CELLC),
     vcell("Не выбран", KILL)],
    [Paragraph("<b>S2.</b> White-label инструмент для фабрик", CELL),
     Paragraph("высокая", CELLC), Paragraph("средн.", CELLC), Paragraph("низкая", CELLC),
     vcell("Не выбран", KILL)],
    [Paragraph("<b>S3.</b> SaaS-инструмент для дизайнеров", CELL),
     Paragraph("средн.", CELLC), Paragraph("средн.", CELLC), Paragraph("средн.", CELLC),
     vcell("Выбран (второй)", KEEP)],
    [Paragraph("<b>S4.</b> Виртуальный стейджинг недвижимости", CELLB),
     Paragraph("<b>высокая</b>", CELLC), Paragraph("средн.", CELLC), Paragraph("<b>высокая</b>", CELLC),
     vcell("Выбран (основной)", KEEP)],
    [Paragraph("<b>S5.</b> Open-core / API-платформа", CELL),
     Paragraph("высокая", CELLC), Paragraph("высокий", CELLC), Paragraph("низкая", CELLC),
     vcell("Не выбран", KILL)],
]
t = Table(rows, colWidths=[68*mm, 22*mm, 20*mm, 24*mm, 36*mm])
t.setStyle(TableStyle([
    ("BACKGROUND", (0,0), (-1,0), INK),
    ("ROWBACKGROUNDS", (0,1), (-1,-1), [colors.white, LIGHT]),
    ("BACKGROUND", (0,4), (-1,4), colors.HexColor("#E4EFEA")),  # подсветка S4
    ("GRID", (0,0), (-1,-1), 0.5, LINE),
    ("VALIGN", (0,0), (-1,-1), "MIDDLE"),
    ("LEFTPADDING", (0,0), (-1,-1), 6), ("RIGHTPADDING", (0,0), (-1,-1), 6),
    ("TOPPADDING", (0,0), (-1,-1), 5), ("BOTTOMPADDING", (0,0), (-1,-1), 5),
]))
story.append(t)
story.append(Paragraph(
    "S1 не выбран — единственное преимущество (платёж в рублях) принадлежит будущему конкуренту "
    "(Яндекс/Сбер). S2 — у инструмента нет платящего спроса со стороны фабрик. S5 — рынка такого API "
    "в РФ пока не существует.", SMALL))
story.append(Spacer(1, 8))

story.append(Paragraph("Выбранная стратегия", H1))
story.append(accentbar())
story.append(box([
    Paragraph(
        "Один продукт на одной кодовой базе, два профессиональных сегмента с повторяющимся спросом:",
        S("c", fontName="AR-B", fontSize=9.6, leading=14, alignment=TA_LEFT, spaceAfter=5)),
    bullet("<b>Таран — виртуальный стейджинг (S4).</b> Риелтор/застройщик грузит фото пустой комнаты → "
           "получает обставленные фото для объявления. Платит профессионал с десятками объектов в год. "
           "Лучшая экономика, и AR/сканер уходят с критического пути.", BODYL),
    bullet("<b>Второй сегмент — дизайнеры (S3).</b> Тот же движок и рендер как рабочий инструмент. "
           "Дизайнер платит сам, бесплатно приводит клиентов и гонит заказы фабрикам — так включается "
           "партнёрский слой «чужими руками».", BODYL),
    bullet("<b>Движок расстановки — наш ров</b>, а не то, что мы выбрасываем (S1) или продаём как голый "
           "API (S2/S5).", BODYL),
]))
story.append(Spacer(1, 3))
story.append(Paragraph(
    "Это заостряет более ранний внутренний вывод (дизайнеры-first): у виртуального стейджинга экономика "
    "<b>строго лучше</b> (быстрее до денег, выше маржа) и он чище уходит от событийного спроса — поэтому "
    "именно он становится денежным тараном.", SMALL))

# ════════════════════════════════════════════════════════════════════
# 5. ЮНИТ-ЭКОНОМИКА
# ════════════════════════════════════════════════════════════════════
story.append(Paragraph("Юнит-экономика: почему это сходится", H1))
story.append(accentbar())
ue = [
    [Paragraph(x, CELLW) for x in ["Кто платит", "Частота спроса", "LTV / CAC", "Окупаемость"]],
    [Paragraph("Массовый покупатель", CELL), Paragraph("раз в 5–10 лет", CELLC),
     vcell("0,03–0,38  (убыток)", KILL), Paragraph("никогда", CELLC)],
    [Paragraph("<b>Дизайнер</b>", CELLB), Paragraph("40–140 проектов/год", CELLC),
     vcell("3–8", KEEP), Paragraph("3–6 мес", CELLC)],
    [Paragraph("<b>Риелтор / застройщик</b>", CELLB), Paragraph("десятки объектов/год", CELLC),
     vcell("3–8", KEEP), Paragraph("1–3 мес", CELLC)],
]
t = Table(ue, colWidths=[52*mm, 44*mm, 40*mm, 34*mm])
t.setStyle(TableStyle([
    ("BACKGROUND", (0,0), (-1,0), INK),
    ("ROWBACKGROUNDS", (0,1), (-1,-1), [colors.white, LIGHT]),
    ("GRID", (0,0), (-1,-1), 0.5, LINE),
    ("VALIGN", (0,0), (-1,-1), "MIDDLE"),
    ("LEFTPADDING", (0,0), (-1,-1), 7), ("RIGHTPADDING", (0,0), (-1,-1), 7),
    ("TOPPADDING", (0,0), (-1,-1), 5), ("BOTTOMPADDING", (0,0), (-1,-1), 5),
]))
story.append(t)
story.append(Spacer(1, 4))
story.append(Paragraph(
    "Маржа виртуального стейджинга — порядка 95% и <b>устойчива к росту цен на AI</b>: расстановку "
    "считает движок (вычисление, не запрос к ИИ), а генерация изображений на отечественном стеке "
    "копеечна. Несущая выручка — подписка профессионала и пакеты для застройщиков, а не комиссия с "
    "редкой покупки.", BODY))

# ════════════════════════════════════════════════════════════════════
# 5b. ЗАТРАТЫ ДО ОКУПАЕМОСТИ (реальные цифры)
# ════════════════════════════════════════════════════════════════════
story.append(Paragraph("Затраты до окупаемости (реальные цифры)", H1))
story.append(accentbar())
story.append(Paragraph(
    "Модель построена на <b>официальном прайсе Yandex Cloud</b> (ноя-2025) и медианных зарплатах РФ "
    "(Хабр Карьера, 2025). Технический факт, влияющий на себестоимость: managed-API в РФ (YandexART) не "
    "редактирует фото, поэтому стейджинг работает на <b>self-hosted SDXL + ControlNet на Yandex GPU</b> "
    "(РФ-резидентно, 152-ФЗ) — себестоимость ~7–11 руб./кадр.", BODY))
story.append(Spacer(1, 4))
story.append(box([
    Paragraph(
        "Капитал до окупаемости <b>≈ 9,5–16,5 млн руб.</b> (подушка 18–20 млн). Операционная "
        "безубыточность <b>≈ М15</b>, полный возврат вложенного <b>≈ М23</b>; дно «ямы» ≈ 9,3 млн руб.",
        THESIS),
]))
story.append(Spacer(1, 6))
team = [[Paragraph(x, CELLW) for x in ["Фаза", "Команда", "ФОТ/мес", "Полные затраты/мес"]],
        [Paragraph("MVP · М1–4", CELLB), Paragraph("backend + ML/CV + 0,5 iOS", CELL), Paragraph("~595 тыс руб.", CELL), Paragraph("~626 тыс руб.", CELL)],
        [Paragraph("Пилот · М5–9", CELLB), Paragraph("+ iOS + перформанс-маркетолог", CELL), Paragraph("~865 тыс руб.", CELL), Paragraph("~1,1–1,2 млн руб.", CELL)],
        [Paragraph("Рост · М10–24", CELLB), Paragraph("+ support/sales + дизайн", CELL), Paragraph("~1,07 млн руб.", CELL), Paragraph("1,7–2,5 млн руб.", CELL)]]
t2 = Table(team, colWidths=[26*mm, 72*mm, 30*mm, 42*mm])
t2.setStyle(TableStyle([
    ("BACKGROUND", (0,0), (-1,0), INK),
    ("ROWBACKGROUNDS", (0,1), (-1,-1), [colors.white, LIGHT]),
    ("GRID", (0,0), (-1,-1), 0.5, LINE),
    ("VALIGN", (0,0), (-1,-1), "MIDDLE"),
    ("LEFTPADDING", (0,0), (-1,-1), 6), ("RIGHTPADDING", (0,0), (-1,-1), 6),
    ("TOPPADDING", (0,0), (-1,-1), 4.5), ("BOTTOMPADDING", (0,0), (-1,-1), 4.5),
]))
story.append(t2)
story.append(Spacer(1, 5))
for b in [
    "<b>Себестоимость 1 стейджинга ~10–40 руб.</b> (4 кадра), маржа <b>~90–95%</b>; на прерываемых GPU и батчинге COGS падает в 4–5×.",
    "<b>Главные рычаги:</b> цена и скорость набора риелторов (LTV/CAC 5–20×), режим GPU (прерываемые ВМ), тайминг найма (команда 6 человек, подряд до М12–14).",
]:
    story.append(bullet(b))

# ════════════════════════════════════════════════════════════════════
# 6. ДОРОЖНАЯ КАРТА И КОНТРОЛЬНЫЕ ТОЧКИ
# ════════════════════════════════════════════════════════════════════
story.append(Paragraph("Дорожная карта и контрольные точки (gates)", H1))
story.append(accentbar())
story.append(Paragraph(
    "Стратегия снимается рисками поэтапно — каждый этап имеет проверяемый критерий, при провале которого "
    "мы не масштабируемся, а корректируем курс. Это защита капитала от «слепого» сжигания.", BODY))
gates = [
    "<b>Фаза 0 — фундамент.</b> Авторизация + рабочая аналитика активации. Без них нельзя отличить "
    "прибыльный сегмент от убыточного. Идёт <b>до</b> любого платного маркетинга.",
    "<b>Gate 1 — качество.</b> Пилот на 20 риелторах; критерий: «вставил картинку в реальный листинг» "
    "≥ 60%. Не прошло — дорабатываем продукт, не масштабируем.",
    "<b>Gate 2 — несущий чек.</b> Первый застройщик конвертируется в первом квартале пилота. "
    "Подтверждает B2B-канал, недоступный платформам-листингам.",
    "<b>Далее — рост.</b> Масштабирование стейджинга, подключение дизайнеров (тот же стек), фаза 2 "
    "(фабрики/комиссия — через дизайнеров, со спросом, а не с пустого места). Опционально — Казахстан.",
]
for g in gates:
    story.append(bullet(g))
story.append(Spacer(1, 6))

story.append(Paragraph("Главные риски и их снятие", H2))
risks = [
    ["Авито/Циан встроят AI-меблировку",
     "Институциональные договоры с застройщиками и агентствами — канал, недоступный платформе листинга; скорость; движок-ров."],
    ["Качество AI-генерации недостаточно для листинга",
     "Движок как валидатор геометрии + сохранение реальной комнаты (inpainting); жёсткий quality-gate до маркетинга."],
    ["Узкий рынок одного сегмента",
     "Расширение на соседние B2B (стейджинг → застройщики → дизайнеры → Казахстан) на той же кодовой базе."],
]
rr = [[Paragraph("Риск", CELLW), Paragraph("Как снимаем", CELLW)]]
for a, b in risks:
    rr.append([Paragraph(a, CELLB), Paragraph(b, CELL)])
t = Table(rr, colWidths=[58*mm, 112*mm])
t.setStyle(TableStyle([
    ("BACKGROUND", (0,0), (-1,0), ACCENT),
    ("ROWBACKGROUNDS", (0,1), (-1,-1), [colors.white, LIGHT]),
    ("GRID", (0,0), (-1,-1), 0.5, LINE),
    ("VALIGN", (0,0), (-1,-1), "MIDDLE"),
    ("LEFTPADDING", (0,0), (-1,-1), 7), ("RIGHTPADDING", (0,0), (-1,-1), 7),
    ("TOPPADDING", (0,0), (-1,-1), 4.5), ("BOTTOMPADDING", (0,0), (-1,-1), 4.5),
]))
story.append(t)

# ── Шаблон страницы: шапка + подвал ────────────────────────────────
def header_footer(canvas, doc):
    canvas.saveState()
    w, h = A4
    # Шапка
    canvas.setFillColor(INK)
    canvas.rect(0, h-26*mm, w, 26*mm, fill=1, stroke=0)
    canvas.setFillColor(GOLD)
    canvas.rect(0, h-26*mm, w, 1.4*mm, fill=1, stroke=0)
    canvas.setFillColor(colors.white)
    canvas.setFont("AR-B", 16)
    canvas.drawString(18*mm, h-14*mm, "AIVibe")
    canvas.setFont("AR", 9)
    canvas.setFillColor(colors.HexColor("#AEB9C7"))
    canvas.drawString(18*mm, h-20*mm, "Стратегический меморандум для инвесторов")
    canvas.setFont("AR", 8)
    canvas.drawRightString(w-18*mm, h-13*mm, "AI-дизайн интерьера · рынок РФ")
    canvas.drawRightString(w-18*mm, h-18*mm, "Июнь 2026")
    canvas.drawRightString(w-18*mm, h-22.5*mm, "КОНФИДЕНЦИАЛЬНО")
    # Подвал
    canvas.setStrokeColor(LINE)
    canvas.setLineWidth(0.6)
    canvas.line(18*mm, 14*mm, w-18*mm, 14*mm)
    canvas.setFont("AR", 7.4)
    canvas.setFillColor(MUTED)
    canvas.drawString(18*mm, 9.5*mm,
        "Конфиденциально. Цифры — консервативные оценки, не обещания результата.")
    canvas.drawRightString(w-18*mm, 9.5*mm, f"AIVibe · стр. {doc.page}")
    canvas.restoreState()

frame = Frame(18*mm, 16*mm, A4[0]-36*mm, A4[1]-26*mm-18*mm, id="main",
              leftPadding=0, rightPadding=0, topPadding=4, bottomPadding=0)
doc = BaseDocTemplate(OUT, pagesize=A4, title="AIVibe — Инвест-меморандум",
                      author="AIVibe", subject="Стратегия выхода на рынок")
doc.addPageTemplates([PageTemplate(id="tpl", frames=[frame], onPage=header_footer)])
doc.build(story)
print("OK:", OUT, "·", os.path.getsize(OUT), "bytes")
