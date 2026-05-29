# Phase 4 AR Designer — чеклист device-тестирования

Ручная проверка RealityKit AR Designer (Phase 4, PR #11) на реальном устройстве.
Канонический источник; GitHub issue [#23](https://github.com/irosssss/AIVibe2026/issues/23) ссылается сюда.

## Стратегия

**AR-first, без LiDAR.** Plane detection через `SpatialTrackingSession` + ручной ввод
размеров комнаты. Работает на любом iPhone 11+ / iPad 2018+ с iOS 26.

> Точность ±10–15 см принята как осознанный trade-off ради широкой совместимости
> (подход как у IKEA Place). LiDAR **не требуется**.

## Перед тестом

- **Hardware:** любой iPhone 11+ или iPad с iOS 26. (Baseline для FPS — iPhone 11.)
- **Build:** `master` (актуальный) в Release-конфигурации на устройстве.
- **Как пользоваться:** скопируйте этот файл к прогону, отмечайте `[x]`, в конце
  заполните Sign-off. Критичные секции для релиза — **1–8** и **Smoke chain**.

Условные обозначения: ✅ прошло · ❌ не прошло (завести bug) · ➖ не применимо.

---

## 1. Boot & permissions

- [ ] App launches without crash on first run after install
- [ ] Camera permission prompt появляется при первом входе в AR-Designer
- [ ] World Sensing permission prompt появляется (iOS 26 — `NSWorldSensingUsageDescription`)
- [ ] Denying World Sensing → coaching overlay показывает `unavailable` с понятным сообщением
- [ ] Denying Camera → fallback / informative empty state, без краша

## 2. SpatialTracking & AnchorEntity resolution (plane detection)

- [ ] Coaching overlay показывает «Наведите камеру на пол» при входе (до резолва anchor)
- [ ] Pointing at well-lit horizontal floor → overlay исчезает за 3–5 секунд
- [ ] `AnchorEntity(.plane(.horizontal, .floor))` резолвится и держится при ходьбе по комнате
- [ ] На glass / mirror / highly reflective floor → coaching остаётся в `searching` (no false-positive anchor)
- [ ] В низком освещении → degraded behavior приемлем (медленнее резолв, без краша)
- [ ] `AnchorStateEvents.DidFailToAnchor` срабатывает при махании телефоном → `unavailable` показан

## 3. Manual room scale flow (без LiDAR)

- [ ] При запуске AR без сохранённого скана → запрос manual W×D×H в метрах
- [ ] Валидация: W ≥ 2 м, D ≥ 2 м, H ≥ 2.2 м, max 50 м² пол
- [ ] Синтетическая `RoomGeometry` строится корректно (stub `.manualEntryTapped`)
- [ ] Можно перейти в AR с введёнными размерами
- [ ] Размеры мебели визуально соответствуют введённым (диван 200 см выглядит ~2 м рядом с пользователем)

## 4. Furniture rendering

- [ ] Все 5 placeholder items из synthesized `RoomDesignPlan` рендерятся на полу
- [ ] `GroundingShadowComponent` → мягкая тень видна под каждым `ModelEntity`
- [ ] Тень остаётся привязана при движении мебели (рекурсивное применение работает)
- [ ] Нет clipping мебели через пол
- [ ] Нет мебели «плавающей в воздухе» после anchor резолва

## 5. Gestures

- [ ] **Tap** на мебель → selection highlight (white overlay) появляется
- [ ] Tap на пустое место → selection clears
- [ ] Tap на другой item → selection switches (без double-overlay)
- [ ] **Drag** мебели → двигается плавно по Y=0 plane
- [ ] Drag — continuous (без snap/jitter)
- [ ] Drag-end коммитит финальную позицию в TCA store (re-tap показывает сохранённую позицию)
- [ ] Drag предмета A при выбранном B → двигается только A
- [ ] Нет случайного drag снаружи furniture entity

## 6. Collision visualization

- [ ] Drag одного item в другой → красный overlay появляется на обоих в течение 100 мс (debounce)
- [ ] Развести их → красный overlay исчезает
- [ ] Out-of-bounds (drag за границу комнаты) → красный overlay + `outOfBounds` CollisionReport entry

## 7. Refine loop (AI feedback)

- [ ] Подвинуть 2–3 items с оригинальных позиций
- [ ] Tap «Уточнить расстановку»
- [ ] `FeedbackBuilder` строит корректный `UserFeedback` (moved → dislikes, остальные → keepItems)
- [ ] `AgentOrchestrator.refine()` возвращает новый план в течение 25 с timeout
- [ ] Новые позиции рендерятся — старая мебель удалена, новая добавлена через SceneDiffer delta
- [ ] `AnchorEntity` **не** потеряна во время refine (оригинальный Phase 4 race bug)
- [ ] Если network падает во время refine → `refineError` показан, sheet остаётся функциональным

## 8. SceneDiffer race (drag-end vs refine-complete)

- [ ] Drag item A
- [ ] Во время drag — tap «Уточнить расстановку»
- [ ] Отпустить drag для A
- [ ] Дождаться завершения refine
- [ ] Expected: самый свежий snapshot побеждает (version-based), без мигания, без удвоенных entity
- [ ] Нет призраков мебели (orphaned `ModelEntity` в scene graph)

## 9. Memory / dispose

- [ ] Открыть AR-Designer → закрыть (back) → переоткрыть 5 раз
- [ ] Каждое закрытие вызывает `sceneBridge.dispose()` — память стабильна в Instruments (no leak)
- [ ] Никаких «duplicate ModelEntity» warnings в Xcode console
- [ ] `applyTask` отменяется при закрытии (no in-flight Task после dismiss)

## 10. Approval & checkout flow

- [ ] Tap checkout → `ARApprovalSheet` презентует с `.large` detent
- [ ] Approval sheet показывает все items + total price
- [ ] Cancel → возврат в AR scene
- [ ] Confirm → триггерит cart action (stub OK для MVP — verify event fires)

## 11. VoiceOver / accessibility

- [ ] VoiceOver включён → каждый furniture item озвучивает title + dimensions
- [ ] Coaching overlay читается через VoiceOver
- [ ] Refine кнопка достижима через VoiceOver

## 12. Edge cases

- [ ] Background app → AR-Designer переоткрывается без anchor reset (или показывает coaching снова — оба приемлемы)
- [ ] Телефонный звонок во время AR → нет краша, восстанавливается
- [ ] Low memory warning → нет краша; furniture entities всё ещё рендерятся
- [ ] USDZ load failure для одного item → остальные рендерятся; failed показывает placeholder
- [ ] Старое устройство (iPhone 11 / iPad 2018) — производительность приемлема, FPS не ниже 30

---

## Smoke chain

End-to-end от cold start, должен пройти в одной сессии:

- [ ] Cold launch → Scan tab → manual room entry W×D×H
- [ ] StylePicker → выбрать Scandinavian → «Создать дизайн»
- [ ] AgentOrchestrator pipeline выполняется (AnalyzerAgent → DesignerAgent → CollisionDetector)
- [ ] Tap «Смотреть в AR»
- [ ] AR-Designer открывается с реальным сгенерированным планом (не mock)
- [ ] Все items рендерятся с тенями, coaching резолвится
- [ ] Подвинуть 2 items, refine, принять новый план
- [ ] Tap checkout → approval sheet показан
- [ ] Cancel → возврат в AR
- [ ] Close → возврат в scan tab → нет краша

---

## Sign-off

Когда критичные секции (1–8 + Smoke chain) проходят хотя бы на одном устройстве:

- [ ] Видеозапись smoke chain прикреплена к issue #23
- [ ] Instruments profiling: no leak после 5× open/close цикла
- [ ] Tested iPhone — модель + iOS version: `_______`
- [ ] Tested iPad (optional): `_______`
- [ ] FPS на baseline iPhone 11: `_______` avg (целевой ≥ 30 FPS)
- [ ] Тестировщик / дата: `_______`
