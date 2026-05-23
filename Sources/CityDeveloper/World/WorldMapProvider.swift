import Foundation

/// Фасад/координатор бутстрапа карты мира.
/// Создаётся в AppDelegate.applicationDidFinishLaunching до GameScene,
/// чтобы при didMove(to:) карта уже была доступна.
///
/// Порядок инициализации:
/// 1. Прочитать seed из WorldSeedStore; если нет — сгенерировать и сохранить.
/// 2. Прочитать карту из WorldMapStore; если нет/несовпадение → перегенерировать и сохранить.
/// 3. Готовая NoiseMap оседает в provider.map.
final class WorldMapProvider {

    /// Текущая карта мира. Гарантированно не nil после инициализации.
    private(set) var map: NoiseMap

    /// Текущий seed мира.
    private(set) var seed: Int64

    private let mapStore: WorldMapStore

    init(
        seedStore: WorldSeedStore.Type = WorldSeedStore.self,
        mapStore: WorldMapStore = WorldMapStore()
    ) {
        self.mapStore = mapStore

        // Шаг 1: получить или сгенерировать seed
        let resolvedSeed: Int64
        if let saved = seedStore.loadSeed() {
            resolvedSeed = saved
        } else {
            resolvedSeed = Int64.random(in: .min ... .max)
            seedStore.saveSeed(resolvedSeed)
        }
        self.seed = resolvedSeed

        // Шаг 2: загрузить карту или перегенерировать
        let resolvedMap: NoiseMap
        let existingMap = mapStore.load()
        if let loaded = existingMap,
           loaded.seed == resolvedSeed,
           loaded.version == NoiseMap.currentVersion,
           loaded.size == NoiseMap.defaultSize {
            resolvedMap = loaded
        } else {
            if existingMap != nil {
                // Карта была, но не подходит (seed/version/size) — логируем
                ErrorsLog.write("WorldMapProvider: worldmap mismatch (seed or version/size), regenerating")
            }
            let generated = NoiseFieldGenerator.generate(seed: resolvedSeed, size: NoiseMap.defaultSize)
            mapStore.save(generated)
            resolvedMap = generated
        }
        self.map = resolvedMap
    }

    /// Перегенерирует карту с новым seed (или с тем же, если newSeed == nil).
    /// Предназначен для TASK-030 («Сбросить карту»).
    @discardableResult
    func regenerate(newSeed: Int64? = nil) -> NoiseMap {
        let nextSeed = newSeed ?? Int64.random(in: .min ... .max)
        WorldSeedStore.saveSeed(nextSeed)
        seed = nextSeed

        let generated = NoiseFieldGenerator.generate(seed: nextSeed, size: NoiseMap.defaultSize)
        mapStore.save(generated)
        map = generated
        return generated
    }
}
