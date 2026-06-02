#!/usr/bin/env bash
# Устанавливает git pre-commit hook с проверкой секретов (trufflehog).
# Запуск: bash scripts/install-hooks.sh

set -euo pipefail

HOOK_PATH="$(git rev-parse --show-toplevel)/.git/hooks/pre-commit"

if [ -f "$HOOK_PATH" ] && ! grep -q "trufflehog" "$HOOK_PATH"; then
    echo "⚠️  pre-commit hook уже существует. Бэкап → ${HOOK_PATH}.bak"
    cp "$HOOK_PATH" "${HOOK_PATH}.bak"
fi

cat > "$HOOK_PATH" << 'HOOK'
#!/usr/bin/env bash
# Pre-commit hook: проверка секретов через trufflehog.
# Установлен через scripts/install-hooks.sh

set -eo pipefail

if ! command -v trufflehog &>/dev/null; then
    echo "⚠️  trufflehog не установлен. Установи: brew install trufflehog"
    echo "   Пропускаю проверку секретов."
    exit 0
fi

echo "🔍 Проверка секретов (trufflehog)..."

# Сканируем только staged изменения (быстро, не вся история)
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACMR)

if [ -z "$STAGED_FILES" ]; then
    exit 0
fi

# trufflehog проверяет staged diff
trufflehog git file://. --since-commit HEAD --only-verified --fail 2>/dev/null

if [ $? -ne 0 ]; then
    echo ""
    echo "❌ Обнаружены верифицированные секреты в staged файлах!"
    echo "   Удали секреты из кода и используй Yandex Lockbox / env vars."
    echo "   Для false positive: добавь в .trufflehog-ignore"
    exit 1
fi

echo "✅ Секретов не обнаружено."
HOOK

chmod +x "$HOOK_PATH"
echo "✅ Pre-commit hook установлен: $HOOK_PATH"
echo ""
echo "Зависимости:"
echo "  brew install trufflehog    # macOS"
echo "  # или: pip install trufflehog   (Python fallback)"
