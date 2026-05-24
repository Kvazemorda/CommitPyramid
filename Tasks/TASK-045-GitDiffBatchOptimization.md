# TASK-045: Один git log вместо N git diff'ов — снизить CPU при импорте

## Связь
- **F-19** из Concept.md (Git watcher)
- **BUG-015** из Bugs.md
- **Приоритет:** P0

---

## 📋 Постановка от менеджера

_Автор: opus_
_Дата: 2026-05-24_

### Что хотим

При импорте 7 репо с включённым `weightByDiff` запускается ~1500 subprocess'ов
`git diff --shortstat` — по одному на каждую пару (commit_{i-1}, commit_i).
На SSD это ~50-100ms за вызов = 1-2 минуты CPU + dиск. Хочется: ОДИН `git log
--numstat` за весь скан репо, парсим вывод локально, без subprocess-storm'а.

### Пользовательский сценарий

1. Пользователь делает Reset с датой 2020 для 7 репо.
2. Процесс импорта завершается за ≤30 секунд (вместо 2-3 минут сейчас).
3. CPU нагрузка не зашкаливает (нет fork-storm'а).
4. Результат — те же самые units, что и раньше.

### Acceptance criteria

- [ ] Для каждого репо вызывается ≤2 subprocess'а git (git log + опционально
      git fetch, если включён).
- [ ] Веса юнитов после оптимизации совпадают с весами через старый
      computeWeight (для одного и того же набора коммитов) в пределах ±1 (на
      случай мелких отличий в подсчёте `--numstat` vs `--shortstat`).
- [ ] Время импорта 7 репо ≤30 секунд (контрольный замер: ранее ~3 мин).
- [ ] CPU не пиковит >100% дольше чем на длительность одного `git log`.

### Что НЕ делаем

- Не меняем weightByDiff toggle и multiplier (это TASK-043).
- Не меняем формат source-key или порядок коммитов.
- Не убираем weightByDiff как фичу — только меняем способ подсчёта.

### Edge cases

- [ ] Очень большой коммит (>1M строк): git log --numstat может вернуть много
      данных. OK для разумных репо (наш limit -n 1000).
- [ ] Бинарные файлы в diff: numstat показывает `-` вместо чисел. Парсер
      должен skip'ать non-numeric.
- [ ] Первый коммит в репо (нет prev) — `--numstat` для первого коммита
      покажет diff против пустого дерева. Это OK, вес высокий, потом clamp
      через multiplier даст 1.
- [ ] Replay deterministic — должен сохраниться. Веса детерминированы по
      содержимому коммитов, источники одни и те же.

### Зависимости

- Использует прежний GitCLI.run, GitRepoSpec, без новых зависимостей.

### Дизайн

Не применимо (CLI invocation).

### Done-критерий

_Из Concept.md F-19:_

> GitWatcher эффективно сканирует репозитории и подтягивает коммиты в виде
> событий task_completed. CPU нагрузка остаётся низкой даже при больших
> репо.

---

## 🛠 Технический разбор от тимлида

_Автор: opus_
_Дата: 2026-05-24_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния

- **`GitWatcher.performScan`** (`GitWatcher.swift:135-249`):
  - 1-й subprocess: `git log <branch> --since <date> --pretty=tformat:%H%n%ct%n%s%x00 --no-merges -n 1000` → парсим в `[GitCommit]`.
  - 2-й..N-й subprocess: `computeWeight(prev, current)` для каждого коммита →
    `git diff --shortstat prev..current`. Это N-1 subprocess'ов.
- **`computeWeight`** возвращает count = insertions + deletions, mapping в
  1/2/3/5.

### Архитектурное решение

Объединить в один subprocess:

```
git log <branch> --since <date> --numstat --pretty=tformat:'COMMIT\t%H\t%ct\t%s' --no-merges -n 1000
```

Вывод формат:
```
COMMIT\t<sha1>\t<ct>\t<subject>
<insertions>\t<deletions>\t<filename>
<insertions>\t<deletions>\t<filename>
...
COMMIT\t<sha2>\t<ct>\t<subject>
<insertions>\t<deletions>\t<filename>
...
```

Парсер:
- Идём по строкам. Если строка начинается с `COMMIT\t` → новый коммит, парсим
  sha/ct/subject.
- Иначе — это `numstat` строка для текущего коммита. Парсим insertions и
  deletions (или `-`), аккумулируем.
- На следующий COMMIT (или EOF) — сохраняем коммит в [GitCommit] с
  накопленным totalLines.

Затем `computeWeight` становится pure-функцией от totalLines (без
subprocess):
```swift
func weightFromLines(_ lines: Int) -> Int {
    switch lines {
    case 0...200: return 1
    case 201...2000: return 2
    case 2001...10000: return 3
    default: return 5
    }
}
```

### Пошаговая декомпозиция

1. **Изменить git log команду** `[AC:1]`
   - Файл: `Sources/CityDeveloper/Data/GitWatcher/GitWatcher.swift:139`
   - Заменить:
     ```swift
     let logArgs: [String] = [
         "-C", repoPath.path,
         "log", repo.branch,
         "--since", sinceISO,
         "--numstat",
         "--pretty=tformat:COMMIT\t%H\t%ct\t%s",
         "--no-merges",
         "-n", "1000"
     ]
     ```
   - Уточнение: `--numstat` ставится ПОСЛЕ `--pretty`, чтобы git выдавал
     pretty header + numstat блок для каждого коммита.

2. **Переписать parser в performScan** `[AC:2]`
   - Старый блок (split по `\0`, lines[0]=sha, lines[1]=ct, lines[2]=subject)
     удалить.
   - Новый:
     ```swift
     guard let rawString = String(data: stdoutData, encoding: .utf8) else { return }

     struct GitCommitWithStat {
         let sha: String
         let ts: Date
         let subject: String
         var diffLines: Int
     }
     var commits: [GitCommitWithStat] = []
     var current: GitCommitWithStat?

     for line in rawString.components(separatedBy: "\n") {
         let trimmed = line.trimmingCharacters(in: .whitespaces)
         if trimmed.isEmpty { continue }

         if trimmed.hasPrefix("COMMIT\t") {
             // Закрыть предыдущий
             if let c = current { commits.append(c) }
             // Парсим новый
             let parts = trimmed.components(separatedBy: "\t")
             guard parts.count >= 4,
                   let ct = Double(parts[2]) else { current = nil; continue }
             current = GitCommitWithStat(
                 sha: parts[1],
                 ts: Date(timeIntervalSince1970: ct),
                 subject: String(parts[3...].joined(separator: "\t").prefix(255)),
                 diffLines: 0
             )
         } else {
             // numstat line: "<ins>\t<del>\t<file>" or "-\t-\t<binary>"
             guard current != nil else { continue }
             let parts = trimmed.components(separatedBy: "\t")
             guard parts.count >= 2 else { continue }
             let ins = Int(parts[0]) ?? 0
             let del = Int(parts[1]) ?? 0
             current?.diffLines += ins + del
         }
     }
     if let c = current { commits.append(c) }

     commits.sort { $0.ts < $1.ts }
     ```

3. **Заменить computeWeight pure-функцией** `[AC:2,3]`
   - В performScan loop:
     ```swift
     let baseWeight: Int
     if repo.weightByDiff {
         baseWeight = weightFromLines(commit.diffLines)
     } else {
         baseWeight = 1
     }
     let multiplier = appSettings?.commitWeightMultiplier ?? 0.1
     let weight = max(1, Int(round(Double(baseWeight) * multiplier)))
     ```
   - Старый `computeWeight(repo:prevSha:sha:)` (метод) → переименовать в
     `weightFromLines(_ lines: Int) -> Int`, оставить как private static.
   - Удалить `parseDiffShortstat` (больше не нужен).

4. **Обновить GitCommit struct** `[AC:2]`
   - Старый `GitCommit` (line 6-10) переименовать или заменить на новый, где
     есть поле `diffLines: Int`. Или просто сделать `var commits:
     [GitCommitWithStat]` (как выше). Минимизация изменений: оставить
     GitCommit + добавить отдельную map `[String: Int]` sha → diffLines.

### Edge cases

- [ ] **Нет diff (merge / пустой коммит)** — numstat вернёт 0 строк после
      COMMIT header → diffLines = 0 → weight = 1.
- [ ] **Бинарные файлы (`-\t-\t<file>`)** — Int("-") = nil → 0+0=0, не
      учитывается.
- [ ] **Subject содержит таб** — берём `parts[3...].joined(separator: "\t")`.
- [ ] **commits.count >= 1000** — limit как раньше, лог warning.

### Файлы для изменения

- `Sources/CityDeveloper/Data/GitWatcher/GitWatcher.swift` — performScan
  парсер, weightFromLines, удаление computeWeight и parseDiffShortstat.

### Файлы НЕ трогать

- `Sources/CityDeveloper/Data/GitWatcher/GitCLI.swift` — Process wrapper не
  меняется.

### Команды проверки

- Компиляция: `swift build`
- Smoke:
  1. Reset с датой 2020 на 7 репо.
  2. Засечь время от клика Reset до появления последних юнитов в errors.log
     («ingested N units»). Должно быть ≤30s.
  3. Сравнить кол-во ingested events с предыдущей сессией — должно совпадать
     (или ±5%).

### Сложность
`middle` — парсер переписать, тестирование на реальных репо.

### Объём
S (≤2ч)

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: middle_

### Definition of Done

- [ ] AC выполнены (особенно ≤30s импорт 7 репо)
- [ ] Тесты GitWatcher (если есть) проходят
- [ ] `Bugs.md`: BUG-015 → закрыт

---

## Статус
`[x] ready`

## Метаданные
- Создана: 2026-05-24
