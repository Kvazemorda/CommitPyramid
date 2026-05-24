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
        guard let resolvedFamily = resolved else { return nil }

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
            // MVP: только egyptian в catalog. TASK-051 follow-up: roman/greek.
            return "egyptian"
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
}
