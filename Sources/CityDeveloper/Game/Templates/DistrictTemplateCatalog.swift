import Foundation

// MARK: - DistrictTemplateCatalog
//
// Singleton-loader шаблонов кварталов (F-25, TASK-047).
//
// MVP: список families захардкожен = ["egyptian"].
// TASK-051 / Roman / Greek follow-up задачи добавят новые имена явно.
// Динамический скан папок не используется — Bundle.module не гарантирует
// перечисление директорий в SwiftPM bundle (нет isDirectory API для resource URLs).

enum DistrictTemplateCatalog {

    private static var cache: [DistrictTemplate]?
    private static let ioQueue = DispatchQueue(label: "city.district.catalog.io")

    // MARK: - Public API

    static func all() -> [DistrictTemplate] {
        ioQueue.sync {
            if let cache { return cache }
            let loaded = loadFromBundle()
            cache = loaded
            return loaded
        }
    }

    static func byFamily(_ family: String) -> [DistrictTemplate] {
        all().filter { $0.family == family }
    }

    static func byStage(_ stage: Int, family: String) -> [DistrictTemplate] {
        byFamily(family).filter { $0.stage == stage }
    }

    static func availableFamilies() -> Set<String> {
        Set(all().map(\.family))
    }

    // MARK: - Validation (internal — нужен тестам через @testable import)

    /// Проверяет шаблон на валидность:
    /// - все слоты внутри [0..width) × [0..height)
    /// - нет перекрывающихся footprint
    /// Возвращает строку с описанием первой ошибки, или nil если всё ок.
    static func validate(_ t: DistrictTemplate) -> String? {
        var occupied: Set<GridPoint> = []
        for slot in t.slots {
            let cells = footprintCells(slot: slot)
            for cell in cells {
                if cell.x < 0 || cell.x >= t.width || cell.y < 0 || cell.y >= t.height {
                    return "slot at (\(slot.x),\(slot.y)) footprint \(slot.footprint.width)×\(slot.footprint.height) is out of bounds (template \(t.width)×\(t.height))"
                }
                if occupied.contains(cell) {
                    return "slot at (\(slot.x),\(slot.y)) overlaps existing slot at (\(cell.x),\(cell.y))"
                }
                occupied.insert(cell)
            }
        }
        return nil
    }

    // MARK: - Private

    private static func loadFromBundle() -> [DistrictTemplate] {
        // hardcoded MVP, TASK-051 follow-up для динамического списка families
        let families: Set<String> = ["egyptian"]
        var result: [DistrictTemplate] = []
        var seenNames = Set<String>()

        // SwiftPM `.process("Resources")` flattens the directory structure into bundle root.
        // We load all JSON from root and filter by the `family` field decoded from each file.
        // This handles both flattened (SwiftPM process) and subdirectory-preserving bundles.
        let allURLs = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []

        for url in allURLs {
            guard let data = try? Data(contentsOf: url) else {
                ErrorsLog.write("[template-loader] failed to read \(url.lastPathComponent)")
                continue
            }
            do {
                let template = try JSONDecoder().decode(DistrictTemplate.self, from: data)
                // Filter: only process families we manage
                guard families.contains(template.family) else { continue }
                if let err = validate(template) {
                    ErrorsLog.write("[template-loader] skipped \(url.lastPathComponent): \(err)")
                    continue
                }
                if seenNames.contains(template.name) {
                    ErrorsLog.write("[template-loader] duplicate name '\(template.name)' (file \(url.lastPathComponent)) — using first wins")
                    continue
                }
                seenNames.insert(template.name)
                result.append(template)
            } catch {
                // Non-template JSON (or unknown role) — skip silently unless it looks like a template
                ErrorsLog.write("[template-loader] decode failed for \(url.lastPathComponent): \(error)")
            }
        }
        return result
    }

    private static func footprintCells(slot: TemplateSlot) -> [GridPoint] {
        var cells: [GridPoint] = []
        for dx in 0..<slot.footprint.width {
            for dy in 0..<slot.footprint.height {
                cells.append(GridPoint(x: slot.x + dx, y: slot.y + dy))
            }
        }
        return cells
    }

    // MARK: - Test helpers

    #if DEBUG
    static func resetCache() {
        ioQueue.sync { cache = nil }
    }
    #endif
}
