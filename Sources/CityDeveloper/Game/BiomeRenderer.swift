import SpriteKit

// MARK: - BiomeRenderer (TASK-028)
//
// Строит SKTileMapNode (изометрический, tileSize 64×32) из BiomeMapReader.
// Биом-карту получает через протокол BiomeMapReader.
// BiomeMap conformance — в BiomeMapReader.swift.
//
// zPosition тайл-карты = -1000 (ниже watermark -500, ниже юнитов/жителей -(x+y)).
// Overlay-ноды (переходы земля↔вода, луг↔пустыня) = -999.

final class BiomeRenderer {

    // MARK: - Константы

    private static let tileSize = CGSize(width: 64, height: 32)

    /// Поддерживаемые пары биомов (симметричные) для переходных групп тайлсета.
    private static let transitionPairs: [BiomePair] = [
        BiomePair(.meadow, .forest),
        BiomePair(.meadow, .desert),
        BiomePair(.meadow, .stone),
        BiomePair(.stone, .mountain),
        BiomePair(.meadow, .river),
        BiomePair(.meadow, .sea),
        BiomePair(.desert, .sea),
        BiomePair(.stone, .sea),
    ]

    // MARK: - Состояние

    private let tileMap: SKTileMapNode
    private weak var attachedWorld: SKNode?

    /// Плоская биомная сетка row-major: biomeGrid[row * cols + col].
    private var biomeGrid: [BiomeKind] = []

    // Кэш групп тайлсета
    private var pureGroups:       [BiomeKind: SKTileGroup]    = [:]
    private var transitionGroups: [TransitionKey: SKTileGroup] = [:]

    // MARK: - Init

    init(map: BiomeMapReader) {
        let (tileSet, pure, transition) = Self.buildTileSet()
        pureGroups       = pure
        transitionGroups = transition

        tileMap = SKTileMapNode(
            tileSet: tileSet,
            columns: map.width,
            rows: map.height,
            tileSize: Self.tileSize
        )
        tileMap.position = .zero
        tileMap.zPosition = -1000

        doPopulate(from: map)
    }

    // MARK: - Публичный API

    /// Прикрепляет тайл-карту к родительскому узлу.
    func attach(to parent: SKNode) {
        attachedWorld = parent
        parent.addChild(tileMap)
        buildBiomeLabels(on: parent)
    }

    /// Пересобирает рендер из новой карты — для TASK-030 «Сбросить карту».
    func rebuild(from map: BiomeMapReader) {
        // Стереть тайлы
        for col in 0..<tileMap.numberOfColumns {
            for row in 0..<tileMap.numberOfRows {
                tileMap.setTileGroup(nil, forColumn: col, row: row)
            }
        }
        doPopulate(from: map)
        if let parent = attachedWorld {
            buildBiomeLabels(on: parent)
        }
    }

    // MARK: - Построение тайлсета

    private static func buildTileSet() -> (
        SKTileSet,
        [BiomeKind: SKTileGroup],
        [TransitionKey: SKTileGroup]
    ) {
        var allGroups:  [SKTileGroup]                  = []
        var pure:       [BiomeKind: SKTileGroup]       = [:]
        var transition: [TransitionKey: SKTileGroup]   = [:]

        // 7 чистых групп (по одной дефиниции на биом)
        for biome in BiomeKind.allCases {
            let tex   = TileTextureFactory.texture(for: biome)
            let def   = SKTileDefinition(texture: tex, size: tileSize)
            let group = SKTileGroup(tileDefinition: def)
            group.name = "pure_\(biome.rawValue)"
            pure[biome] = group
            allGroups.append(group)
        }

        // Переходные группы: поддерживаемые пары × 4 ребра × 2 направления
        for pair in transitionPairs {
            for edge in [Edge.ne, .nw, .se, .sw] {
                // base=a, neighbor=b
                do {
                    let tex  = TileTextureFactory.transitionTexture(from: pair.a, to: pair.b, edge: edge)
                    let def  = SKTileDefinition(texture: tex, size: tileSize)
                    let grp  = SKTileGroup(tileDefinition: def)
                    grp.name = "tr_\(pair.a.rawValue)_\(pair.b.rawValue)_\(edge)"
                    let key  = TransitionKey(base: pair.a, neighbor: pair.b, edge: edge)
                    transition[key] = grp
                    allGroups.append(grp)
                }
                // base=b, neighbor=a (обратная пара)
                do {
                    let tex  = TileTextureFactory.transitionTexture(from: pair.b, to: pair.a, edge: edge)
                    let def  = SKTileDefinition(texture: tex, size: tileSize)
                    let grp  = SKTileGroup(tileDefinition: def)
                    grp.name = "tr_\(pair.b.rawValue)_\(pair.a.rawValue)_\(edge)"
                    let key  = TransitionKey(base: pair.b, neighbor: pair.a, edge: edge)
                    transition[key] = grp
                    allGroups.append(grp)
                }
            }
        }

        let tileSet = SKTileSet(tileGroups: allGroups, tileSetType: .isometric)
        tileSet.defaultTileSize = tileSize
        return (tileSet, pure, transition)
    }

    // MARK: - Заполнение тайлов (edge-aware)

    private func doPopulate(from map: BiomeMapReader) {
        let cols = tileMap.numberOfColumns
        let rows = tileMap.numberOfRows

        // Построить biomeGrid для последующего overlay
        biomeGrid = [BiomeKind](repeating: .meadow, count: rows * cols)

        for row in 0..<rows {
            for col in 0..<cols {
                let center = map.biome(atX: col, y: row)
                biomeGrid[row * cols + col] = center

                // Прочитать 4 соседа; за краем — тот же биом (clamp)
                let north = map.biome(atX: col,     y: row - 1)
                let south = map.biome(atX: col,     y: row + 1)
                let east  = map.biome(atX: col + 1, y: row)
                let west  = map.biome(atX: col - 1, y: row)

                let neighbors: [(BiomeKind, Edge)] = [
                    (north, .ne),
                    (south, .sw),
                    (east,  .se),
                    (west,  .nw),
                ]

                let diffNeighbors = neighbors.filter { $0.0 != center }

                if diffNeighbors.isEmpty {
                    // Все соседи совпадают — чистый тайл
                    tileMap.setTileGroup(pureGroups[center], forColumn: col, row: row)
                    continue
                }

                // Выбрать доминирующего «чужого» соседа по приоритету
                let dominant = diffNeighbors.max(by: { $0.0.transitionPriority < $1.0.transitionPriority })!
                let (other, edge) = dominant

                let key = TransitionKey(base: center, neighbor: other, edge: edge)
                if let transGroup = transitionGroups[key] {
                    tileMap.setTileGroup(transGroup, forColumn: col, row: row)
                } else {
                    // Пара не поддерживается — чистый тайл (overlay покроет стык при overlay-паре)
                    tileMap.setTileGroup(pureGroups[center], forColumn: col, row: row)
                }
            }
        }
    }

    // MARK: - Debug-лейблы биомов (каждый тайл, с координатами)

    private func buildBiomeLabels(on parent: SKNode) {
        let cols = tileMap.numberOfColumns
        let rows = tileMap.numberOfRows
        for row in 0..<rows {
            for col in 0..<cols {
                let biome = biomeAt(col: col, row: row)
                let label = SKLabelNode(text: "\(String(biome.asciiSymbol))\n\(col),\(row)")
                label.fontSize = 5
                label.fontName = "Helvetica"
                label.fontColor = .white.withAlphaComponent(0.85)
                label.numberOfLines = 2
                label.position = tileMap.centerOfTile(atColumn: col, row: row)
                label.zPosition = -998
                label.verticalAlignmentMode = .center
                parent.addChild(label)
            }
        }
    }

    // MARK: - Вспомогательные

    private func biomeAt(col: Int, row: Int) -> BiomeKind {
        let cols = tileMap.numberOfColumns
        let rows = tileMap.numberOfRows
        guard col >= 0, col < cols, row >= 0, row < rows else { return .meadow }
        return biomeGrid[row * cols + col]
    }
}

// MARK: - Supporting types

/// Пара биомов (неупорядоченная) — для Set и словаря.
struct BiomePair: Hashable {
    let a: BiomeKind
    let b: BiomeKind

    init(_ x: BiomeKind, _ y: BiomeKind) {
        if x.rawValue <= y.rawValue { a = x; b = y }
        else                        { a = y; b = x }
    }
}

/// Ключ переходной группы тайлсета.
struct TransitionKey: Hashable {
    let base:     BiomeKind
    let neighbor: BiomeKind
    let edge:     Edge
}
