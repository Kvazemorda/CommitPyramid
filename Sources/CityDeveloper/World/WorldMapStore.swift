import Foundation

/// Персистенция шумовой карты мира (worldmap.json) — по аналогии с SnapshotStore.
/// Атомарная запись; при повреждении/несовместимой версии — диагностика в ErrorsLog, возврат nil.
final class WorldMapStore {

    var url: URL

    init(url: URL = AppPaths.worldmapJson) {
        self.url = url
    }

    /// Загружает карту из файла. Возвращает nil при:
    /// - отсутствии файла;
    /// - повреждении данных;
    /// - несовпадении версии формата (EC2).
    func load() -> NoiseMap? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        guard let map = try? decoder.decode(NoiseMap.self, from: data) else {
            ErrorsLog.write("WorldMapStore: failed to decode worldmap.json — regenerating")
            return nil
        }
        guard map.version == NoiseMap.currentVersion else {
            ErrorsLog.write("WorldMapStore: worldmap version mismatch (\(map.version) != \(NoiseMap.currentVersion)), regenerating")
            return nil
        }
        return map
    }

    /// Сохраняет карту атомарно. Возвращает false при ошибке записи.
    @discardableResult
    func save(_ map: NoiseMap) -> Bool {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(map) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            ErrorsLog.write("WorldMapStore: save failed: \(error)")
            return false
        }
    }
}
