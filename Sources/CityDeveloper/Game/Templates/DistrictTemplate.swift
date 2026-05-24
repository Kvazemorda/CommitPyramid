import Foundation

// MARK: - SlotRole

/// Роли слотов в шаблоне квартала (F-25).
/// 13 значений — добавлять только через отдельную задачу (нарушит инвариант кодировки JSON).
enum SlotRole: String, Codable, CaseIterable, Sendable {
    case residential, well, road, market, temple, workshop, farm,
         bath, school, obelisk, gate, warehouse, monumental
}

// MARK: - TemplateSlot

/// Один слот в шаблоне квартала: позиция, роль, footprint.
/// footprint по умолчанию 1×1 (если не задан в JSON, декодирование вернёт ошибку —
/// поле обязательно для явного указания).
struct TemplateSlot: Codable, Sendable {
    let x: Int
    let y: Int
    let role: SlotRole
    let footprint: GridSize
}

// MARK: - DistrictTemplate

/// Шаблон квартала: описывает grid слотов с ролями для одной family/stage.
/// Codable через JSON (см. Resources/DistrictTemplates/<family>/*.json).
struct DistrictTemplate: Codable, Sendable {
    let name: String
    let family: String
    let stage: Int
    let width: Int
    let height: Int
    let biomePreference: [BiomeKind]
    let slots: [TemplateSlot]
}
