import Foundation

// MARK: - TemplateMigrationValidator (TASK-049 F-25)
//
// Pure static helper — проверяет, что все existing units проекта попадают
// на slot'ы nextTemplate с совместимой role. Вынесен в отдельный тип для testability
// (можно передать in-memory фикстурные templates без обращения к Catalog).

enum TemplateMigrationValidator {

    /// Проверяет, что все existing units проекта попадают на slot'ы nextTemplate
    /// с совместимой role. Совместимость: slot.role == unit.kind.preferredSlotRole.
    /// districtOrigin — origin квартала (для расчёта абсолютной позиции slot'ов).
    ///
    /// Если units пустой — возвращает true (нет юнитов → миграция безопасна).
    static func canMigrate(
        units: [UnitState],
        to nextTemplate: DistrictTemplate,
        districtOrigin: GridPoint
    ) -> Bool {
        // Построить map: absolute slot position → slot.role
        var slotRoles: [GridPoint: SlotRole] = [:]
        for slot in nextTemplate.slots {
            let abs = GridPoint(x: districtOrigin.x + slot.x, y: districtOrigin.y + slot.y)
            slotRoles[abs] = slot.role
        }
        // Каждый unit проекта: unit.position должна быть slot'ом
        // с slot.role == unit.kind.preferredSlotRole.
        for unit in units {
            guard let role = slotRoles[unit.position] else { return false }
            if role != unit.kind.preferredSlotRole { return false }
        }
        return true
    }
}
