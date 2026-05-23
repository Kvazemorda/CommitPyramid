#!/usr/bin/env bash
#
# Тестовый помощник: добавляет одну строку-задачу в tasks.jsonl.
# Использование:
#   ./Scripts/add-task.sh "Имя проекта" "Текст задачи"
#
# Если игра запущена — увидишь, как через 1-2 секунды появится новый юнит.

set -euo pipefail

DATA="${HOME}/Library/Application Support/CommitPyramid"
FILE="${DATA}/tasks.jsonl"

mkdir -p "${DATA}"
touch "${FILE}"

if [ $# -lt 2 ]; then
  echo "usage: $0 <project> <title>" >&2
  exit 1
fi

PROJECT="$1"
TITLE="$2"
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# JSON-эскейпинг для кавычек и обратных слешей
esc() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"; }
P=$(esc "$PROJECT")
T=$(esc "$TITLE")

LINE="{\"ts\": \"${TS}\", \"project\": ${P}, \"title\": ${T}}"
echo "${LINE}" >> "${FILE}"
echo "added → ${FILE}"
echo "${LINE}"
