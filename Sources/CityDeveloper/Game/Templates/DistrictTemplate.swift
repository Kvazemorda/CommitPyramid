import Foundation

// MARK: - SlotRole

/// Роли слотов в шаблоне квартала (F-25).
/// 13 значений — добавлять только через отдельную задачу (нарушит инвариант кодировки JSON).
enum SlotRole: String, Codable, CaseIterable, Sendable {
    case residential, well, road, market, temple, workshop, farm,
         bath, school, obelisk, gate, warehouse, monumental
}

// MARK: - TemplateSlot

/// Один слот в шаблоне квартала: позиция, роль, footprint, minEra.
/// footprint по умолчанию 1×1 (если не задан в JSON, декодирование вернёт ошибку —
/// поле обязательно для явного указания).
/// minEra: минимальный era-уровень для активации слота (default 0). TASK-050 F-25.
struct TemplateSlot: Codable, Sendable {
    let x: Int
    let y: Int
    let role: SlotRole
    let footprint: GridSize
    /// TASK-050 F-25: минимальный eraLevel проекта для активации слота (default 0).
    /// Слоты с minEra > 0 отфильтровываются UnitPlanner'ом если eraLevel < minEra.
    let minEra: Int

    /// Memberwise initializer (required because custom init(from:) suppresses auto-synthesis).
    init(x: Int, y: Int, role: SlotRole, footprint: GridSize, minEra: Int = 0) {
        self.x = x
        self.y = y
        self.role = role
        self.footprint = footprint
        self.minEra = minEra
    }

    private enum CodingKeys: String, CodingKey {
        case x, y, role, footprint, minEra
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = try c.decode(Int.self, forKey: .x)
        y = try c.decode(Int.self, forKey: .y)
        role = try c.decode(SlotRole.self, forKey: .role)
        footprint = try c.decode(GridSize.self, forKey: .footprint)
        minEra = try c.decodeIfPresent(Int.self, forKey: .minEra) ?? 0
    }
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
