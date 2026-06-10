#!/usr/bin/env bash
#
# backend/deploy.sh — деплой всех 4 Cloud Functions AIVibe в Yandex Cloud.
#
# Требуемые переменные окружения:
#   YC_FOLDER_ID  — ID каталога Yandex Cloud (yc config get folder-id)
#   SA_ID         — ID сервисного аккаунта (роль для функций)
#   LOCKBOX_ID    — ID секрета Lockbox с ключами приложения
#
# Запуск:
#   chmod +x backend/deploy.sh   # один раз
#   bash backend/deploy.sh
#
set -euo pipefail

# ─── Проверка окружения ──────────────────────────────────────────
missing=()
[ -z "${YC_FOLDER_ID:-}" ] && missing+=("YC_FOLDER_ID")
[ -z "${SA_ID:-}" ]        && missing+=("SA_ID")
[ -z "${LOCKBOX_ID:-}" ]   && missing+=("LOCKBOX_ID")

if [ ${#missing[@]} -gt 0 ]; then
  echo "✗ Не заданы переменные окружения: ${missing[*]}" >&2
  echo "  Задай их перед запуском, например:" >&2
  echo "    export YC_FOLDER_ID=\$(yc config get folder-id)" >&2
  echo "    export SA_ID=\$(yc iam service-account get aivibe-sa --format json | python3 -c \"import sys,json;print(json.load(sys.stdin)['id'])\")" >&2
  echo "    export LOCKBOX_ID=\$(yc lockbox secret get aivibe-secrets --format json | python3 -c \"import sys,json;print(json.load(sys.stdin)['id'])\")" >&2
  exit 1
fi

command -v yc >/dev/null 2>&1 || { echo "✗ yc CLI не найден. Установи Yandex Cloud CLI." >&2; exit 1; }
command -v zip >/dev/null 2>&1 || { echo "✗ zip не найден." >&2; exit 1; }

# ─── Пути ────────────────────────────────────────────────────────
BACKEND="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$BACKEND/tmp"

cleanup() { rm -rf "$BUILD_DIR"; }
trap cleanup EXIT

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ─── Секреты из Lockbox (инжектятся как переменные окружения) ─────
SECRET_KEYS=(
  YANDEXGPT_FOLDER_ID
  GIGACHAT_CLIENT_ID
  GIGACHAT_CLIENT_SECRET
  APP_TOKEN
  APIFY_API_TOKEN
  YDB_DOCUMENT_API_ENDPOINT
  YDB_DATABASE
  NODE_TLS_REJECT_UNAUTHORIZED
  YOOKASSA_SHOP_ID
  YOOKASSA_SECRET_KEY
)
# version-id не указываем — yc сам берёт актуальную версию секрета
# (литерал "latest" не поддерживается: «Secret ... or its version latest not found»).
SECRET_FLAGS=()
for key in "${SECRET_KEYS[@]}"; do
  SECRET_FLAGS+=(--secret "id=$LOCKBOX_ID,key=$key,environment-variable=$key")
done

# ─── Хелпер деплоя ───────────────────────────────────────────────
# deploy <function-name> <entrypoint> <memory> <timeout> <staging-dir>
# Доп. флаги для конкретной функции — через массив EXTRA_FLAGS (сбрасывать после).
EXTRA_FLAGS=()
deploy() {
  local name="$1" entrypoint="$2" memory="$3" timeout="$4" srcdir="$5"
  echo "→ Пакую и деплою $name ..."

  # В свежем облаке функции ещё нет — version create падает. Создаём идемпотентно.
  if ! yc serverless function get "$name" --folder-id "$YC_FOLDER_ID" >/dev/null 2>&1; then
    echo "  функция $name не найдена — создаю"
    yc serverless function create --name "$name" --folder-id "$YC_FOLDER_ID" >/dev/null
  fi
  # Публичный вызов по HTTP — идемпотентно при каждом деплое, а не только при
  # создании (иначе сбой между create и allow оставит функцию приватной навсегда).
  # Авторизация — APP_TOKEN внутри самой функции (health и вебхук ЮKassa
  # токена не требуют by design). Требует роли serverless.functions.admin у SA.
  yc serverless function allow-unauthenticated-invoke "$name" --folder-id "$YC_FOLDER_ID" >/dev/null

  ( cd "$srcdir" && zip -qr "$BUILD_DIR/$name.zip" . )

  yc serverless function version create \
    --folder-id "$YC_FOLDER_ID" \
    --function-name "$name" \
    --runtime nodejs22 \
    --entrypoint "$entrypoint" \
    --memory "$memory" \
    --execution-timeout "$timeout" \
    --source-path "$BUILD_DIR/$name.zip" \
    --service-account-id "$SA_ID" \
    "${SECRET_FLAGS[@]}" \
    ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"}

  echo "✓ $name задеплоен"
}

# ─── 1. aivibe-ai-advisor ────────────────────────────────────────
# Полная точка входа: prompt guard + блокировки + triplex fallback.
S="$BUILD_DIR/ai-advisor"
mkdir -p "$S"
cp "$BACKEND/index.js"        "$S/index.js"
cp "$BACKEND/blockedUsers.js" "$S/blockedUsers.js"
cp "$BACKEND/cache.js"        "$S/cache.js"
cp "$BACKEND/promptGuard.js"  "$S/promptGuard.js"
cp "$BACKEND/package.json"    "$S/package.json"
cp -R "$BACKEND/shared"       "$S/shared"
deploy "aivibe-ai-advisor" "index.handler" "256m" "30s" "$S"

# Функции из functions/<name>/ импортируют '../../shared/...', но в zip-пакете
# index.js лежит в корне, а shared/ — рядом. Поэтому при сборке переписываем
# путь на './shared/'. (ai-advisor этого не требует: он собирается из
# backend/index.js, где импорт уже './shared/'.)
stage_subfunction() {
  local src="$1" dst="$2"
  sed 's#\.\./\.\./shared/#./shared/#g' "$src" > "$dst"
}

# ─── 2. aivibe-marketplace ───────────────────────────────────────
# Фичефлаг B2: CATALOG_SOURCE=partner → партнёрский каталог YDB,
# иначе Apify (дефолт). Переключение: CATALOG_SOURCE=partner bash backend/deploy.sh
S="$BUILD_DIR/marketplace"
mkdir -p "$S"
stage_subfunction "$BACKEND/functions/marketplace/index.js" "$S/index.js"
cp "$BACKEND/functions/marketplace/package.json"   "$S/package.json"
cp -R "$BACKEND/shared"                             "$S/shared"
EXTRA_FLAGS=(--environment "CATALOG_SOURCE=${CATALOG_SOURCE:-apify}")
deploy "aivibe-marketplace" "index.handler" "512m" "60s" "$S"
EXTRA_FLAGS=()

# ─── 3. aivibe-rag-indexer ───────────────────────────────────────
S="$BUILD_DIR/rag-indexer"
mkdir -p "$S"
stage_subfunction "$BACKEND/functions/rag-indexer/index.js" "$S/index.js"
cp "$BACKEND/functions/rag-indexer/package.json"   "$S/package.json"
cp -R "$BACKEND/shared"                             "$S/shared"
deploy "aivibe-rag-indexer" "index.handler" "512m" "300s" "$S"

# ─── 4. aivibe-image-gen ─────────────────────────────────────────
S="$BUILD_DIR/image-gen"
mkdir -p "$S"
stage_subfunction "$BACKEND/functions/image-gen/index.js" "$S/index.js"
cp "$BACKEND/functions/image-gen/package.json"     "$S/package.json"
cp -R "$BACKEND/shared"                             "$S/shared"
deploy "aivibe-image-gen" "index.handler" "256m" "60s" "$S"

# ─── 5. aivibe-payments ──────────────────────────────────────────
# Подписка PRO/BUSINESS через ЮKassa (Фаза 1, A3.1 — docs/UPGRADE_PLAN.md).
S="$BUILD_DIR/payments"
mkdir -p "$S"
stage_subfunction "$BACKEND/functions/payments/index.js" "$S/index.js"
cp "$BACKEND/functions/payments/package.json"      "$S/package.json"
cp -R "$BACKEND/shared"                             "$S/shared"
deploy "aivibe-payments" "index.handler" "256m" "30s" "$S"

# ─── Итог ────────────────────────────────────────────────────────
echo ""
echo "✅ Все 5 функций задеплоены. URL функций:"
for name in aivibe-ai-advisor aivibe-marketplace aivibe-rag-indexer aivibe-image-gen aivibe-payments; do
  url=$(yc serverless function get "$name" --folder-id "$YC_FOLDER_ID" --format json 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('http_invoke_url','(нет)'))" 2>/dev/null || echo "(нет)")
  printf "  %-22s %s\n" "$name" "$url"
done

echo ""
echo "➡️  Дальше: заполни backend/api-gateway.yaml реальными ID функций и SA,"
echo "    затем создай шлюз:  yc serverless api-gateway create --name aivibe-gateway --spec backend/api-gateway.yaml"
