#!/usr/bin/env bash
# smoke-ruin-priority.sh — детерминированность выбора руины (TASK-017, F-06).
#
# СТАТУС: РУЧНАЯ ПРОВЕРКА (CLI-replay target отсутствует в Package.swift).
# Автоматический запуск через --replay недоступен.
# DoD: нужен ручной прогон согласно инструкции ниже.
#
# ─────────────────────────────────────────────────────────────────────────────
# ЦЕЛЬ ТЕСТА
#
# Проверить два свойства:
#   A) При наличии руины (decay==4) новый проект занимает её, а не свежий луг.
#   B) Детерминированность: два независимых запуска с одним tasks.jsonl дают
#      идентичный финальный state.json (districtOrigin gamma == districtOrigin alpha).
#
# ─────────────────────────────────────────────────────────────────────────────
# СИНТЕТИЧЕСКИЙ tasks.jsonl (генерируется ниже)
#
# Сценарий:
#   - alpha: 1 задача, ts = 100 дней назад → должен уйти в decay-4 (>90 дней).
#   - beta:  5 задач, ts = 100 дней назад → тоже decay-4, но у него больше юнитов.
#   - gamma: 1 задача, ts = сейчас → новый проект.
#
# Ожидаемый выбор (по правилу F-06):
#   - alpha и beta имеют одинаковый lastActivityAt (оба 100 дней назад).
#   - Tiebreaker: beta имеет 5 юнитов против 1 у alpha → beta.unitIds.count > alpha.unitIds.count.
#   - Итого: gamma должна занять districtOrigin beta (не alpha, не свежий луг).
#
# ПРИМЕЧАНИЕ: alpha по правилу будет выбираться первой только если её lastActivityAt
# СТРОГО МЕНЬШЕ beta.lastActivityAt. При одинаковом ts сортировка переходит к
# tiebreaker по unitIds.count desc → beta (5 юнитов) выигрывает у alpha (1 юнит).
#
# ─────────────────────────────────────────────────────────────────────────────
# ИНСТРУКЦИЯ ДЛЯ РУЧНОЙ ПРОВЕРКИ
#
# 1. Создать временный каталог и сгенерировать tasks.jsonl:
#
#    TMPDIR=$(mktemp -d)
#    NOW=$(date -u +%s)
#    TS_OLD=$(( NOW - 100 * 86400 ))  # 100 дней назад
#    TS_OLD_ISO=$(date -u -r $TS_OLD +%Y-%m-%dT%H:%M:%SZ)
#    TS_NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
#
#    # alpha: 1 задача (1 юнит)
#    echo "{\"ts\":\"$TS_OLD_ISO\",\"project\":\"alpha\",\"title\":\"alpha task 1\",\"done\":true}" > "$TMPDIR/tasks.jsonl"
#
#    # beta: 5 задач (5 юнитов) — при одинаковом ts выиграет у alpha по unitIds.count
#    for i in 1 2 3 4 5; do
#      echo "{\"ts\":\"$TS_OLD_ISO\",\"project\":\"beta\",\"title\":\"beta task $i\",\"done\":true}" >> "$TMPDIR/tasks.jsonl"
#    done
#
#    # gamma: новый проект (должен занять руину beta)
#    echo "{\"ts\":\"$TS_NOW_ISO\",\"project\":\"gamma\",\"title\":\"gamma task 1\",\"done\":true}" >> "$TMPDIR/tasks.jsonl"
#
# 2. Запуск 1:
#    - Указать в AppSettings (или через env) путь к $TMPDIR как dataDirectory и tasksJsonlPath.
#    - Запустить приложение: open .build/debug/CommitPyramid (или через Xcode).
#    - Подождать ~5 сек (DecayEngine catch-up + размещение gamma).
#    - Сохранить state.json: cp "$DATA_DIR/state.json" "$TMPDIR/state-run1.json"
#
# 3. Запуск 2:
#    - Удалить state.json: rm "$DATA_DIR/state.json"
#    - Запустить приложение снова с тем же tasks.jsonl.
#    - Подождать ~5 сек.
#    - Сохранить: cp "$DATA_DIR/state.json" "$TMPDIR/state-run2.json"
#
# 4. Проверка детерминированности:
#    diff "$TMPDIR/state-run1.json" "$TMPDIR/state-run2.json"
#    # Ожидаемый результат: пустой diff (или только snapshotTs расходится — допустимо).
#
# 5. Проверка выбора руины:
#    # gamma должна иметь districtOrigin == districtOrigin beta (наибольший unitIds.count при равном ts).
#    jq '.cityState.projects.gamma.districtOrigin, .cityState.projects.beta.districtOrigin' \
#       "$TMPDIR/state-run1.json"
#    # Ожидаемый результат: два идентичных объекта {"x":..,"y":..}.
#
#    # beta должна отсутствовать в финальном state (заменена gamma):
#    jq '.cityState.projects | has("beta")' "$TMPDIR/state-run1.json"
#    # Ожидаемый результат: false
#
# ─────────────────────────────────────────────────────────────────────────────
# КРИТЕРИИ ПРОХОЖДЕНИЯ
#
#   PASS:
#     - diff пуст (или расходится только snapshotTs).
#     - gamma.districtOrigin == beta.districtOrigin (beta выбрана как старшая с большим кол-вом юнитов).
#     - "beta" отсутствует в projects финального state.
#
#   FAIL:
#     - diff непустой (state зависит от запуска → проблема детерминизма).
#     - gamma.districtOrigin != beta.districtOrigin (неверный выбор кандидата).
#     - "beta" присутствует в state (атомарное удаление не сработало).
#
# ─────────────────────────────────────────────────────────────────────────────

echo "smoke-ruin-priority.sh: нет CLI-replay target. Следуйте инструкции ручной проверки в комментариях этого скрипта."
echo "DoD TASK-017: пометить как 'нужен ручной прогон' до появления CLI-target."
exit 0
