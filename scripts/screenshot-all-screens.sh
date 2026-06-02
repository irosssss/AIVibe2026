#!/bin/bash
# screenshot-all-screens.sh
# Снимает все 4 таба × 2 темы (light/dark) = 8 PNG в /tmp/aivibe_shots/
# Требования:
#   - симулятор iPhone 16e iOS 18.6 уже booted
#   - app собран (AIVibeApp.app в DerivedData)
#
# Использование:
#   ./scripts/screenshot-all-screens.sh

set -e

DEV="${AIVIBE_SIM_DEVICE:-4898C540-1C47-4C0C-BA5A-FB55195C16C9}"
BUNDLE="com.aivibe.AIVibeApp"
OUT="/tmp/aivibe_shots"

mkdir -p "$OUT"
rm -f "$OUT"/*.png

echo "→ Boot device $DEV (idempotent)"
xcrun simctl boot "$DEV" 2>/dev/null || true

for theme in light dark; do
    echo "→ Set appearance: $theme"
    xcrun simctl ui "$DEV" appearance "$theme"
    sleep 1

    for tab in home chat scan ar; do
        echo "  • tab=$tab"
        # Kill prev, launch with arg
        xcrun simctl terminate "$DEV" "$BUNDLE" 2>/dev/null || true
        sleep 0.5
        xcrun simctl launch "$DEV" "$BUNDLE" -StartTab "$tab" > /dev/null
        # Ждём пока UI отрисуется (4-5 сек хватает для cold start + animation)
        sleep 4
        xcrun simctl io "$DEV" screenshot "$OUT/${tab}_${theme}.png" 2>&1 \
            | grep -i "Wrote screenshot" || true
    done
done

# Возврат темы в light, очистка
xcrun simctl ui "$DEV" appearance light

echo ""
echo "✓ Готово. Скриншоты в $OUT/"
ls -la "$OUT"
