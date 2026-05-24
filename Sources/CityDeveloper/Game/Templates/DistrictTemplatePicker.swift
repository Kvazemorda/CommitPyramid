import Foundation

enum DistrictTemplatePicker {

    /// Выбирает шаблон квартала для проекта.
    /// Детерминирован: одни и те же входы → один и тот же результат.
    static func pick(
        stage: Int,
        family: String,
        biome: BiomeKind?,
        seed: UInt64
    ) -> DistrictTemplate? {
        // 1. Resolve family
        let resolved = resolveFamily(family, biome: biome, seed: seed)
        guard let resolved else { return nil }

        // TASK-051: availability fallback. resolved может быть несуществующей в catalog family
        // (например, пользователь выбрал "roman" в Settings, но MVP содержит только "egyptian").
        let available = DistrictTemplateCatalog.availableFamilies()
        let resolvedFamily: String
        if available.contains(resolved) {
            resolvedFamily = resolved
        } else {
            ErrorsLog.write("[template] family '\(resolved)' not available in catalog, falling back to 'egyptian'")
            resolvedFamily = "egyptian"
        }

        // 2. Кандидаты (era-templates excluded — assigned only via applyEraProgression)
        let allCandidates = DistrictTemplateCatalog.byStage(stage, family: resolvedFamily)
        let candidates = allCandidates.filter { t in
            !t.name.hasSuffix("-monumental") && !t.name.hasSuffix("-legacy")
        }
        guard !candidates.isEmpty else { return nil }

        // 3. Biome filter (fallback если все отфильтрованы)
        let filtered: [DistrictTemplate]
        if let biome {
            let f = candidates.filter {
                $0.biomePreference.isEmpty || $0.biomePreference.contains(biome)
            }
            filtered = f.isEmpty ? candidates : f
        } else {
            filtered = candidates
        }

        // 4. Детерминированный pick
        let sorted = filtered.sorted { $0.name < $1.name }
        var rng = SplitMix64(seed: seed)
        let idx = Int(rng.next() % UInt64(sorted.count))
        return sorted[idx]
    }

    private static func resolveFamily(
        _ family: String,
        biome: BiomeKind?,
        seed: UInt64
    ) -> String? {
        switch family {
        case "auto":
            return resolveAutoFamily(biome: biome)
        case "mixed":
            let available = DistrictTemplateCatalog.availableFamilies().sorted()
            guard !available.isEmpty else { return nil }
            if available.count == 1 { return available[0] }
            var rng = SplitMix64(seed: seed)
            let idx = Int(rng.next() % UInt64(available.count))
            return available[idx]
        default:
            return family
        }
    }

    /// TASK-051 F-25: biome → дефолтная family для "auto" режима.
    private static func resolveAutoFamily(biome: BiomeKind?) -> String {
        guard let biome else { return "egyptian" }
        switch biome {
        case .meadow, .desert: return "egyptian"
        case .mountain, .stone: return "roman"
        case .sea, .river: return "greek"
        case .forest: return "egyptian"
        }
    }
}
