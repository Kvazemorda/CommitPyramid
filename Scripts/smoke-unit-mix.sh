#!/usr/bin/env bash
# smoke-unit-mix.sh — проверка пропорций состава юнитов в квартале (TASK-018, F-07).
#
# СТАТУС: РУЧНАЯ ПРОВЕРКА (CLI-replay target отсутствует в Package.swift).
# Автоматический запуск через --replay недоступен.
# DoD: [ ] ручной прогон — пометить чекбокс после прохождения.
#
# ─────────────────────────────────────────────────────────────────────────────
# ЦЕЛЬ ТЕСТА
#
# Проверить следующие свойства:
#   A) Пропорции: квартал 20 юнитов содержит все 4 категории в диапазонах
#      R=45..55%, I=18..22%, P=18..22%, S=9..11% (±10% от 50/20/20/10).
#   B) Well-правило: wellCount >= ceil(residentialCount / 5).
#   C) Stage-ограничения: нет market/temple/obelisk при stage < порога.
#   D) Детерминированность: два независимых запуска дают идентичный состав.
#   E) Short-проект (stage≤1): social-слоты = well (fallback); нет market/temple/obelisk.
#
# ─────────────────────────────────────────────────────────────────────────────
# СИНТЕТИЧЕСКИЙ tasks.jsonl
#
# Проект «mix-long»: 20 событий, даты от 60 дней назад с интервалом 3 дня.
#   Итог по F-08: к 20-й задаче ageDays ≈ 57 дней → stage растёт по мере накопления.
#   Ожидаемый финальный stage ≥ 4 (точное значение зависит от StageRules.computeStage).
#
# Проект «mix-short»: 5 событий, все от 5 дней назад.
#   stage ≈ 0..1 → social fallback = well.
#
# ─────────────────────────────────────────────────────────────────────────────
# ИНСТРУКЦИЯ ДЛЯ РУЧНОЙ ПРОВЕРКИ
#
# 0. Предварительно: убедитесь, что `jq` установлен (`brew install jq`).
#    ПРИМЕЧАНИЕ: формат state.json — всегда читать как .cityState.units и .cityState.projects.
#
# 1. Создать временный каталог и сгенерировать tasks.jsonl:
#
#    TMPDIR_SMOKE=$(mktemp -d)
#    NOW=$(date -u +%s)
#
#    # mix-long: 20 событий от 60 дней назад, интервал 3 дня
#    for i in $(seq 1 20); do
#      OFFSET=$(( (20 - i) * 3 * 86400 ))
#      TS=$(( NOW - OFFSET ))
#      TS_ISO=$(date -u -r $TS +%Y-%m-%dT%H:%M:%SZ)
#      echo "{\"ts\":\"$TS_ISO\",\"project\":\"mix-long\",\"title\":\"task $i\",\"done\":true}"
#    done > "$TMPDIR_SMOKE/tasks.jsonl"
#
#    # mix-short: 5 событий от 5 дней назад
#    TS_SHORT_ISO=$(date -u -r $(( NOW - 5 * 86400 )) +%Y-%m-%dT%H:%M:%SZ)
#    for i in $(seq 1 5); do
#      echo "{\"ts\":\"$TS_SHORT_ISO\",\"project\":\"mix-short\",\"title\":\"short task $i\",\"done\":true}"
#    done >> "$TMPDIR_SMOKE/tasks.jsonl"
#
# 2. Запуск 1:
#    - Указать в AppSettings путь к $TMPDIR_SMOKE как dataDirectory и tasksJsonlPath.
#    - Запустить приложение: open .build/debug/CommitPyramid.app (или через Xcode).
#    - Подождать ~5 сек (CityEngine replay завершится).
#    - Сохранить state.json: cp "$DATA_DIR/state.json" "$TMPDIR_SMOKE/state-run1.json"
#
# 3. Проверка пропорций для mix-long (первые 20 юнитов — единственный цикл):
#
#    jq '
#      .cityState.units
#      | to_entries
#      | map(select(.value.projectId == "mix-long"))
#      | map(.value)
#      | (length) as $total
#      | {
#          total: $total,
#          residential: (map(select(.kind == "shack" or .kind == "house" or .kind == "villa")) | length),
#          infra:       (map(select(.kind == "well" or .kind == "road" or .kind == "warehouse")) | length),
#          production:  (map(select(.kind == "workshop" or .kind == "raw")) | length),
#          social:      (map(select(.kind == "market" or .kind == "forum" or .kind == "temple" or .kind == "obelisk")) | length),
#          wells:       (map(select(.kind == "well")) | length)
#        }
#    ' "$TMPDIR_SMOKE/state-run1.json"
#
#    # Ожидаемый результат (при одном цикле из 20):
#    #   total:       20
#    #   residential: 10  (50%) — диапазон AC: 9..11
#    #   infra:       4   (20%) — диапазон AC: 3..5  (+ возможные fallback well из social-слотов)
#    #   production:  4   (20%) — диапазон AC: 3..5
#    #   social:      2   (10%) — диапазон AC: 1..3  (или 0, если оба слота дали fallback well)
#    #
#    # ПРИМЕЧАНИЕ: если stage < 2 на social-слотах → social=0, infra+=2 (fallback well).
#    # В этом случае AC по social не применяется (квартал не достиг stage ≥ 2 вовремя).
#    # Проверка: убедиться, что infra не превышает 6 (4 базовых + 2 fallback максимум).
#
# 4. Проверка well-правила:
#
#    # wells >= ceil(residential / 5)
#    jq '
#      .cityState.units
#      | to_entries | map(select(.value.projectId == "mix-long")) | map(.value)
#      | {
#          residential: (map(select(.kind == "shack" or .kind == "house" or .kind == "villa")) | length),
#          wells: (map(select(.kind == "well")) | length)
#        }
#      | .wells >= ((.residential / 5) | ceil)
#    ' "$TMPDIR_SMOKE/state-run1.json"
#    # Ожидаемый результат: true
#
# 5. Проверка stage-ограничений для mix-short:
#
#    jq '
#      .cityState.units
#      | to_entries | map(select(.value.projectId == "mix-short")) | map(.value)
#      | map(select(.kind == "market" or .kind == "temple" or .kind == "obelisk"))
#      | length
#    ' "$TMPDIR_SMOKE/state-run1.json"
#    # Ожидаемый результат: 0
#    # Объяснение: mix-short имеет stage≤1 → social-слоты дают fallback well,
#    # market/temple/obelisk не появляются.
#
# 6. Покрытие категорий mix-long (все 4 присутствуют):
#
#    jq '
#      .cityState.units
#      | to_entries | map(select(.value.projectId == "mix-long")) | map(.value)
#      | {
#          has_residential: (map(select(.kind == "shack" or .kind == "house" or .kind == "villa")) | length > 0),
#          has_infra:       (map(select(.kind == "well" or .kind == "road" or .kind == "warehouse")) | length > 0),
#          has_production:  (map(select(.kind == "workshop" or .kind == "raw")) | length > 0),
#          has_social:      (map(select(.kind == "market" or .kind == "forum" or .kind == "temple" or .kind == "obelisk")) | length > 0)
#        }
#    ' "$TMPDIR_SMOKE/state-run1.json"
#    # Ожидаемый результат: все has_* = true
#    # ПРИМЕЧАНИЕ: has_social = false допустимо ТОЛЬКО если финальный stage mix-long < 2
#    # к моменту прохождения social-слотов (7 и 18). В этом случае — escalate к PM.
#
# 7. Детерминированность:
#    - Удалить state.json: rm "$DATA_DIR/state.json"
#    - Повторить Запуск 1 (шаг 2).
#    - Сохранить: cp "$DATA_DIR/state.json" "$TMPDIR_SMOKE/state-run2.json"
#    - Сравнить составы:
#
#    jq '[.cityState.units | to_entries | map(select(.value.projectId == "mix-long")) | map(.value) | sort_by(.taskTs) | .[] | .kind]' \
#       "$TMPDIR_SMOKE/state-run1.json" > "$TMPDIR_SMOKE/mix-long-run1.json"
#
#    jq '[.cityState.units | to_entries | map(select(.value.projectId == "mix-long")) | map(.value) | sort_by(.taskTs) | .[] | .kind]' \
#       "$TMPDIR_SMOKE/state-run2.json" > "$TMPDIR_SMOKE/mix-long-run2.json"
#
#    diff "$TMPDIR_SMOKE/mix-long-run1.json" "$TMPDIR_SMOKE/mix-long-run2.json"
#    # Ожидаемый результат: пустой diff (последовательность kind идентична).
#
# ─────────────────────────────────────────────────────────────────────────────
# EDGE CASES ПОКРЫТЫЕ ТЕСТОМ
#
# 1. stage < 2 (mix-short): social-слоты → well; нет market/temple/obelisk. ✓
# 2. Два проекта параллельно: mix-long и mix-short изолированы (filter по projectId). ✓
# 3. Детерминированность: двойной прогон, сравнение по kind-последовательности. ✓
# 4. Well-правило N=5: wells >= ceil(residential/5). ✓
# 5. Все 4 категории при 20 юнитах. ✓
#
# ─────────────────────────────────────────────────────────────────────────────
# КРИТЕРИИ ПРОХОЖДЕНИЯ (PASS/FAIL)
#
#   PASS:
#     A) mix-long: residential=9..11, infra=3..5, production=3..5, social=1..3 (при stage≥2)
#        ИЛИ social=0 + infra=5..6 (при stage<2 на social-слотах — ожидаемый fallback).
#     B) mix-long: wells >= ceil(residential / 5)  → должно быть true.
#     C) mix-short: count(market|temple|obelisk) == 0.
#     D) mix-long: все 4 категории присутствуют (при stage≥2 к slot 7).
#     E) Детерминированность: diff пуст.
#
#   FAIL:
#     A) Доля любой категории выходит за окно ±10% (при достижении stage ≥ 2 до slot 7).
#     B) wells < ceil(residential / 5).
#     C) Любой market/temple/obelisk в mix-short.
#     D) diff непустой.
#
# ─────────────────────────────────────────────────────────────────────────────

echo "smoke-unit-mix.sh: нет CLI-replay target. Следуйте инструкции ручной проверки в комментариях этого скрипта."
echo "DoD TASK-018: [ ] ручной прогон — пометить чекбокс после прохождения всех критериев выше."
exit 0
