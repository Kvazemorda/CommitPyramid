#!/usr/bin/env bash
# smoke-stage-tiers.sh — визуальная подмена tier по стадиям квартала (TASK-019, F-08).
#
# СТАТУС: РУЧНАЯ ПРОВЕРКА (CLI-replay target отсутствует в Package.swift).
# Автоматический запуск недоступен — используется только для генерации
# синтетического tasks.jsonl и документирования ожидаемого поведения.
#
# FPS-замер (AC 7): ручной в Instruments Time Profiler — см. шаг 9 декомпозиции.
#
# ─────────────────────────────────────────────────────────────────────────────
# ЦЕЛЬ ТЕСТА
#
# Проверить три свойства:
#   A) stage-up: при 200 задачах в одном проекте stage дорастает до 4–5.
#   B) Детерминированность координат: два прогона дают идентичные unit.position
#      для всех юнитов (bottom-centre anchor неизменен).
#   C) tier <= project.stage: для всех юнитов tier соответствует stage квартала.
#
# ─────────────────────────────────────────────────────────────────────────────
# СИНТЕТИЧЕСКИЙ tasks.jsonl (генерируется ниже)
#
# Сценарий:
#   - tier-test: 200 задач за последние 60 дней — форсирует рост до stage 4–5.
#
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# FPS-ЗАМЕР (шаг 9, AC 7) — РУЧНОЙ, Instruments Time Profiler
#
# Метрика: минимум по фрейму ≥ 50 FPS на переходе stage 2→3, сцена 500+ юнитов.
#
# Процедура:
#   1. Сгенерировать tasks.jsonl с проектом на 600 задач:
#      for i in {1..600}; do
#        echo '{"ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","project":"fps-test","title":"t'$i'"}' >> tasks.jsonl
#      done
#   2. Запустить приложение, дождаться формирования квартала (500+ юнитов).
#   3. Открыть Instruments → Time Profiler, начать запись.
#   4. Триггернуть stage-up: добавить в tasks.jsonl 1 задачу, которая
#      поднимает StageRules.computeStage() с 2 на 3.
#   5. Окно замера: 2 секунды после триггера.
#   6. Ожидаемый результат: минимальный фрейм ≥ 50 FPS (M1 baseline, 1× scale).
#   7. Опционально сохранить trace как Scripts/profiles/stage-transition.trace
#      (добавить в .gitignore).
#
# Обоснование архитектурного выбора (детальность):
#   - swapStageSprite запускает SKAction на каждой ноде независимо.
#   - Все fadeOut/fadeIn идут параллельно в SpriteKit render loop.
#   - Сложность O(N) по числу юнитов при поиске и O(1) per-action.
#   - Ожидаемый профиль: ≤2 мс spike в момент запуска N SKAction на main-queue.
#
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

DATA_DIR="${CITY_DATA_DIR:-${HOME}/Library/Application Support/CommitPyramid}"
TASKS_FILE="${DATA_DIR}/tasks.jsonl"
STATE_FILE="${DATA_DIR}/state.json"
OUT1="${DATA_DIR}/smoke-out1.json"
OUT2="${DATA_DIR}/smoke-out2.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN_TASKS="${SCRIPT_DIR}/smoke-stage-tiers-tasks.jsonl"

# ─── ГЕНЕРАЦИЯ синтетического tasks.jsonl ─────────────────────────────────

echo "Генерация synthetic tasks.jsonl (200 событий, проект tier-test, 60 дней)..."
python3 - <<'PYTHON'
import json
import sys
from datetime import datetime, timedelta, timezone

NOW = datetime.now(timezone.utc)
DAYS = 60
COUNT = 200

lines = []
for i in range(COUNT):
    # Равномерно распределяем по DAYS дням
    days_back = DAYS - (i * DAYS / COUNT)
    ts = NOW - timedelta(days=days_back, hours=i % 24)
    record = {
        "ts": ts.isoformat(),
        "project": "tier-test",
        "title": f"task-{i+1}",
        "taskId": f"tid-{i+1}",
        "source": "smoke"
    }
    lines.append(json.dumps(record, ensure_ascii=False))

print('\n'.join(lines))
PYTHON
) > "${GEN_TASKS}"

echo "Создано $(wc -l < "${GEN_TASKS}") событий в ${GEN_TASKS}"

# ─── РУЧНАЯ ИНСТРУКЦИЯ ────────────────────────────────────────────────────
#
# Шаги для ручного smoke-теста:
#
# 1. Скопировать сгенерированный файл в директорию данных приложения:
#    cp "${GEN_TASKS}" "${TASKS_FILE}"
#
# 2. Запустить приложение (первый прогон), дождаться полной загрузки.
#    Убедиться визуально: квартал tier-test должен иметь здания stage 4–5
#    (высокие/роскошные силуэты, не лачуги).
#
# 3. Сохранить state.json первого прогона:
#    cp "${STATE_FILE}" "${OUT1}"
#
# 4. Очистить state (сбросить snapshot):
#    rm -f "${STATE_FILE}"
#    Перезапустить приложение (второй прогон).
#
# 5. Сохранить state.json второго прогона:
#    cp "${STATE_FILE}" "${OUT2}"
#
# 6. Сравнить позиции юнитов (AC «координаты не меняются»):
#    Ожидаемый результат: IDENTICAL для всех позиций.
#
# 7. Проверить tier <= stage для всех юнитов:
#    Ожидаемый результат: tier совпадает с project.stage.
#
# ─── АВТОПРОВЕРКА (если jq установлен и оба out-файла существуют) ─────────

if command -v jq &>/dev/null && [[ -f "${OUT1}" && -f "${OUT2}" ]]; then
    echo ""
    echo "=== Проверка A: детерминированность позиций ==="
    POS1=$(jq -c '[.units | to_entries[] | {id: .key, pos: .value.position}] | sort_by(.id)' "${OUT1}")
    POS2=$(jq -c '[.units | to_entries[] | {id: .key, pos: .value.position}] | sort_by(.id)' "${OUT2}")
    if [[ "${POS1}" == "${POS2}" ]]; then
        echo "PASS: позиции идентичны между прогонами."
    else
        echo "FAIL: позиции отличаются!"
        diff <(echo "${POS1}") <(echo "${POS2}") | head -20
        exit 1
    fi

    echo ""
    echo "=== Проверка B: tier <= project.stage для всех юнитов ==="
    # Извлечь все units с их projectId и tier, сравнить со stage проекта
    VIOLATIONS=$(jq -r '
        . as $root |
        .units | to_entries[] |
        . as $u |
        ($root.projects[$u.value.projectId]) as $proj |
        if $proj != null and $u.value.tier > $proj.stage then
            "VIOLATION: unit \($u.key) tier=\($u.value.tier) > project.stage=\($proj.stage)"
        else empty end
    ' "${OUT1}")
    if [[ -z "${VIOLATIONS}" ]]; then
        echo "PASS: tier <= stage для всех юнитов."
    else
        echo "FAIL:"
        echo "${VIOLATIONS}"
        exit 1
    fi

    echo ""
    echo "=== Smoke-тест PASS ==="
else
    echo ""
    echo "РУЧНОЙ ПРОГОН: следуй инструкции выше (jq не установлен или out-файлы отсутствуют)."
fi
