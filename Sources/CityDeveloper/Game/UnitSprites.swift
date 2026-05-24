import SpriteKit
import AppKit

/// Фабрика визуала юнита: тайл-земля + тень + куб + крыша + декорации.
enum UnitSprites {

    static let tileWidth: CGFloat = 64
    static let tileHeight: CGFloat = 32

    // MARK: - Растровые ассеты зданий

    /// Кеш текстур, чтобы не перечитывать PNG на каждый юнит.
    private static var spriteTextureCache: [String: SKTexture] = [:]

    /// Negative-cache: имена PNG, которых нет в бандле. Исключает повторные Bundle URL lookups
    /// при каждом stage-up (иначе ~250 lookup'ов на 50 юнитов = 3–5 мс на main-thread).
    /// (TASK-036)
    private static var missingTextureNames: Set<String> = []

    /// Пытается загрузить PNG из Resources/Buildings/<name>.png и собрать SKSpriteNode
    /// под изометрический тайл. anchorY смещает основание спрайта в нужное место тайла
    /// (0.30 ≈ низ основания изометрического домика).
    static func loadBuildingSprite(named name: String, targetWidth: CGFloat, anchorY: CGFloat) -> SKSpriteNode? {
        // Negative-cache: если уже знаем что файла нет — не ходим в Bundle.
        guard !missingTextureNames.contains(name) else { return nil }

        let texture: SKTexture
        if let cached = spriteTextureCache[name] {
            texture = cached
        } else {
            guard
                let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Buildings")
                       ?? Bundle.module.url(forResource: name, withExtension: "png"),
                let image = NSImage(contentsOf: url)
            else {
                missingTextureNames.insert(name)
                return nil
            }
            texture = SKTexture(image: image)
            texture.filteringMode = .linear
            spriteTextureCache[name] = texture
        }
        let size = texture.size()
        guard size.width > 0 else { return nil }
        let scale = targetWidth / size.width
        let sprite = SKSpriteNode(texture: texture)
        sprite.size = CGSize(width: size.width * scale, height: size.height * scale)
        sprite.anchorPoint = CGPoint(x: 0.5, y: anchorY)
        return sprite
    }

    // MARK: - userData keys

    static let unitIdKey = "unitId"
    static let projectIdKey = "projectId"

    // MARK: - Категориальный tier-набор (4 категории × 5 stage = 20 спрайтов)

    /// Точка входа для GameScene: создаёт контейнер с ground + building.
    /// building.name = "building" — ключ для swapStageSprite.
    /// anchorPoint контейнера — default (SKNode не имеет anchorPoint); позиция = bottom-centre сетки.
    static func makeStageNode(unit: UnitState, stageOverride: Int? = nil) -> SKNode {
        // Road-юниты рендерятся плоской дорожной клеткой (как магистраль),
        // без 3D-куба. См. BUG-012 / TASK-042.
        if unit.kind == .road {
            let road = makeRoadCellNode()
            road.userData = NSMutableDictionary()
            road.userData?[unitIdKey] = unit.id
            road.userData?[projectIdKey] = unit.projectId
            return road
        }

        let category = unit.kind.category
        let stage = stageOverride ?? max(unit.tier, 1)
        let container = SKNode()

        // Ground tile
        let groundColor = categoricalGroundColor(for: category)
        let ground = IsoBuilder.groundTile(
            width: tileWidth - 2,
            height: tileHeight - 1,
            fillColor: groundColor,
            strokeColor: SKColor.black.withAlphaComponent(0.25)
        )
        ground.zPosition = -1
        container.addChild(ground)

        // Building: kind-specific placeholder → PNG-first (TASK-032)
        let building = makeKindBuilding(unit: unit, stage: stage)
        building.name = "building"
        building.position = .zero
        container.addChild(building)

        container.userData = NSMutableDictionary()
        container.userData?[unitIdKey] = unit.id
        container.userData?[projectIdKey] = unit.projectId

        return container
    }

    /// Диспетчер по категории → stage sprite. stage зажат в [1..5].
    /// - Note: Deprecated в TASK-036. Новый API: `makeKindStageBuilding(kind:stage:)`.
    @available(*, deprecated, renamed: "makeKindStageBuilding(kind:stage:)")
    static func makeCategoricalBuilding(category: UnitCategory, stage: Int) -> SKNode {
        let s = max(1, min(stage, 5))
        switch category {
        case .residential:    return makeResidentialStage(s)
        case .infrastructure: return makeInfrastructureStage(s)
        case .production:     return makeProductionStage(s)
        case .social:         return makeSocialStage(s)
        // TODO TASK-032: placeholder для новых категорий; финальные спрайты — TASK-040
        case .religious:      return makeSocialStage(s)   // временно social-спрайт
        case .military:       return makeInfrastructureStage(s)  // временно infra-спрайт
        }
    }

    // MARK: - Ground color per category

    /// Статическая таблица цветов тайла-земли по категории.
    private static let groundColorByCategory: [UnitCategory: SKColor] = [
        .residential:    Palette.sandLight,
        .infrastructure: Palette.sandMid,
        .production:     Palette.warmBrown.darkened(by: 0.05),   // выцветшее дерево + кирпич
        .social:         Palette.parchment,
        .religious:      Palette.parchment.lightened(by: 0.05),  // золотисто-светлый камень
        .military:       Palette.smokeGrey.darkened(by: 0.05),   // тёмно-серый камень
    ]

    private static func categoricalGroundColor(for category: UnitCategory) -> SKColor {
        groundColorByCategory[category] ?? Palette.sandLight
    }

    // MARK: - PlaceholderSpec (TASK-032)

    /// Декларативный дескриптор процедурного placeholder-силуэта для одного UnitKind.
    private struct PlaceholderSpec {
        enum RoofStyle { case pyramid, flat, none, dome }
        enum DecorStyle { case none, window, chimney, columns, pediment, banner, smokeStack }

        let footprint: CGSize
        let baseHeight: CGFloat
        let bodyPalette: (top: SKColor, side: SKColor)
        let roof: RoofStyle
        let roofPalette: SKColor
        let decor: [DecorStyle]
    }

    // MARK: - Таблица placeholder-спецификаций (50 юнитов)

    // swiftlint:disable:next function_body_length
    private static let placeholderSpecs: [UnitKind: PlaceholderSpec] = {
        // Shorthand helpers
        func res(_ fp: CGSize, _ h: CGFloat, body: SKColor,
                 roof: PlaceholderSpec.RoofStyle = .pyramid,
                 roofColor: SKColor = Palette.ochre,
                 decor: [PlaceholderSpec.DecorStyle] = []) -> PlaceholderSpec {
            PlaceholderSpec(footprint: fp, baseHeight: h,
                            bodyPalette: (top: body.lightened(by: 0.08), side: body),
                            roof: roof, roofPalette: roofColor, decor: decor)
        }

        // MARK: Residential (12)
        // Grid sizes per TASK-044 table. Footprint px: gridW*28 × gridH*14. Heights scale with size.
        // dugout=1×1, shack=1×1, hut=1×1, house=1×1 → stay small
        // farmHouse=2×2, twoStory=1×2, stoneHse=2×1, townhouse=2×2, tenement=2×2
        // manor=3×2, villa=3×3, palace=3×3
        let dugout    = res(CGSize(width: 26, height: 14), 12,
                            body: Palette.clay.darkened(by: 0.15), roof: .flat,
                            roofColor: Palette.clay.darkened(by: 0.25))
        let shack     = res(CGSize(width: 30, height: 16), 14,
                            body: Palette.clay, roofColor: Palette.ochre)
        let hut       = res(CGSize(width: 32, height: 16), 16,
                            body: Palette.warmBrown.lightened(by: 0.05), roofColor: Palette.ochre)
        let farmHouse = res(CGSize(width: 56, height: 28), 22,  // 2×2
                            body: Palette.warmBrown, roofColor: Palette.clay,
                            decor: [.window])
        let house     = res(CGSize(width: 36, height: 18), 22,
                            body: Palette.stone.lightened(by: 0.06), roofColor: Palette.clay,
                            decor: [.window])
        let twoStory  = res(CGSize(width: 28, height: 28), 28,  // 1×2
                            body: Palette.stone, roofColor: Palette.clay,
                            decor: [.window])
        let stoneHse  = res(CGSize(width: 56, height: 14), 28,  // 2×1
                            body: Palette.stone.darkened(by: 0.08), roofColor: Palette.smokeGrey,
                            decor: [.window])
        let townhouse = res(CGSize(width: 56, height: 28), 34,  // 2×2
                            body: Palette.sandMid, roofColor: Palette.clay,
                            decor: [.window])
        let tenement  = res(CGSize(width: 56, height: 28), 38,  // 2×2
                            body: Palette.sandMid.darkened(by: 0.05), roof: .flat,
                            roofColor: Palette.stone.darkened(by: 0.15), decor: [.window])
        let manor     = res(CGSize(width: 84, height: 28), 34,  // 3×2
                            body: Palette.parchment.darkened(by: 0.08), roofColor: Palette.clay,
                            decor: [.window, .columns])
        let villaSpec = res(CGSize(width: 84, height: 42), 40,  // 3×3
                            body: Palette.parchment, roofColor: Palette.clay.darkened(by: 0.05),
                            decor: [.window, .columns])
        let palace    = res(CGSize(width: 84, height: 42), 48,  // 3×3
                            body: Palette.parchment.lightened(by: 0.04), roofColor: Palette.ochre,
                            decor: [.window, .columns, .pediment])

        // MARK: Infrastructure (9)
        // well=1×1, road=1×1, gate=1×2, bridge=1×3, cistern=2×2, lighthouse=2×2,
        // irrigationCanal=2×1, pier=3×2, warehouse=2×2
        let wellSpec   = res(CGSize(width: 22, height: 12), 8,
                             body: Palette.stone, roof: .none, roofColor: Palette.stone)
        let roadSpec   = res(CGSize(width: 28, height: 14), 4,
                             body: Palette.sandMid.darkened(by: 0.08), roof: .none,
                             roofColor: .clear)
        let gateSpec   = res(CGSize(width: 28, height: 28), 22,  // 1×2
                             body: Palette.stone.darkened(by: 0.05), roof: .flat,
                             roofColor: Palette.stone.darkened(by: 0.20))
        let bridgeSpec = res(CGSize(width: 28, height: 42), 10,  // 1×3
                             body: Palette.stone.lightened(by: 0.06), roof: .none,
                             roofColor: .clear)
        let cisternSpec = res(CGSize(width: 56, height: 28), 16,  // 2×2
                              body: Palette.stone.darkened(by: 0.10), roof: .flat,
                              roofColor: Palette.stone.darkened(by: 0.22))
        let lighthouseSpec = res(CGSize(width: 56, height: 28), 32,  // 2×2
                                 body: Palette.parchment.darkened(by: 0.05),
                                 roof: .pyramid, roofColor: Palette.ochre)
        let canalSpec  = res(CGSize(width: 56, height: 14), 6,  // 2×1
                             body: Palette.skyNight.darkened(by: 0.05), roof: .none,
                             roofColor: .clear)
        let pierSpec   = res(CGSize(width: 84, height: 28), 10,  // 3×2
                             body: Palette.warmBrown.darkened(by: 0.10), roof: .none,
                             roofColor: .clear)
        let warehouseSpec = res(CGSize(width: 56, height: 28), 18,  // 2×2
                                body: Palette.sandLight, roof: .flat,
                                roofColor: Palette.smokeGrey.darkened(by: 0.20))

        // MARK: Production (12)
        // farm=3×3, fishingPier=2×2, workshop=2×1, raw=1×1, forge=2×1, pottery=2×1,
        // brewery=2×2, sawmill=2×2, quarry=3×2, mine=2×2, largeWarehouse=3×2, factory=3×3
        let farmSpec   = res(CGSize(width: 84, height: 42), 14,  // 3×3
                             body: Palette.warmBrown.lightened(by: 0.08), roof: .pyramid,
                             roofColor: Palette.ochre.darkened(by: 0.05))
        let fishPier   = res(CGSize(width: 56, height: 28), 10,  // 2×2
                             body: Palette.warmBrown.darkened(by: 0.12), roof: .flat,
                             roofColor: Palette.warmBrown.darkened(by: 0.22))
        let workshopSpec = res(CGSize(width: 56, height: 14), 18,  // 2×1
                               body: Palette.ochre, roof: .pyramid,
                               roofColor: Palette.smokeGrey, decor: [.chimney])
        let rawSpec    = res(CGSize(width: 28, height: 14), 8,  // 1×1
                             body: Palette.clay.darkened(by: 0.20), roof: .none,
                             roofColor: .clear)
        let forgeSpec  = res(CGSize(width: 56, height: 14), 20,  // 2×1
                             body: Palette.warmBrown.darkened(by: 0.05), roof: .pyramid,
                             roofColor: Palette.smokeGrey.darkened(by: 0.10), decor: [.chimney])
        let potterySpec = res(CGSize(width: 56, height: 14), 16,  // 2×1
                              body: Palette.clay.lightened(by: 0.08), roof: .pyramid,
                              roofColor: Palette.ochre.darkened(by: 0.10))
        let brewerySpec = res(CGSize(width: 56, height: 28), 20,  // 2×2
                              body: Palette.ochre.darkened(by: 0.08), roof: .pyramid,
                              roofColor: Palette.warmBrown, decor: [.chimney])
        let sawmillSpec = res(CGSize(width: 56, height: 28), 16,  // 2×2
                              body: Palette.warmBrown.lightened(by: 0.05), roof: .pyramid,
                              roofColor: Palette.warmBrown.darkened(by: 0.25))
        let quarrySpec  = res(CGSize(width: 84, height: 28), 16,  // 3×2
                              body: Palette.stone.darkened(by: 0.15), roof: .flat,
                              roofColor: Palette.stone.darkened(by: 0.28))
        let mineSpec    = res(CGSize(width: 56, height: 28), 22,  // 2×2
                              body: Palette.stone.darkened(by: 0.22), roof: .flat,
                              roofColor: Palette.stone.darkened(by: 0.32), decor: [.smokeStack])
        let lgWarehouse = res(CGSize(width: 84, height: 28), 26,  // 3×2
                              body: Palette.sandLight.darkened(by: 0.05), roof: .flat,
                              roofColor: Palette.stone.darkened(by: 0.18), decor: [.smokeStack])
        let factorySpec = res(CGSize(width: 84, height: 42), 40,  // 3×3
                              body: Palette.sandMid.darkened(by: 0.08), roof: .flat,
                              roofColor: Palette.stone.darkened(by: 0.22),
                              decor: [.chimney, .smokeStack])

        // MARK: Social (12 including temple/obelisk legacy)
        // tavern=2×1, market=2×2, plaza=3×3, bathhouse=2×2, school=2×2, hospital=2×2,
        // forum=3×3, library=2×2, aqueduct=1×3, theater=3×3, temple=3×3, obelisk=1×1
        let tavernSpec  = res(CGSize(width: 56, height: 14), 14,  // 2×1
                              body: Palette.warmBrown.lightened(by: 0.05), roof: .pyramid,
                              roofColor: Palette.skyDusk.lightened(by: 0.08))
        let marketSpec  = res(CGSize(width: 56, height: 28), 14,  // 2×2
                              body: Palette.sandLight, roof: .pyramid,
                              roofColor: Palette.skyDusk, decor: [.columns])
        let plazaSpec   = res(CGSize(width: 84, height: 42), 8,  // 3×3
                              body: Palette.parchment, roof: .flat,
                              roofColor: Palette.parchment.darkened(by: 0.10))
        let bathhouseSpec = res(CGSize(width: 56, height: 28), 20,  // 2×2
                                body: Palette.parchment.darkened(by: 0.05), roof: .dome,
                                roofColor: Palette.stone.lightened(by: 0.10))
        let schoolSpec  = res(CGSize(width: 56, height: 28), 18,  // 2×2
                              body: Palette.parchment.darkened(by: 0.08), roof: .pyramid,
                              roofColor: Palette.clay.lightened(by: 0.05), decor: [.window])
        let hospitalSpec = res(CGSize(width: 56, height: 28), 22,  // 2×2
                               body: Palette.parchment, roof: .pyramid,
                               roofColor: Palette.sandMid, decor: [.window])
        let forumSpec   = res(CGSize(width: 84, height: 42), 26,  // 3×3
                              body: Palette.parchment.darkened(by: 0.08), roof: .flat,
                              roofColor: Palette.parchment.darkened(by: 0.12), decor: [.columns])
        let librarySpec = res(CGSize(width: 56, height: 28), 24,  // 2×2
                              body: Palette.parchment, roof: .pyramid,
                              roofColor: Palette.ochre, decor: [.columns])
        let aqueductSpec = res(CGSize(width: 28, height: 42), 22,  // 1×3
                               body: Palette.parchment.darkened(by: 0.05), roof: .flat,
                               roofColor: Palette.stone.darkened(by: 0.12), decor: [.columns])
        let theaterSpec = res(CGSize(width: 84, height: 42), 30,  // 3×3
                              body: Palette.parchment, roof: .pyramid,
                              roofColor: Palette.skyDusk.lightened(by: 0.05), decor: [.columns])
        let templeSpec  = res(CGSize(width: 84, height: 42), 30,  // 3×3
                              body: Palette.parchment.darkened(by: 0.05), roof: .pyramid,
                              roofColor: Palette.ochre, decor: [.columns, .pediment])
        let obeliskSpec = res(CGSize(width: 16, height: 8), 36,  // 1×1 (tall, narrow)
                              body: Palette.sandMid, roof: .pyramid,
                              roofColor: Palette.ochre)

        // MARK: Religious (3 of 5 that exist in enum)
        // chapel=2×1, cathedral=3×3, pyramid=4×4
        let chapelSpec   = res(CGSize(width: 56, height: 14), 18,  // 2×1
                               body: Palette.parchment.darkened(by: 0.05), roof: .pyramid,
                               roofColor: Palette.ochre.lightened(by: 0.05))
        let cathedralSpec = res(CGSize(width: 84, height: 42), 46,  // 3×3
                                body: Palette.parchment.lightened(by: 0.04), roof: .pyramid,
                                roofColor: Palette.ochre.lightened(by: 0.08), decor: [.columns, .pediment])
        let pyramidSpec  = PlaceholderSpec(
            footprint: CGSize(width: 112, height: 56), baseHeight: 60,  // 4×4
            bodyPalette: (top: Palette.sandLight.lightened(by: 0.06), side: Palette.sandLight),
            roof: .pyramid, roofPalette: Palette.ochre.lightened(by: 0.06), decor: [])

        // MARK: Military (3)
        // watchtower=2×1, barracks=2×2, shipyard=3×3
        let watchtowerSpec = res(CGSize(width: 56, height: 14), 28,  // 2×1 (tall tower)
                                 body: Palette.stone.darkened(by: 0.10), roof: .pyramid,
                                 roofColor: Palette.smokeGrey.darkened(by: 0.12))
        let barracksSpec   = res(CGSize(width: 56, height: 28), 24,  // 2×2
                                 body: Palette.stone.darkened(by: 0.15), roof: .flat,
                                 roofColor: Palette.stone.darkened(by: 0.28))
        let shipyardSpec   = res(CGSize(width: 84, height: 42), 18,  // 3×3
                                 body: Palette.warmBrown.darkened(by: 0.15), roof: .flat,
                                 roofColor: Palette.warmBrown.darkened(by: 0.30))

        return [
            // Residential
            .dugout:        dugout,
            .shack:         shack,
            .hut:           hut,
            .farmHouse:     farmHouse,
            .house:         house,
            .twoStoryHouse: twoStory,
            .stoneHouse:    stoneHse,
            .townhouse:     townhouse,
            .tenement:      tenement,
            .manor:         manor,
            .villa:         villaSpec,
            .palace:        palace,
            // Infrastructure
            .well:            wellSpec,
            .road:            roadSpec,
            .gate:            gateSpec,
            .bridge:          bridgeSpec,
            .cistern:         cisternSpec,
            .lighthouse:      lighthouseSpec,
            .irrigationCanal: canalSpec,
            .pier:            pierSpec,
            .warehouse:       warehouseSpec,
            // Production
            .farm:          farmSpec,
            .fishingPier:   fishPier,
            .workshop:      workshopSpec,
            .raw:           rawSpec,
            .forge:         forgeSpec,
            .pottery:       potterySpec,
            .brewery:       brewerySpec,
            .sawmill:       sawmillSpec,
            .quarry:        quarrySpec,
            .mine:          mineSpec,
            .largeWarehouse: lgWarehouse,
            .factory:       factorySpec,
            // Social
            .tavern:    tavernSpec,
            .market:    marketSpec,
            .plaza:     plazaSpec,
            .bathhouse: bathhouseSpec,
            .school:    schoolSpec,
            .hospital:  hospitalSpec,
            .forum:     forumSpec,
            .library:   librarySpec,
            .aqueduct:  aqueductSpec,
            .theater:   theaterSpec,
            .temple:    templeSpec,
            .obelisk:   obeliskSpec,
            // Religious
            .chapel:    chapelSpec,
            .cathedral: cathedralSpec,
            .pyramid:   pyramidSpec,
            // Military
            .watchtower: watchtowerSpec,
            .barracks:   barracksSpec,
            .shipyard:   shipyardSpec,
        ]
    }()

    // MARK: - Universal placeholder builder

    /// Строит процедурный силуэт по spec. Если large == true — высота +30% (AC #3).
    private static func makePlaceholderBuilding(spec: PlaceholderSpec, large: Bool) -> SKNode {
        let node = SKNode()
        let h = large ? spec.baseHeight * 1.3 : spec.baseHeight
        let fp = spec.footprint

        // Body (cube)
        if h > 0 {
            let body = IsoBuilder.cube(
                footprint: fp, height: h,
                colors: .init(
                    top:    spec.bodyPalette.top,
                    left:   spec.bodyPalette.side,
                    right:  spec.bodyPalette.side.darkened(by: 0.18),
                    stroke: Palette.inkDark.withAlphaComponent(0.6)
                )
            )
            node.addChild(body)

            // Brick hatch
            let rows = max(1, Int(h / 6))
            node.addChild(IsoBuilder.brickHatch(
                footprint: fp, height: h, rows: rows,
                color: Palette.inkDark.withAlphaComponent(0.18)
            ))
        }

        // Roof
        switch spec.roof {
        case .pyramid:
            let peak = max(8, h * 0.35)
            let roofNode = IsoBuilder.pyramidRoof(
                footprint: fp, peak: peak,
                leftColor: spec.roofPalette,
                rightColor: spec.roofPalette.darkened(by: 0.18),
                strokeColor: Palette.inkDark.withAlphaComponent(0.6)
            )
            roofNode.position = CGPoint(x: 0, y: h)
            node.addChild(roofNode)
        case .flat:
            let topShade = IsoBuilder.groundTile(
                width: fp.width, height: fp.height,
                fillColor: spec.roofPalette,
                strokeColor: Palette.inkDark
            )
            topShade.position = CGPoint(x: 0, y: h)
            node.addChild(topShade)
        case .dome:
            let dome = SKShapeNode(circleOfRadius: fp.width * 0.38)
            dome.fillColor = spec.roofPalette.lightened(by: 0.08)
            dome.strokeColor = Palette.inkDark.withAlphaComponent(0.5)
            dome.lineWidth = 0.8
            dome.position = CGPoint(x: 0, y: h + fp.width * 0.18)
            node.addChild(dome)
        case .none:
            break
        }

        // Decor
        for style in spec.decor {
            switch style {
            case .window:
                let win = SKShapeNode(rect: CGRect(x: -2.5, y: 0, width: 5, height: 5))
                win.fillColor = Palette.skyNight.withAlphaComponent(0.80)
                win.strokeColor = Palette.inkDark.withAlphaComponent(0.5)
                win.lineWidth = 0.5
                win.position = CGPoint(x: 6, y: h * 0.42)
                node.addChild(win)
            case .chimney:
                let chimney = IsoBuilder.cube(
                    footprint: CGSize(width: 5, height: 3), height: 8,
                    colors: .init(
                        top:    Palette.smokeGrey.darkened(by: 0.18),
                        left:   Palette.smokeGrey.darkened(by: 0.28),
                        right:  Palette.smokeGrey.darkened(by: 0.40),
                        stroke: Palette.inkDark.withAlphaComponent(0.7)
                    )
                )
                chimney.position = CGPoint(x: -fp.width * 0.18, y: h + 4)
                node.addChild(chimney)
            case .columns:
                for dx in [-fp.width * 0.3, fp.width * 0.3] {
                    let col = IsoBuilder.cube(
                        footprint: CGSize(width: 3, height: 2), height: min(h * 0.7, 18),
                        colors: .init(
                            top:    Palette.parchment,
                            left:   Palette.parchment.darkened(by: 0.08),
                            right:  Palette.parchment.darkened(by: 0.18),
                            stroke: Palette.inkDark.withAlphaComponent(0.5)
                        )
                    )
                    col.position = CGPoint(x: dx, y: h * 0.1)
                    node.addChild(col)
                }
            case .pediment:
                let innerFp = CGSize(width: fp.width * 0.7, height: fp.height * 0.7)
                let ped = IsoBuilder.pyramidRoof(
                    footprint: innerFp, peak: 12,
                    leftColor: Palette.ochre,
                    rightColor: Palette.ochre.darkened(by: 0.20),
                    strokeColor: Palette.inkDark.withAlphaComponent(0.6)
                )
                ped.position = CGPoint(x: 0, y: h)
                node.addChild(ped)
            case .smokeStack:
                let stack = IsoBuilder.cube(
                    footprint: CGSize(width: 5, height: 3), height: 12,
                    colors: .init(
                        top:    Palette.smokeGrey.darkened(by: 0.20),
                        left:   Palette.smokeGrey.darkened(by: 0.30),
                        right:  Palette.smokeGrey.darkened(by: 0.42),
                        stroke: Palette.inkDark.withAlphaComponent(0.7)
                    )
                )
                stack.position = CGPoint(x: fp.width * 0.20, y: h + 2)
                node.addChild(stack)
            case .banner:
                let pole = SKShapeNode(rect: CGRect(x: -0.5, y: 0, width: 1, height: 10))
                pole.fillColor = Palette.warmBrown
                pole.strokeColor = .clear
                pole.position = CGPoint(x: 0, y: h + 2)
                node.addChild(pole)
                let flag = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 8, height: 5))
                flag.fillColor = Palette.clay
                flag.strokeColor = Palette.inkDark.withAlphaComponent(0.4)
                flag.lineWidth = 0.5
                flag.position = CGPoint(x: 0, y: h + 8)
                node.addChild(flag)
            case .none:
                break
            }
        }

        return node
    }

    // MARK: - Fallback categorical spec

    /// Возвращает умолчальный spec по категории для kind'ов без явной строки в таблице.
    /// Safety net: в нормальной работе не срабатывает, т.к. все 50 kind'ов покрыты.
    private static func fallbackSpec(for category: UnitCategory, stage: Int) -> PlaceholderSpec {
        let s = max(1, min(stage, 5))
        let baseHeight: CGFloat = CGFloat(s) * 6 + 8
        switch category {
        case .residential:
            return PlaceholderSpec(
                footprint: CGSize(width: 32, height: 16), baseHeight: baseHeight,
                bodyPalette: (top: Palette.clay.lightened(by: 0.08), side: Palette.clay),
                roof: .pyramid, roofPalette: Palette.ochre, decor: [])
        case .infrastructure:
            return PlaceholderSpec(
                footprint: CGSize(width: 28, height: 14), baseHeight: baseHeight,
                bodyPalette: (top: Palette.stone.lightened(by: 0.08), side: Palette.stone),
                roof: .flat, roofPalette: Palette.stone.darkened(by: 0.18), decor: [])
        case .production:
            return PlaceholderSpec(
                footprint: CGSize(width: 34, height: 18), baseHeight: baseHeight,
                bodyPalette: (top: Palette.ochre.lightened(by: 0.05), side: Palette.ochre),
                roof: .pyramid, roofPalette: Palette.smokeGrey, decor: [])
        case .social:
            return PlaceholderSpec(
                footprint: CGSize(width: 36, height: 18), baseHeight: baseHeight,
                bodyPalette: (top: Palette.parchment, side: Palette.parchment.darkened(by: 0.08)),
                roof: .pyramid, roofPalette: Palette.skyDusk, decor: [])
        case .religious:
            return PlaceholderSpec(
                footprint: CGSize(width: 30, height: 16), baseHeight: baseHeight,
                bodyPalette: (top: Palette.parchment.lightened(by: 0.04), side: Palette.parchment),
                roof: .pyramid, roofPalette: Palette.ochre.lightened(by: 0.05), decor: [])
        case .military:
            return PlaceholderSpec(
                footprint: CGSize(width: 32, height: 16), baseHeight: baseHeight,
                bodyPalette: (top: Palette.stone.darkened(by: 0.08), side: Palette.stone.darkened(by: 0.12)),
                roof: .flat, roofPalette: Palette.stone.darkened(by: 0.28), decor: [])
        }
    }

    // MARK: - Kind-level building dispatch (TASK-032)

    /// Точка входа для рендеринга: PNG-first → placeholder по kind-spec → fallback по category.
    /// effectiveStage = max(stage, kind.minStage) — защита от вызова ниже minStage.
    static func makeKindBuilding(unit: UnitState, stage: Int) -> SKNode {
        let kind = unit.kind
        let effectiveStage = max(stage, kind.minStage)

        // PNG-first: stage-suffix → без суффикса → placeholder
        let rawVal = kind.rawValue
        if let sprite = loadBuildingSprite(
            named: "\(rawVal)_stage\(effectiveStage)",
            targetWidth: 64, anchorY: 0.30) {
            sprite.name = "building"
            return sprite
        }
        if let sprite = loadBuildingSprite(named: rawVal, targetWidth: 64, anchorY: 0.30) {
            sprite.name = "building"
            return sprite
        }

        // Procedural placeholder
        let spec = placeholderSpecs[kind] ?? fallbackSpec(for: kind.category, stage: effectiveStage)
        return makePlaceholderBuilding(spec: spec, large: kind.large)
    }

    // MARK: - Kind × Stage building dispatch (TASK-036)

    /// Tier-визуал для конкретного UnitKind на заданном stage квартала.
    ///
    /// stage зажимается в [kind.minStage ... 5]; при stage < minStage рисуется placeholder
    /// для stage = kind.minStage (edge case: Дворец на stage 0 → рисуется stage 5).
    ///
    /// Стратегия (порядок):
    ///   1. PNG `<kind>_stage<effectiveStage>.png` с fallback по убыванию stage до minStage;
    ///   2. PNG `<kind>.png` (single-stage large без tier'ов);
    ///   3. Процедурный placeholder через makeProceduralBuilding(kind:stage:).
    static func makeKindStageBuilding(kind: UnitKind, stage: Int) -> SKNode {
        let minS = kind.minStage
        let effective = max(minS, min(stage, 5))
        let rawVal = kind.rawValue

        // 1. PNG с tier-суффиксом — fallback по убыванию stage до minStage.
        for s in stride(from: effective, through: minS, by: -1) {
            let name = "\(rawVal)_stage\(s)"
            if let sprite = loadBuildingSprite(named: name, targetWidth: tileWidth, anchorY: 0.30) {
                let node = SKNode()
                sprite.name = "building"
                node.addChild(sprite)
                return node
            }
        }

        // 2. PNG без stage-суффикса (large-юниты без stage-вариаций).
        if let sprite = loadBuildingSprite(named: rawVal, targetWidth: tileWidth, anchorY: 0.30) {
            let node = SKNode()
            sprite.name = "building"
            node.addChild(sprite)
            return node
        }

        // 3. Процедурный placeholder по категории/kind.
        return makeProceduralBuilding(kind: kind, stage: effective)
    }

    /// Диспетчер процедурных placeholder'ов по категории.
    /// Для residential/religious/military — per-kind фабрики (TASK-036).
    /// Для infra/production/social — делегируем в категориальные (satisfies AC «≥2 tier»).
    private static func makeProceduralBuilding(kind: UnitKind, stage: Int) -> SKNode {
        switch kind.category {
        case .residential:
            return makeResidentialKind(kind: kind, stage: stage)
        case .religious:
            return makeReligiousStage(kind: kind, stage: stage)
        case .military:
            return makeMilitaryStage(kind: kind, stage: stage)
        case .infrastructure:
            return makeInfrastructureStage(stage)
        case .production:
            return makeProductionStage(stage)
        case .social:
            return makeSocialStage(stage)
        }
    }

    // MARK: - Residential per-kind tier factory (TASK-036)

    /// Dispatcher для 12 жилых юнитов: каждый kind → индивидуальный визуал по stage.
    /// Tier-лестница: dugout(h8) → shack(h14) → hut/farmHouse(h16) → house/stoneHouse(h22)
    ///   → twoStoryHouse/townhouse(h28) → tenement(h34) → manor/villa(h40) → palace(h48).
    private static func makeResidentialKind(kind: UnitKind, stage: Int) -> SKNode {
        // Residential preset: (footprint, height, bodyColor, roofStyle, roofColor, decors)
        struct Preset {
            let fp: CGSize
            let h: CGFloat
            let body: SKColor
            let roofStyle: PlaceholderSpec.RoofStyle
            let roofColor: SKColor
            let windows: Int     // 0–3 windows per row
            let windowRows: Int  // 0–2 rows
        }

        let preset: Preset
        switch kind {
        case .dugout:
            // Землянка: низкий, плоская крыша, землянистый цвет
            preset = Preset(fp: CGSize(width: 26, height: 14), h: 8,
                            body: Palette.clay.darkened(by: 0.15), roofStyle: .flat,
                            roofColor: Palette.clay.darkened(by: 0.25), windows: 0, windowRows: 0)
        case .shack:
            preset = Preset(fp: CGSize(width: 30, height: 16), h: 14,
                            body: Palette.clay, roofStyle: .pyramid,
                            roofColor: Palette.ochre, windows: 0, windowRows: 0)
        case .hut:
            preset = Preset(fp: CGSize(width: 32, height: 16), h: 16,
                            body: Palette.warmBrown.lightened(by: 0.05), roofStyle: .pyramid,
                            roofColor: Palette.ochre, windows: 1, windowRows: 1)
        case .farmHouse:
            preset = Preset(fp: CGSize(width: 34, height: 18), h: 18,
                            body: Palette.warmBrown, roofStyle: .pyramid,
                            roofColor: Palette.clay, windows: 1, windowRows: 1)
        case .house:
            preset = Preset(fp: CGSize(width: 36, height: 18), h: 22,
                            body: Palette.stone.lightened(by: 0.06), roofStyle: .pyramid,
                            roofColor: Palette.clay, windows: 1, windowRows: 1)
        case .twoStoryHouse:
            preset = Preset(fp: CGSize(width: 34, height: 18), h: 28,
                            body: Palette.stone, roofStyle: .pyramid,
                            roofColor: Palette.clay, windows: 1, windowRows: 2)
        case .stoneHouse:
            preset = Preset(fp: CGSize(width: 38, height: 20), h: 28,
                            body: Palette.stone.darkened(by: 0.08), roofStyle: .pyramid,
                            roofColor: Palette.smokeGrey, windows: 2, windowRows: 1)
        case .townhouse:
            preset = Preset(fp: CGSize(width: 34, height: 18), h: 34,
                            body: Palette.sandMid, roofStyle: .pyramid,
                            roofColor: Palette.clay, windows: 2, windowRows: 2)
        case .tenement:
            preset = Preset(fp: CGSize(width: 38, height: 20), h: 38,
                            body: Palette.sandMid.darkened(by: 0.05), roofStyle: .flat,
                            roofColor: Palette.stone.darkened(by: 0.15), windows: 3, windowRows: 2)
        case .manor:
            preset = Preset(fp: CGSize(width: 46, height: 24), h: 34,
                            body: Palette.parchment.darkened(by: 0.08), roofStyle: .pyramid,
                            roofColor: Palette.clay, windows: 2, windowRows: 2)
        case .villa:
            preset = Preset(fp: CGSize(width: 48, height: 24), h: 40,
                            body: Palette.parchment, roofStyle: .pyramid,
                            roofColor: Palette.clay.darkened(by: 0.05), windows: 3, windowRows: 2)
        case .palace:
            preset = Preset(fp: CGSize(width: 52, height: 28), h: 48,
                            body: Palette.parchment.lightened(by: 0.04), roofStyle: .pyramid,
                            roofColor: Palette.ochre, windows: 3, windowRows: 2)
        default:
            // Safety net: не должно срабатывать для residential — делегируем в категориальный.
            return makeResidentialStage(stage)
        }

        let node = SKNode()
        // Тело здания (масштаб высоты по stage для tier-вариации)
        let stageMult: CGFloat = stage <= 1 ? 0.85 : (stage >= 4 ? 1.10 : 1.0)
        let h = preset.h * stageMult

        let body = IsoBuilder.cube(
            footprint: preset.fp, height: h,
            colors: .init(
                top:    preset.body.lightened(by: 0.08),
                left:   preset.body,
                right:  preset.body.darkened(by: 0.18),
                stroke: Palette.inkDark.withAlphaComponent(0.6)
            )
        )
        node.addChild(body)

        // Кирпичный хэтч
        let rows = max(1, Int(h / 6))
        node.addChild(IsoBuilder.brickHatch(
            footprint: preset.fp, height: h, rows: rows,
            color: Palette.inkDark.withAlphaComponent(0.18)
        ))

        // Крыша
        switch preset.roofStyle {
        case .pyramid:
            let peak = max(8, h * 0.35)
            let roof = IsoBuilder.pyramidRoof(
                footprint: preset.fp, peak: peak,
                leftColor: preset.roofColor,
                rightColor: preset.roofColor.darkened(by: 0.18),
                strokeColor: Palette.inkDark.withAlphaComponent(0.6)
            )
            roof.position = CGPoint(x: 0, y: h)
            node.addChild(roof)
        case .flat:
            let topShade = IsoBuilder.groundTile(
                width: preset.fp.width, height: preset.fp.height,
                fillColor: preset.roofColor,
                strokeColor: Palette.inkDark
            )
            topShade.position = CGPoint(x: 0, y: h)
            node.addChild(topShade)
        default:
            break
        }

        // Окна
        if preset.windowRows > 0 && preset.windows > 0 {
            let rowPositions: [CGFloat] = preset.windowRows == 1 ? [0.42] : [0.30, 0.60]
            let totalWins = preset.windows
            let spacing = preset.fp.width / CGFloat(totalWins + 1)
            for rowFrac in rowPositions.prefix(preset.windowRows) {
                for i in 1...totalWins {
                    let win = SKShapeNode(rect: CGRect(x: -2.5, y: 0, width: 5, height: 5))
                    win.fillColor = Palette.skyNight.withAlphaComponent(0.82)
                    win.strokeColor = Palette.inkDark.withAlphaComponent(0.5)
                    win.lineWidth = 0.4
                    win.position = CGPoint(
                        x: CGFloat(i) * spacing - preset.fp.width / 2,
                        y: h * rowFrac
                    )
                    node.addChild(win)
                }
            }
        }

        // Для palace — добавляем колонны-балкон
        if kind == .palace {
            for dx: CGFloat in [-preset.fp.width * 0.3, preset.fp.width * 0.3] {
                let col = IsoBuilder.cube(
                    footprint: CGSize(width: 3, height: 2), height: min(h * 0.6, 18),
                    colors: .init(
                        top:    Palette.parchment,
                        left:   Palette.parchment.darkened(by: 0.08),
                        right:  Palette.parchment.darkened(by: 0.18),
                        stroke: Palette.inkDark.withAlphaComponent(0.5)
                    )
                )
                col.position = CGPoint(x: dx, y: h * 0.1)
                node.addChild(col)
            }
        }

        return node
    }

    // MARK: - Religious stage factory (TASK-036)

    /// 2+ tier'а для религиозных юнитов:
    ///   tier «low»  (stage 1–2): компактный, h~22, пирамидальная крыша;
    ///   tier «mid»  (stage 3):   каменный с колоннадой, h~34;
    ///   tier «high» (stage 4–5): монументальный, h~48, шпиль/купол.
    private static func makeReligiousStage(kind: UnitKind, stage: Int) -> SKNode {
        let node = SKNode()
        let tier: Int
        switch stage {
        case 0...2: tier = 1
        case 3:     tier = 2
        default:    tier = 3
        }

        // Базовые параметры по tier'у
        let fp: CGSize
        let h: CGFloat
        let bodyColor: SKColor
        let roofColor: SKColor

        switch tier {
        case 1:  // низкий — Часовня-стиль
            fp = CGSize(width: 28, height: 14)
            h = 22
            bodyColor = Palette.parchment.darkened(by: 0.05)
            roofColor = Palette.ochre.lightened(by: 0.05)
        case 2:  // средний — Храм с колоннадой
            fp = CGSize(width: 40, height: 22)
            h = 34
            bodyColor = Palette.parchment.darkened(by: 0.03)
            roofColor = Palette.ochre
        default: // высокий — Собор/Пирамида
            fp = CGSize(width: 52, height: 28)
            h = 48
            bodyColor = Palette.parchment.lightened(by: 0.04)
            roofColor = Palette.ochre.lightened(by: 0.08)
        }

        // Для пирамиды — особый силуэт: песчаный цвет
        let isActualPyramid = (kind == .pyramid)
        let finalBodyColor = isActualPyramid ? Palette.sandLight : bodyColor
        let finalRoofColor = isActualPyramid ? Palette.ochre.lightened(by: 0.06) : roofColor

        // Тело
        let body = IsoBuilder.cube(
            footprint: fp, height: h,
            colors: .init(
                top:    finalBodyColor.lightened(by: 0.06),
                left:   finalBodyColor,
                right:  finalBodyColor.darkened(by: 0.20),
                stroke: Palette.inkDark.withAlphaComponent(0.6)
            )
        )
        node.addChild(body)
        node.addChild(IsoBuilder.brickHatch(
            footprint: fp, height: h, rows: max(2, Int(h / 8)),
            color: Palette.inkDark.withAlphaComponent(0.15)
        ))

        // Крыша / шпиль
        if isActualPyramid {
            // Пирамида: огромный пирамидальный шпиль
            let pyramid = IsoBuilder.pyramidRoof(
                footprint: fp, peak: h * 0.8,
                leftColor: finalRoofColor,
                rightColor: finalRoofColor.darkened(by: 0.18),
                strokeColor: Palette.inkDark.withAlphaComponent(0.6)
            )
            pyramid.position = CGPoint(x: 0, y: h)
            node.addChild(pyramid)
        } else {
            let peak = max(10, h * 0.30)
            let roof = IsoBuilder.pyramidRoof(
                footprint: fp, peak: peak,
                leftColor: finalRoofColor,
                rightColor: finalRoofColor.darkened(by: 0.18),
                strokeColor: Palette.inkDark.withAlphaComponent(0.6)
            )
            roof.position = CGPoint(x: 0, y: h)
            node.addChild(roof)
        }

        // Tier 2+: колонны по фасаду
        if tier >= 2 {
            let colCount = tier == 2 ? 3 : 5
            let spread = fp.width * 0.36
            let step = spread * 2 / CGFloat(colCount - 1)
            for i in 0..<colCount {
                let dx = -spread + CGFloat(i) * step
                let col = IsoBuilder.cube(
                    footprint: CGSize(width: 3, height: 2), height: min(h * 0.65, 22),
                    colors: .init(
                        top:    Palette.parchment,
                        left:   Palette.parchment.darkened(by: 0.08),
                        right:  Palette.parchment.darkened(by: 0.18),
                        stroke: Palette.inkDark.withAlphaComponent(0.5)
                    )
                )
                col.position = CGPoint(x: dx, y: h * 0.08)
                node.addChild(col)
            }
        }

        // Tier 3: шпиль поверх купола
        if tier == 3 && !isActualPyramid {
            let spire = IsoBuilder.cube(
                footprint: CGSize(width: 5, height: 3), height: 20,
                colors: .init(
                    top:    Palette.ochre,
                    left:   Palette.ochre.darkened(by: 0.15),
                    right:  Palette.ochre.darkened(by: 0.30),
                    stroke: Palette.inkDark.withAlphaComponent(0.7)
                )
            )
            spire.position = CGPoint(x: 0, y: h + peak(for: fp, h: h))
            node.addChild(spire)
        }

        return node
    }

    /// Helper: высота пика для симметрии шпиля над крышей.
    private static func peak(for fp: CGSize, h: CGFloat) -> CGFloat {
        max(10, h * 0.30)
    }

    // MARK: - Military stage factory (TASK-036)

    /// 3 tier'а для военных юнитов:
    ///   tier «low»  (stage 1–2): Сторожевая башня — узкий высокий куб, флажок;
    ///   tier «mid»  (stage 3):   Казармы — широкий куб, амбразуры;
    ///   tier «high» (stage 4–5): Верфь — низкий L-образный, слип к воде.
    private static func makeMilitaryStage(kind: UnitKind, stage: Int) -> SKNode {
        let node = SKNode()
        // Маппинг kind → tier
        let tier: Int
        switch kind {
        case .watchtower: tier = 1
        case .barracks:   tier = 2
        case .shipyard:   tier = 3
        default:          tier = max(1, min(3, stage - 1))
        }

        switch tier {
        case 1:
            // Сторожевая башня: узкий высокий куб h=36, остроконечная крыша, флажок
            let fp = CGSize(width: 20, height: 12)
            let h: CGFloat = 36
            let body = IsoBuilder.cube(
                footprint: fp, height: h,
                colors: .init(
                    top:    Palette.stone.darkened(by: 0.08),
                    left:   Palette.stone.darkened(by: 0.10),
                    right:  Palette.stone.darkened(by: 0.25),
                    stroke: Palette.inkDark
                )
            )
            node.addChild(body)
            node.addChild(IsoBuilder.brickHatch(
                footprint: fp, height: h, rows: 6,
                color: Palette.inkDark.withAlphaComponent(0.22)
            ))
            // Остроконечная крыша
            let roof = IsoBuilder.pyramidRoof(
                footprint: fp, peak: 14,
                leftColor: Palette.smokeGrey.darkened(by: 0.10),
                rightColor: Palette.smokeGrey.darkened(by: 0.25),
                strokeColor: Palette.inkDark.withAlphaComponent(0.7)
            )
            roof.position = CGPoint(x: 0, y: h)
            node.addChild(roof)
            // Флажок-треугольник
            let pole = SKShapeNode(rect: CGRect(x: -0.5, y: 0, width: 1, height: 10))
            pole.fillColor = Palette.warmBrown
            pole.strokeColor = .clear
            pole.position = CGPoint(x: 0, y: h + 14)
            node.addChild(pole)
            let flag = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 8, height: 5))
            flag.fillColor = Palette.clay
            flag.strokeColor = Palette.inkDark.withAlphaComponent(0.4)
            flag.lineWidth = 0.5
            flag.position = CGPoint(x: 0, y: h + 20)
            node.addChild(flag)
            // Амбразуры (тёмные прямоугольники)
            for dx in [-5, 5] {
                let embrasure = SKShapeNode(rect: CGRect(x: -1.5, y: 0, width: 3, height: 4))
                embrasure.fillColor = Palette.inkDark.withAlphaComponent(0.70)
                embrasure.strokeColor = .clear
                embrasure.position = CGPoint(x: CGFloat(dx), y: h * 0.70)
                node.addChild(embrasure)
            }

        case 2:
            // Казармы: широкий куб h=24, плоская крыша, амбразуры
            let fp = CGSize(width: 48, height: 24)
            let h: CGFloat = 24
            let body = IsoBuilder.cube(
                footprint: fp, height: h,
                colors: .init(
                    top:    Palette.stone.darkened(by: 0.12),
                    left:   Palette.stone.darkened(by: 0.15),
                    right:  Palette.stone.darkened(by: 0.30),
                    stroke: Palette.inkDark
                )
            )
            node.addChild(body)
            node.addChild(IsoBuilder.brickHatch(
                footprint: fp, height: h, rows: 4,
                color: Palette.inkDark.withAlphaComponent(0.22)
            ))
            // Плоская крыша
            let topShade = IsoBuilder.groundTile(
                width: fp.width, height: fp.height,
                fillColor: Palette.stone.darkened(by: 0.28),
                strokeColor: Palette.inkDark
            )
            topShade.position = CGPoint(x: 0, y: h)
            node.addChild(topShade)
            // Амбразуры (один ряд)
            for dx in stride(from: -18, through: 18, by: 9) {
                let emb = SKShapeNode(rect: CGRect(x: -1.5, y: 0, width: 3, height: 4))
                emb.fillColor = Palette.inkDark.withAlphaComponent(0.70)
                emb.strokeColor = .clear
                emb.position = CGPoint(x: CGFloat(dx), y: h * 0.72)
                node.addChild(emb)
            }

        default:
            // Верфь: низкий широкий объект h=18, деревянные балки, "слип" (наклонный пандус)
            let fp = CGSize(width: 52, height: 22)
            let h: CGFloat = 18
            let body = IsoBuilder.cube(
                footprint: fp, height: h,
                colors: .init(
                    top:    Palette.warmBrown.darkened(by: 0.12),
                    left:   Palette.warmBrown.darkened(by: 0.15),
                    right:  Palette.warmBrown.darkened(by: 0.30),
                    stroke: Palette.inkDark
                )
            )
            node.addChild(body)
            node.addChild(IsoBuilder.brickHatch(
                footprint: fp, height: h, rows: 3,
                color: Palette.inkDark.withAlphaComponent(0.25)
            ))
            // Плоская деревянная крыша
            let topShade = IsoBuilder.groundTile(
                width: fp.width, height: fp.height,
                fillColor: Palette.warmBrown.darkened(by: 0.30),
                strokeColor: Palette.inkDark
            )
            topShade.position = CGPoint(x: 0, y: h)
            node.addChild(topShade)
            // Слип: горизонтальная полоса к воде (симуляция пандуса)
            let slipW: CGFloat = fp.width * 0.4
            let slip = IsoBuilder.groundTile(
                width: slipW, height: 8,
                fillColor: Palette.warmBrown.darkened(by: 0.22),
                strokeColor: Palette.inkDark.withAlphaComponent(0.5)
            )
            slip.position = CGPoint(x: fp.width * 0.25, y: -4)
            node.addChild(slip)
        }

        return node
    }

    // MARK: - Deprecated categorical API (kept for legacy callers)

    /// - Note: Deprecated в TASK-036. Используй `makeKindStageBuilding(kind:stage:)`.
    @available(*, deprecated, renamed: "makeKindStageBuilding(kind:stage:)")
    static func _makeCategoricalBuildingLegacy(category: UnitCategory, stage: Int) -> SKNode {
        let s = max(1, min(stage, 5))
        switch category {
        case .residential:    return makeResidentialStage(s)
        case .infrastructure: return makeInfrastructureStage(s)
        case .production:     return makeProductionStage(s)
        case .social:         return makeSocialStage(s)
        case .religious:      return makeSocialStage(s)
        case .military:       return makeInfrastructureStage(s)
        }
    }

    // MARK: - Debug coverage assertion

    #if DEBUG
    /// Проверяет, что все 50 UnitKind покрыты в placeholderSpecs.
    /// Не вызывается в продакшне — только контракт-чек для ревью.
    static func _debugAssertPlaceholderCoverage() {
        for kind in UnitKind.allCases {
            assert(placeholderSpecs[kind] != nil, "Missing placeholder spec for \(kind)")
        }
    }
    #endif

    // MARK: - Жилые (residential): лачуга → деревянный → каменный → многоэтажный → вилла

    // stage 1: лачуга — низкий куб, глина, соломенная крыша (h=14)
    // stage 2: деревянный дом — выше, тёмное дерево, окно (h=20)
    // stage 3: каменный дом — квадрат, тёплый камень, 2 окна (h=28)
    // stage 4: многоэтажный — узкий высокий, 2 ряда окон (h=38)
    // stage 5: вилла — широкая, балкон, орнамент (h=46)
    private static func makeResidentialStage(_ stage: Int) -> SKNode {
        let node = SKNode()
        switch stage {
        case 1:
            // Лачуга: пробуем растровый ассет, иначе процедурный куб
            if let sprite = loadBuildingSprite(named: "shack", targetWidth: 64, anchorY: 0.30) {
                node.addChild(sprite)
                break
            }
            let fp = CGSize(width: 30, height: 16)
            let h: CGFloat = 14
            let body = IsoBuilder.cube(
                footprint: fp, height: h,
                colors: .init(
                    top:    Palette.clay.lightened(by: 0.08),
                    left:   Palette.clay,
                    right:  Palette.clay.darkened(by: 0.18),
                    stroke: Palette.inkDark.withAlphaComponent(0.7)
                )
            )
            node.addChild(body)
            // Соломенная крыша
            let roof = IsoBuilder.pyramidRoof(
                footprint: fp, peak: 10,
                leftColor: Palette.ochre.darkened(by: 0.05),
                rightColor: Palette.ochre.darkened(by: 0.20),
                strokeColor: Palette.inkDark.withAlphaComponent(0.6)
            )
            roof.position = CGPoint(x: 0, y: h)
            node.addChild(roof)

        case 2:
            // Деревянный дом: тёмное дерево, окошко
            let fp = CGSize(width: 34, height: 18)
            let h: CGFloat = 20
            let body = IsoBuilder.cube(
                footprint: fp, height: h,
                colors: .init(
                    top:    Palette.warmBrown.lightened(by: 0.08),
                    left:   Palette.warmBrown,
                    right:  Palette.warmBrown.darkened(by: 0.22),
                    stroke: Palette.inkDark.withAlphaComponent(0.7)
                )
            )
            node.addChild(body)
            node.addChild(IsoBuilder.brickHatch(
                footprint: fp, height: h, rows: 3,
                color: Palette.inkDark.withAlphaComponent(0.22)
            ))
            // Остроконечная крыша
            let roof = IsoBuilder.pyramidRoof(
                footprint: fp, peak: 14,
                leftColor: Palette.smokeGrey.darkened(by: 0.05),
                rightColor: Palette.smokeGrey.darkened(by: 0.18),
                strokeColor: Palette.inkDark.withAlphaComponent(0.6)
            )
            roof.position = CGPoint(x: 0, y: h)
            node.addChild(roof)
            // Окошко
            let win = SKShapeNode(rect: CGRect(x: -2.5, y: 0, width: 5, height: 5))
            win.fillColor = Palette.skyNight.withAlphaComponent(0.80)
            win.strokeColor = Palette.inkDark.withAlphaComponent(0.5)
            win.lineWidth = 0.5
            win.position = CGPoint(x: 7, y: h * 0.4)
            node.addChild(win)

        case 3:
            // Каменный дом: тёплый камень, 2 окна, крыша
            let fp = CGSize(width: 38, height: 20)
            let h: CGFloat = 28
            let body = IsoBuilder.cube(
                footprint: fp, height: h,
                colors: .init(
                    top:    Palette.stone.lightened(by: 0.10),
                    left:   Palette.stone,
                    right:  Palette.stone.darkened(by: 0.20),
                    stroke: Palette.inkDark.withAlphaComponent(0.6)
                )
            )
            node.addChild(body)
            node.addChild(IsoBuilder.brickHatch(
                footprint: fp, height: h, rows: 4,
                color: Palette.inkDark.withAlphaComponent(0.20)
            ))
            let roof = IsoBuilder.pyramidRoof(
                footprint: fp, peak: 16,
                leftColor: Palette.clay,
                rightColor: Palette.clay.darkened(by: 0.18),
                strokeColor: Palette.inkDark.withAlphaComponent(0.6)
            )
            roof.position = CGPoint(x: 0, y: h)
            node.addChild(roof)
            for dx in [-8, 8] {
                let win = SKShapeNode(rect: CGRect(x: -2.5, y: 0, width: 5, height: 5))
                win.fillColor = Palette.skyNight.withAlphaComponent(0.82)
                win.strokeColor = Palette.inkDark.withAlphaComponent(0.5)
                win.lineWidth = 0.4
                win.position = CGPoint(x: CGFloat(dx), y: h * 0.4)
                node.addChild(win)
            }

        case 4:
            // Многоэтажный: узкий высокий, 2 ряда окон, плоская крыша
            let fp = CGSize(width: 32, height: 18)
            let h: CGFloat = 38
            let body = IsoBuilder.cube(
                footprint: fp, height: h,
                colors: .init(
                    top:    Palette.sandMid.lightened(by: 0.08),
                    left:   Palette.sandMid,
                    right:  Palette.sandMid.darkened(by: 0.20),
                    stroke: Palette.inkDark.withAlphaComponent(0.6)
                )
            )
            node.addChild(body)
            node.addChild(IsoBuilder.brickHatch(
                footprint: fp, height: h, rows: 6,
                color: Palette.inkDark.withAlphaComponent(0.18)
            ))
            // 2 ряда окон
            for row in [0.3, 0.6] {
                for dx in [-7, 0, 7] {
                    let win = SKShapeNode(rect: CGRect(x: -2, y: 0, width: 4, height: 4))
                    win.fillColor = Palette.skyNight.withAlphaComponent(0.85)
                    win.strokeColor = Palette.inkDark.withAlphaComponent(0.4)
                    win.lineWidth = 0.4
                    win.position = CGPoint(x: CGFloat(dx), y: h * row)
                    node.addChild(win)
                }
            }
            // Плоская крыша + парапет
            let topShade = IsoBuilder.groundTile(
                width: fp.width,
                height: fp.height,
                fillColor: Palette.stone.darkened(by: 0.15),
                strokeColor: Palette.inkDark
            )
            topShade.position = CGPoint(x: 0, y: h)
            node.addChild(topShade)

        default: // stage 5
            // Вилла: широкая, балкон, орнаментный фриз
            let fp = CGSize(width: 46, height: 24)
            let h: CGFloat = 46
            let body = IsoBuilder.cube(
                footprint: fp, height: h,
                colors: .init(
                    top:    Palette.parchment,
                    left:   Palette.parchment.darkened(by: 0.08),
                    right:  Palette.parchment.darkened(by: 0.22),
                    stroke: Palette.inkDark.withAlphaComponent(0.6)
                )
            )
            node.addChild(body)
            node.addChild(IsoBuilder.brickHatch(
                footprint: fp, height: h, rows: 6,
                color: Palette.inkDark.withAlphaComponent(0.15)
            ))
            // Остроконечная крыша
            let roof = IsoBuilder.pyramidRoof(
                footprint: fp, peak: 24,
                leftColor: Palette.clay.darkened(by: 0.05),
                rightColor: Palette.clay.darkened(by: 0.20),
                strokeColor: Palette.inkDark.withAlphaComponent(0.6)
            )
            roof.position = CGPoint(x: 0, y: h)
            node.addChild(roof)
            // Ряд окон + колоннки-балкон
            for dx in [-14, -5, 5, 14] {
                let win = SKShapeNode(rect: CGRect(x: -2.5, y: 0, width: 5, height: 6))
                win.fillColor = Palette.skyNight.withAlphaComponent(0.85)
                win.strokeColor = Palette.inkDark.withAlphaComponent(0.4)
                win.lineWidth = 0.4
                win.position = CGPoint(x: CGFloat(dx), y: h * 0.45)
                node.addChild(win)
            }
            // Фриз (декоративная полоса)
            let frieze = SKShapeNode(rect: CGRect(x: -fp.width / 2, y: 0, width: fp.width, height: 4))
            frieze.fillColor = Palette.ochre.withAlphaComponent(0.60)
            frieze.strokeColor = .clear
            frieze.position = CGPoint(x: 0, y: h * 0.30)
            node.addChild(frieze)
        }
        return node
    }

    // MARK: - Инфраструктура (infrastructure): примитив → досчатый → каменный → облагороженный → роскошный

    // stage 1: примитивный колодец/дорожка — пень/грунтовая яма (h=8)
    // stage 2: досчатый — деревянное строение, грубые балки (h=14)
    // stage 3: каменный — прочный куб, арка (h=20)
    // stage 4: облагороженный — отделка, декор (h=28)
    // stage 5: роскошный — арки, колонны, орнамент (h=36)
    private static func makeInfrastructureStage(_ stage: Int) -> SKNode {
        let node = SKNode()
        switch stage {
        case 1:
            // Примитив: низкий плоский объект (выкопанная яма / насыпь)
            let fp = CGSize(width: 28, height: 14)
            let h: CGFloat = 8
            let body = IsoBuilder.cube(
                footprint: fp, height: h,
                colors: .init(
                    top:    Palette.clay.darkened(by: 0.25),
                    left:   Palette.clay.darkened(by: 0.30),
                    right:  Palette.clay.darkened(by: 0.40),
                    stroke: Palette.inkDark.withAlphaComponent(0.7)
                )
            )
            node.addChild(body)

        case 2:
            // Досчатый: деревянные балки, грубая конструкция
            let fp = CGSize(width: 34, height: 18)
            let h: CGFloat = 14
            let body = IsoBuilder.cube(
                footprint: fp, height: h,
                colors: .init(
                    top:    Palette.warmBrown.darkened(by: 0.10),
                    left:   Palette.warmBrown.darkened(by: 0.12),
                    right:  Palette.warmBrown.darkened(by: 0.28),
                    stroke: Palette.inkDark.withAlphaComponent(0.7)
                )
            )
            node.addChild(body)
            node.addChild(IsoBuilder.brickHatch(
                footprint: fp, height: h, rows: 2,
                color: Palette.inkDark.withAlphaComponent(0.28)
            ))

        case 3:
            // Каменный: прочный куб
            let fp = CGSize(width: 38, height: 20)
            let h: CGFloat = 20
            let body = IsoBuilder.cube(
                footprint: fp, height: h,
                colors: .init(
                    top:    Palette.stone.lightened(by: 0.08),
                    left:   Palette.stone,
                    right:  Palette.stone.darkened(by: 0.22),
                    stroke: Palette.inkDark.withAlphaComponent(0.6)
                )
            )
            node.addChild(body)
            node.addChild(IsoBuilder.brickHatch(
                footprint: fp, height: h, rows: 3,
                color: Palette.inkDark.withAlphaComponent(0.20)
            ))
            // Простая арка (имитация)
            let arch = SKShapeNode(rect: CGRect(x: -4, y: 0, width: 8, height: 10))
            arch.fillColor = Palette.parchment.withAlphaComponent(0.70)
            arch.strokeColor = Palette.inkDark.withAlphaComponent(0.5)
            arch.lineWidth = 0.5
            arch.position = CGPoint(x: 0, y: h * 0.15)
            node.addChild(arch)

        case 4:
            // Облагороженный: отделочный куб с декором
            let fp = CGSize(width: 42, height: 22)
            let h: CGFloat = 28
            let body = IsoBuilder.cube(
                footprint: fp, height: h,
                colors: .init(
                    top:    Palette.sandLight.lightened(by: 0.05),
                    left:   Palette.sandLight,
                    right:  Palette.sandLight.darkened(by: 0.18),
                    stroke: Palette.inkDark.withAlphaComponent(0.6)
                )
            )
            node.addChild(body)
            node.addChild(IsoBuilder.brickHatch(
                footprint: fp, height: h, rows: 4,
                color: Palette.inkDark.withAlphaComponent(0.15)
            ))
            // Декоративные пилястры (вертикальные полоски)
            for dx in [-14, 14] {
                let pilaster = SKShapeNode(rect: CGRect(x: -1.5, y: 0, width: 3, height: h * 0.8))
                pilaster.fillColor = Palette.parchment.withAlphaComponent(0.55)
                pilaster.strokeColor = .clear
                pilaster.position = CGPoint(x: CGFloat(dx), y: h * 0.1)
                node.addChild(pilaster)
            }

        default: // stage 5
            // Роскошный: монументальный, арки, колонны
            let fp = CGSize(width: 48, height: 26)
            let h: CGFloat = 36
            let body = IsoBuilder.cube(
                footprint: fp, height: h,
                colors: .init(
                    top:    Palette.parchment.lightened(by: 0.05),
                    left:   Palette.parchment.darkened(by: 0.08),
                    right:  Palette.parchment.darkened(by: 0.20),
                    stroke: Palette.inkDark.withAlphaComponent(0.6)
                )
            )
            node.addChild(body)
            node.addChild(IsoBuilder.brickHatch(
                footprint: fp, height: h, rows: 5,
                color: Palette.inkDark.withAlphaComponent(0.12)
            ))
            // Колонны
            for dx in [-16, -8, 0, 8, 16] {
                let col = IsoBuilder.cube(
                    footprint: CGSize(width: 3, height: 2),
                    height: 18,
                    colors: .init(
                        top:    Palette.parchment,
                        left:   Palette.parchment.darkened(by: 0.08),
                        right:  Palette.parchment.darkened(by: 0.18),
                        stroke: Palette.inkDark.withAlphaComponent(0.5)
                    )
                )
                col.position = CGPoint(x: CGFloat(dx), y: 4)
                node.addChild(col)
            }
        }
        return node
    }

    // MARK: - Производство (production): грубый → кустарный → ремесленный → цеховой → мануфактура

    // stage 1: грубый очаг/яма (h=10)
    // stage 2: кустарная мастерская (h=16)
    // stage 3: ремесленная печь/кузница (h=22)
    // stage 4: цеховой комплекс (h=30)
    // stage 5: мануфактура (h=38)
    private static func makeProductionStage(_ stage: Int) -> SKNode {
        let node = SKNode()
        switch stage {
        case 1:
            // Грубый очаг: приземистый тёмный куб
            let fp = CGSize(width: 26, height: 14)
            let h: CGFloat = 10
            let body = IsoBuilder.cube(
                footprint: fp, height: h,
                colors: .init(
                    top:    Palette.clay.darkened(by: 0.20),
                    left:   Palette.clay.darkened(by: 0.30),
                    right:  Palette.clay.darkened(by: 0.42),
                    stroke: Palette.inkDark
                )
            )
            node.addChild(body)
            // Кучка угля
            let coal = SKShapeNode(circleOfRadius: 3)
            coal.fillColor = Palette.inkDark.withAlphaComponent(0.70)
            coal.strokeColor = .clear
            coal.position = CGPoint(x: 0, y: h + 2)
            node.addChild(coal)

        case 2:
            // Кустарная мастерская: охра, грубые балки
            let fp = CGSize(width: 32, height: 18)
            let h: CGFloat = 16
            let body = IsoBuilder.cube(
                footprint: fp, height: h,
                colors: .init(
                    top:    Palette.ochre.lightened(by: 0.05),
                    left:   Palette.ochre,
                    right:  Palette.ochre.darkened(by: 0.20),
                    stroke: Palette.inkDark.withAlphaComponent(0.7)
                )
            )
            node.addChild(body)
            node.addChild(IsoBuilder.brickHatch(
                footprint: fp, height: h, rows: 2,
                color: Palette.inkDark.withAlphaComponent(0.25)
            ))
            // Дымок (маленькая труба)
            let chimney = IsoBuilder.cube(
                footprint: CGSize(width: 4, height: 3), height: 5,
                colors: .init(
                    top:    Palette.smokeGrey.darkened(by: 0.15),
                    left:   Palette.smokeGrey.darkened(by: 0.22),
                    right:  Palette.smokeGrey.darkened(by: 0.32),
                    stroke: Palette.inkDark.withAlphaComponent(0.6)
                )
            )
            chimney.position = CGPoint(x: -6, y: h + 3)
            node.addChild(chimney)

        case 3:
            // Ремесленная кузница: тёмный куб + крупная труба
            let fp = CGSize(width: 38, height: 20)
            let h: CGFloat = 22
            let body = IsoBuilder.cube(
                footprint: fp, height: h,
                colors: .init(
                    top:    Palette.warmBrown.lightened(by: 0.05),
                    left:   Palette.warmBrown,
                    right:  Palette.warmBrown.darkened(by: 0.25),
                    stroke: Palette.inkDark.withAlphaComponent(0.7)
                )
            )
            node.addChild(body)
            node.addChild(IsoBuilder.brickHatch(
                footprint: fp, height: h, rows: 3,
                color: Palette.inkDark.withAlphaComponent(0.25)
            ))
            let roof = IsoBuilder.pyramidRoof(
                footprint: fp, peak: 12,
                leftColor: Palette.smokeGrey,
                rightColor: Palette.smokeGrey.darkened(by: 0.18),
                strokeColor: Palette.inkDark.withAlphaComponent(0.6)
            )
            roof.position = CGPoint(x: 0, y: h)
            node.addChild(roof)
            let chimney = IsoBuilder.cube(
                footprint: CGSize(width: 6, height: 4), height: 10,
                colors: .init(
                    top:    Palette.smokeGrey.darkened(by: 0.18),
                    left:   Palette.smokeGrey.darkened(by: 0.28),
                    right:  Palette.smokeGrey.darkened(by: 0.40),
                    stroke: Palette.inkDark.withAlphaComponent(0.7)
                )
            )
            chimney.position = CGPoint(x: -8, y: h + 6)
            node.addChild(chimney)

        case 4:
            // Цеховой комплекс: широкий, плоская крыша, 2 трубы
            let fp = CGSize(width: 46, height: 24)
            let h: CGFloat = 30
            let body = IsoBuilder.cube(
                footprint: fp, height: h,
                colors: .init(
                    top:    Palette.sandMid.darkened(by: 0.08),
                    left:   Palette.sandMid.darkened(by: 0.10),
                    right:  Palette.sandMid.darkened(by: 0.25),
                    stroke: Palette.inkDark.withAlphaComponent(0.6)
                )
            )
            node.addChild(body)
            node.addChild(IsoBuilder.brickHatch(
                footprint: fp, height: h, rows: 4,
                color: Palette.inkDark.withAlphaComponent(0.20)
            ))
            let topShade = IsoBuilder.groundTile(
                width: fp.width,
                height: fp.height,
                fillColor: Palette.stone.darkened(by: 0.18),
                strokeColor: Palette.inkDark
            )
            topShade.position = CGPoint(x: 0, y: h)
            node.addChild(topShade)
            for dx in [-10, 8] {
                let ch = IsoBuilder.cube(
                    footprint: CGSize(width: 5, height: 3), height: 8,
                    colors: .init(
                        top:    Palette.smokeGrey.darkened(by: 0.20),
                        left:   Palette.smokeGrey.darkened(by: 0.30),
                        right:  Palette.smokeGrey.darkened(by: 0.42),
                        stroke: Palette.inkDark.withAlphaComponent(0.7)
                    )
                )
                ch.position = CGPoint(x: CGFloat(dx), y: h + 4)
                node.addChild(ch)
            }

        default: // stage 5
            // Мануфактура: монументальный склад, 3 трубы, штабели
            let fp = CGSize(width: 52, height: 28)
            let h: CGFloat = 38
            let body = IsoBuilder.cube(
                footprint: fp, height: h,
                colors: .init(
                    top:    Palette.sandLight.darkened(by: 0.05),
                    left:   Palette.sandLight.darkened(by: 0.08),
                    right:  Palette.sandLight.darkened(by: 0.22),
                    stroke: Palette.inkDark.withAlphaComponent(0.6)
                )
            )
            node.addChild(body)
            node.addChild(IsoBuilder.brickHatch(
                footprint: fp, height: h, rows: 5,
                color: Palette.inkDark.withAlphaComponent(0.15)
            ))
            let topShade = IsoBuilder.groundTile(
                width: fp.width,
                height: fp.height,
                fillColor: Palette.stone.darkened(by: 0.22),
                strokeColor: Palette.inkDark
            )
            topShade.position = CGPoint(x: 0, y: h)
            node.addChild(topShade)
            for dx in [-16, -4, 10] {
                let ch = IsoBuilder.cube(
                    footprint: CGSize(width: 6, height: 4), height: 12,
                    colors: .init(
                        top:    Palette.smokeGrey.darkened(by: 0.20),
                        left:   Palette.smokeGrey.darkened(by: 0.30),
                        right:  Palette.smokeGrey.darkened(by: 0.45),
                        stroke: Palette.inkDark.withAlphaComponent(0.7)
                    )
                )
                ch.position = CGPoint(x: CGFloat(dx), y: h + 4)
                node.addChild(ch)
            }
            // Штабели товаров
            for offset in stride(from: -14, through: 14, by: 10) {
                let stack = IsoBuilder.cube(
                    footprint: CGSize(width: 4, height: 3), height: 5,
                    colors: .init(
                        top:    Palette.ochre.darkened(by: 0.18),
                        left:   Palette.ochre.darkened(by: 0.25),
                        right:  Palette.ochre.darkened(by: 0.38),
                        stroke: Palette.inkDark.withAlphaComponent(0.6)
                    )
                )
                stack.position = CGPoint(x: CGFloat(offset), y: h + 6)
                node.addChild(stack)
            }
        }
        return node
    }

    // MARK: - Социальные (social): шатёр → навес → павильон → колоннада → храм/форум

    // stage 1: шатёр — простой тент (h=10)
    // stage 2: деревянный навес — стойки, полог (h=14)
    // stage 3: павильон — каменный, колонны (h=20)
    // stage 4: колоннада — торжественная (h=28)
    // stage 5: храм/форум — монументальный (h=38)
    private static func makeSocialStage(_ stage: Int) -> SKNode {
        let node = SKNode()
        switch stage {
        case 1:
            // Шатёр: крошечный тент-пирамида
            let fp = CGSize(width: 28, height: 14)
            let base = IsoBuilder.cube(
                footprint: fp, height: 6,
                colors: .init(
                    top:    Palette.sandLight,
                    left:   Palette.sandMid,
                    right:  Palette.sandMid.darkened(by: 0.18),
                    stroke: Palette.inkDark.withAlphaComponent(0.6)
                )
            )
            node.addChild(base)
            let tent = IsoBuilder.pyramidRoof(
                footprint: fp, peak: 12,
                leftColor: Palette.skyDusk.lightened(by: 0.10),
                rightColor: Palette.skyDusk.darkened(by: 0.12),
                strokeColor: Palette.inkDark.withAlphaComponent(0.6)
            )
            tent.position = CGPoint(x: 0, y: 6)
            node.addChild(tent)

        case 2:
            // Деревянный навес: стойки + брезент
            let fp = CGSize(width: 36, height: 18)
            let base = IsoBuilder.cube(
                footprint: fp, height: 6,
                colors: .init(
                    top:    Palette.sandLight,
                    left:   Palette.sandMid,
                    right:  Palette.sandMid.darkened(by: 0.18),
                    stroke: Palette.inkDark.withAlphaComponent(0.6)
                )
            )
            node.addChild(base)
            // Стойки
            for dx in [-14, 0, 14] {
                let post = SKShapeNode(rect: CGRect(x: -1, y: 0, width: 2, height: 12))
                post.fillColor = Palette.warmBrown
                post.strokeColor = Palette.inkDark.withAlphaComponent(0.6)
                post.lineWidth = 0.5
                post.position = CGPoint(x: CGFloat(dx), y: 6)
                node.addChild(post)
            }
            let canopy = IsoBuilder.pyramidRoof(
                footprint: fp, peak: 10,
                leftColor: Palette.ochre.lightened(by: 0.08),
                rightColor: Palette.ochre.darkened(by: 0.15),
                strokeColor: Palette.inkDark.withAlphaComponent(0.6)
            )
            canopy.position = CGPoint(x: 0, y: 18)
            node.addChild(canopy)

        case 3:
            // Павильон: каменный, 2 колонны
            let fp = CGSize(width: 42, height: 22)
            let base = IsoBuilder.cube(
                footprint: fp, height: 6,
                colors: .init(
                    top:    Palette.parchment,
                    left:   Palette.stone,
                    right:  Palette.stone.darkened(by: 0.18),
                    stroke: Palette.inkDark.withAlphaComponent(0.6)
                )
            )
            node.addChild(base)
            for dx in [-12, 12] {
                let col = IsoBuilder.cube(
                    footprint: CGSize(width: 4, height: 3), height: 16,
                    colors: .init(
                        top:    Palette.parchment,
                        left:   Palette.parchment.darkened(by: 0.08),
                        right:  Palette.parchment.darkened(by: 0.20),
                        stroke: Palette.inkDark.withAlphaComponent(0.6)
                    )
                )
                col.position = CGPoint(x: CGFloat(dx), y: 6)
                node.addChild(col)
            }
            let canopy = IsoBuilder.pyramidRoof(
                footprint: fp, peak: 14,
                leftColor: Palette.skyDusk,
                rightColor: Palette.skyDusk.darkened(by: 0.15),
                strokeColor: Palette.inkDark.withAlphaComponent(0.6)
            )
            canopy.position = CGPoint(x: 0, y: 22)
            node.addChild(canopy)

        case 4:
            // Колоннада: торжественный ряд колонн
            let fp = CGSize(width: 50, height: 26)
            let plat = IsoBuilder.cube(
                footprint: fp, height: 6,
                colors: .init(
                    top:    Palette.parchment,
                    left:   Palette.stone,
                    right:  Palette.stone.darkened(by: 0.18),
                    stroke: Palette.inkDark.withAlphaComponent(0.6)
                )
            )
            node.addChild(plat)
            for dx in stride(from: -18, through: 18, by: 9) {
                let col = IsoBuilder.cube(
                    footprint: CGSize(width: 4, height: 3), height: 20,
                    colors: .init(
                        top:    Palette.parchment,
                        left:   Palette.parchment.darkened(by: 0.08),
                        right:  Palette.parchment.darkened(by: 0.22),
                        stroke: Palette.inkDark.withAlphaComponent(0.5)
                    )
                )
                col.position = CGPoint(x: CGFloat(dx), y: 6)
                node.addChild(col)
            }
            // Горизонтальный антаблемент
            let entab = IsoBuilder.groundTile(
                width: fp.width,
                height: fp.height,
                fillColor: Palette.sandLight.darkened(by: 0.08),
                strokeColor: Palette.inkDark.withAlphaComponent(0.5)
            )
            entab.position = CGPoint(x: 0, y: 26)
            node.addChild(entab)

        default: // stage 5
            // Храм/форум: монументальный, высокий подиум, ряд колонн + треугольный фронтон
            let fp = CGSize(width: 56, height: 30)
            let podium = IsoBuilder.cube(
                footprint: fp, height: 8,
                colors: .init(
                    top:    Palette.parchment,
                    left:   Palette.parchment.darkened(by: 0.10),
                    right:  Palette.parchment.darkened(by: 0.25),
                    stroke: Palette.inkDark.withAlphaComponent(0.7)
                )
            )
            node.addChild(podium)
            let inner = CGSize(width: 40, height: 22)
            let body = IsoBuilder.cube(
                footprint: inner, height: 22,
                colors: .init(
                    top:    Palette.parchment,
                    left:   Palette.parchment.darkened(by: 0.10),
                    right:  Palette.parchment.darkened(by: 0.25),
                    stroke: Palette.inkDark.withAlphaComponent(0.6)
                )
            )
            body.position = CGPoint(x: 0, y: 8)
            node.addChild(body)
            // Колонны по фасаду
            for dx in stride(from: -18, through: 18, by: 9) {
                let col = IsoBuilder.cube(
                    footprint: CGSize(width: 4, height: 3), height: 18,
                    colors: .init(
                        top:    Palette.parchment,
                        left:   Palette.parchment.darkened(by: 0.06),
                        right:  Palette.parchment.darkened(by: 0.16),
                        stroke: Palette.inkDark.withAlphaComponent(0.5)
                    )
                )
                col.position = CGPoint(x: CGFloat(dx), y: 8)
                node.addChild(col)
            }
            // Фронтон (пирамидальный)
            let pediment = IsoBuilder.pyramidRoof(
                footprint: inner, peak: 18,
                leftColor: Palette.ochre,
                rightColor: Palette.ochre.darkened(by: 0.20),
                strokeColor: Palette.inkDark.withAlphaComponent(0.6)
            )
            pediment.position = CGPoint(x: 0, y: 30)
            node.addChild(pediment)
        }
        return node
    }

    static func makeNode(unit: UnitState) -> SKNode {
        let container = SKNode()

        // Тайл-земля под юнитом
        let groundColor = groundColor(for: unit.kind)
        let ground = IsoBuilder.groundTile(
            width: tileWidth - 2,
            height: tileHeight - 1,
            fillColor: groundColor,
            strokeColor: SKColor.black.withAlphaComponent(0.25)
        )
        ground.zPosition = -1
        container.addChild(ground)

        // 3. Само здание (или плоский объект)
        switch unit.kind {
        case .road:
            container.addChild(makeRoad())
        case .well:
            container.addChild(makeWell())
        case .raw:
            container.addChild(makeRawPit())
        case .shack:
            container.addChild(makeShack(tier: unit.tier))
        case .house:
            container.addChild(makeHouse(tier: unit.tier))
        case .villa:
            container.addChild(makeVilla(tier: unit.tier))
        case .warehouse:
            container.addChild(makeWarehouse(tier: unit.tier))
        case .workshop:
            container.addChild(makeWorkshop(tier: unit.tier))
        case .market:
            container.addChild(makeMarket(tier: unit.tier))
        case .forum:
            container.addChild(makeForum(tier: unit.tier))
        case .temple:
            container.addChild(makeTemple(tier: unit.tier))
        case .obelisk:
            container.addChild(makeObelisk(tier: unit.tier))
        default:
            // TODO TASK-032: placeholder-спрайт для новых 39 юнитов; финальные PNG — TASK-040
            container.addChild(makePlaceholder(for: unit))
        }

        return container
    }

    // MARK: - Тайл-земля под юнитом

    private static func groundColor(for kind: UnitKind) -> SKColor {
        switch kind {
        case .raw:           return Palette.clay.darkened(by: 0.15)        // вспаханное
        case .road:          return Palette.sandMid
        case .well:          return Palette.sandLight
        case .market, .forum: return Palette.sandLight.darkened(by: 0.05)  // мощёная площадь
        case .temple, .obelisk: return Palette.parchment                   // светлый камень
        default:             return Palette.sandLight
        }
    }

    // MARK: - Placeholder для новых юнитов (TASK-032 заменит на финальный PNG-спрайт)

    /// Однотонный куб с буквой инициала label-а.
    /// Используется для всех новых юнитов F-16 до появления арт-ассетов.
    private static func makePlaceholder(for unit: UnitState) -> SKNode {
        let node = SKNode()
        let fp = CGSize(width: 30, height: 16)
        let h: CGFloat = 18
        let body = IsoBuilder.cube(
            footprint: fp, height: h,
            colors: .init(
                top:    Palette.sandLight,
                left:   Palette.sandMid,
                right:  Palette.sandMid.darkened(by: 0.18),
                stroke: Palette.inkDark.withAlphaComponent(0.5)
            )
        )
        node.addChild(body)
        // Буква первого символа label-а для идентификации типа
        let initial = String(unit.kind.label.prefix(1))
        let letter = SKLabelNode(text: initial)
        letter.fontName = "Helvetica"
        letter.fontSize = 10
        letter.fontColor = Palette.inkDark.withAlphaComponent(0.7)
        letter.horizontalAlignmentMode = .center
        letter.verticalAlignmentMode = .center
        letter.position = CGPoint(x: 0, y: h * 0.5)
        node.addChild(letter)
        return node
    }

    // MARK: - Жилые

    private static func makeShack(tier: Int) -> SKNode {
        let node = SKNode()
        let footprint = CGSize(width: 36, height: 18)
        let bodyHeight: CGFloat = 14
        let body = IsoBuilder.cube(
            footprint: footprint, height: bodyHeight,
            colors: .init(
                top:    Palette.clay.lightened(by: 0.05),
                left:   Palette.clay,
                right:  Palette.clay.darkened(by: 0.15),
                stroke: Palette.inkDark.withAlphaComponent(0.6)
            )
        )
        node.addChild(body)
        node.addChild(IsoBuilder.brickHatch(
            footprint: footprint, height: bodyHeight, rows: 2,
            color: Palette.inkDark.withAlphaComponent(0.30)
        ))
        let roof = IsoBuilder.pyramidRoof(
            footprint: footprint, peak: 22,
            leftColor: Palette.smokeGrey.lightened(by: 0.05),
            rightColor: Palette.smokeGrey.darkened(by: 0.10),
            strokeColor: Palette.inkDark.withAlphaComponent(0.6)
        )
        roof.position = CGPoint(x: 0, y: bodyHeight)
        node.addChild(roof)
        return node
    }

    private static func makeHouse(tier: Int) -> SKNode {
        let node = SKNode()
        let footprint = CGSize(width: 40, height: 20)
        let height: CGFloat = 18 + CGFloat(tier) * 2
        let body = IsoBuilder.cube(
            footprint: footprint, height: height,
            colors: .init(
                top:    Palette.sandMid.lightened(by: 0.10),
                left:   Palette.sandMid,
                right:  Palette.sandMid.darkened(by: 0.15),
                stroke: Palette.inkDark.withAlphaComponent(0.6)
            )
        )
        node.addChild(body)
        node.addChild(IsoBuilder.brickHatch(
            footprint: footprint, height: height, rows: 3,
            color: Palette.inkDark.withAlphaComponent(0.28)
        ))
        let roof = IsoBuilder.pyramidRoof(
            footprint: footprint, peak: 18,
            leftColor: Palette.clay,
            rightColor: Palette.clay.darkened(by: 0.15),
            strokeColor: Palette.inkDark.withAlphaComponent(0.6)
        )
        roof.position = CGPoint(x: 0, y: height)
        node.addChild(roof)

        // Окошко на правой грани
        let window = SKShapeNode(rect: CGRect(x: -3, y: 0, width: 6, height: 5))
        window.fillColor = Palette.skyNight.withAlphaComponent(0.85)
        window.strokeColor = Palette.inkDark.withAlphaComponent(0.6)
        window.lineWidth = 0.5
        window.position = CGPoint(x: 8, y: height * 0.4)
        node.addChild(window)

        return node
    }

    private static func makeVilla(tier: Int) -> SKNode {
        let node = SKNode()
        let footprint = CGSize(width: 46, height: 24)
        let height: CGFloat = 22 + CGFloat(tier) * 2
        let body = IsoBuilder.cube(
            footprint: footprint, height: height,
            colors: .init(
                top:    Palette.parchment,
                left:   Palette.parchment.darkened(by: 0.10),
                right:  Palette.parchment.darkened(by: 0.25),
                stroke: Palette.inkDark.withAlphaComponent(0.6)
            )
        )
        node.addChild(body)
        node.addChild(IsoBuilder.brickHatch(
            footprint: footprint, height: height, rows: 4,
            color: Palette.inkDark.withAlphaComponent(0.22)
        ))
        let roof = IsoBuilder.pyramidRoof(
            footprint: footprint, peak: 24,
            leftColor: Palette.clay.darkened(by: 0.05),
            rightColor: Palette.clay.darkened(by: 0.20),
            strokeColor: Palette.inkDark.withAlphaComponent(0.6)
        )
        roof.position = CGPoint(x: 0, y: height)
        node.addChild(roof)
        // Окошки
        for dx in [-12, 0, 12] {
            let window = SKShapeNode(rect: CGRect(x: -2, y: 0, width: 4, height: 4))
            window.fillColor = Palette.skyNight.withAlphaComponent(0.85)
            window.strokeColor = Palette.inkDark.withAlphaComponent(0.5)
            window.lineWidth = 0.4
            window.position = CGPoint(x: CGFloat(dx), y: height * 0.5)
            node.addChild(window)
        }
        return node
    }

    // MARK: - Инфраструктура

    private static func makeWell() -> SKNode {
        let node = SKNode()
        let stone = SKShapeNode(circleOfRadius: 6)
        stone.fillColor = Palette.stone
        stone.strokeColor = Palette.inkDark
        stone.lineWidth = 1
        stone.position = CGPoint(x: 0, y: 2)
        node.addChild(stone)
        let water = SKShapeNode(circleOfRadius: 4)
        water.fillColor = Palette.skyNight
        water.strokeColor = .clear
        water.position = CGPoint(x: 0, y: 3)
        node.addChild(water)
        return node
    }

    private static func makeRoad() -> SKNode {
        let node = SKNode()
        let path = IsoBuilder.groundTile(
            width: tileWidth - 6,
            height: tileHeight - 4,
            fillColor: Palette.sandMid.darkened(by: 0.08),
            strokeColor: Palette.inkDark.withAlphaComponent(0.3)
        )
        path.position = CGPoint(x: 0, y: 1)
        node.addChild(path)
        return node
    }

    /// Публичная фабрика визуала дорожной клетки — используется и для road-юнитов
    /// квартала, и для клеток магистрали в `GameScene.drawRoadCells`. Возвращает
    /// контейнер с тайлом-землёй (sandMid) и дорожным пятном поверх — таким же,
    /// каким рендерится UnitKind.road.
    static func makeRoadCellNode() -> SKNode {
        let container = SKNode()
        let ground = IsoBuilder.groundTile(
            width: tileWidth - 2,
            height: tileHeight - 1,
            fillColor: Palette.sandMid,
            strokeColor: SKColor.black.withAlphaComponent(0.25)
        )
        ground.zPosition = -1
        container.addChild(ground)
        container.addChild(makeRoad())
        return container
    }

    private static func makeRawPit() -> SKNode {
        let node = SKNode()
        let pit = IsoBuilder.groundTile(
            width: tileWidth - 12,
            height: tileHeight - 8,
            fillColor: Palette.clay.darkened(by: 0.3),
            strokeColor: Palette.inkDark
        )
        pit.position = CGPoint(x: 0, y: 1)
        node.addChild(pit)
        // Кучки сырья
        for i in 0..<3 {
            let dot = SKShapeNode(circleOfRadius: 2)
            dot.fillColor = Palette.ochre.darkened(by: 0.2)
            dot.strokeColor = Palette.inkDark
            dot.lineWidth = 0.5
            dot.position = CGPoint(x: CGFloat(i - 1) * 6, y: 3)
            node.addChild(dot)
        }
        return node
    }

    // MARK: - Производство

    private static func makeWarehouse(tier: Int) -> SKNode {
        let node = SKNode()
        let footprint = CGSize(width: 44, height: 22)
        let height: CGFloat = 16 + CGFloat(tier) * 2
        let body = IsoBuilder.cube(
            footprint: footprint, height: height,
            colors: .init(
                top:    Palette.sandLight,
                left:   Palette.sandMid,
                right:  Palette.sandMid.darkened(by: 0.18),
                stroke: Palette.inkDark.withAlphaComponent(0.6)
            )
        )
        node.addChild(body)
        node.addChild(IsoBuilder.brickHatch(
            footprint: footprint, height: height, rows: 3,
            color: Palette.inkDark.withAlphaComponent(0.25)
        ))
        // Плоская крыша
        let topShade = IsoBuilder.groundTile(
            width: footprint.width,
            height: footprint.height,
            fillColor: Palette.smokeGrey.darkened(by: 0.20),
            strokeColor: Palette.inkDark
        )
        topShade.position = CGPoint(x: 0, y: height)
        node.addChild(topShade)

        // Декоративные штабели товаров (амфоры/мешки) для tier >= 1
        if tier >= 1 {
            for offset in stride(from: -10, through: 10, by: 8) {
                let stack = IsoBuilder.cube(
                    footprint: CGSize(width: 4, height: 3),
                    height: 5,
                    colors: .init(
                        top: Palette.ochre.lightened(by: 0.05).darkened(by: 0.20),
                        left: Palette.ochre.darkened(by: 0.20),
                        right: Palette.ochre.darkened(by: 0.35),
                        stroke: Palette.inkDark.withAlphaComponent(0.6)
                    )
                )
                stack.position = CGPoint(x: CGFloat(offset), y: height + 3)
                node.addChild(stack)
            }
        }

        return node
    }

    private static func makeWorkshop(tier: Int) -> SKNode {
        let node = SKNode()
        let footprint = CGSize(width: 38, height: 20)
        let height: CGFloat = 16 + CGFloat(tier) * 2
        let body = IsoBuilder.cube(
            footprint: footprint, height: height,
            colors: .init(
                top:    Palette.ochre.lightened(by: 0.10),
                left:   Palette.ochre,
                right:  Palette.ochre.darkened(by: 0.18),
                stroke: Palette.inkDark.withAlphaComponent(0.6)
            )
        )
        node.addChild(body)
        node.addChild(IsoBuilder.brickHatch(
            footprint: footprint, height: height, rows: 3,
            color: Palette.inkDark.withAlphaComponent(0.30)
        ))
        let roof = IsoBuilder.pyramidRoof(
            footprint: footprint, peak: 12,
            leftColor: Palette.smokeGrey.lightened(by: 0.05),
            rightColor: Palette.smokeGrey.darkened(by: 0.15),
            strokeColor: Palette.inkDark.withAlphaComponent(0.6)
        )
        roof.position = CGPoint(x: 0, y: height)
        node.addChild(roof)
        // Труба
        let chimney = IsoBuilder.cube(
            footprint: CGSize(width: 6, height: 4),
            height: 8,
            colors: .init(
                top:    Palette.smokeGrey.darkened(by: 0.2),
                left:   Palette.smokeGrey.darkened(by: 0.3),
                right:  Palette.smokeGrey.darkened(by: 0.4),
                stroke: Palette.inkDark.withAlphaComponent(0.7)
            )
        )
        chimney.position = CGPoint(x: -6, y: height + 6)
        node.addChild(chimney)
        return node
    }

    // MARK: - Социальные

    private static func makeMarket(tier: Int) -> SKNode {
        let node = SKNode()
        let footprint = CGSize(width: 44, height: 22)
        let height: CGFloat = 6
        let base = IsoBuilder.cube(
            footprint: footprint, height: height,
            colors: .init(
                top:    Palette.sandLight,
                left:   Palette.sandMid,
                right:  Palette.sandMid.darkened(by: 0.18),
                stroke: Palette.inkDark.withAlphaComponent(0.6)
            )
        )
        node.addChild(base)
        // Полосатый навес-тент
        let canopy = IsoBuilder.pyramidRoof(
            footprint: footprint, peak: 16,
            leftColor: Palette.skyDusk,
            rightColor: Palette.skyDusk.darkened(by: 0.15),
            strokeColor: Palette.inkDark.withAlphaComponent(0.7)
        )
        canopy.position = CGPoint(x: 0, y: height + 6)
        node.addChild(canopy)
        // Колонны
        for x in stride(from: -16, through: 16, by: 8) {
            let col = SKShapeNode(rect: CGRect(x: -1, y: 0, width: 2, height: 10))
            col.fillColor = Palette.parchment
            col.strokeColor = Palette.inkDark.withAlphaComponent(0.6)
            col.lineWidth = 0.5
            col.position = CGPoint(x: CGFloat(x), y: height)
            node.addChild(col)
        }
        return node
    }

    private static func makeForum(tier: Int) -> SKNode {
        let node = SKNode()
        let footprint = CGSize(width: 48, height: 24)
        let plat = IsoBuilder.cube(
            footprint: footprint, height: 6,
            colors: .init(
                top:    Palette.parchment,
                left:   Palette.stone,
                right:  Palette.stone.darkened(by: 0.18),
                stroke: Palette.inkDark.withAlphaComponent(0.6)
            )
        )
        node.addChild(plat)
        // Ряд колонн
        for x in stride(from: -18, through: 18, by: 9) {
            let col = IsoBuilder.cube(
                footprint: CGSize(width: 4, height: 3),
                height: 14,
                colors: .init(
                    top:    Palette.parchment,
                    left:   Palette.parchment.darkened(by: 0.10),
                    right:  Palette.parchment.darkened(by: 0.22),
                    stroke: Palette.inkDark.withAlphaComponent(0.6)
                )
            )
            col.position = CGPoint(x: CGFloat(x), y: 6)
            node.addChild(col)
        }
        return node
    }

    private static func makeTemple(tier: Int) -> SKNode {
        let node = SKNode()
        let footprint = CGSize(width: 44, height: 24)
        let plat = IsoBuilder.cube(
            footprint: footprint, height: 6,
            colors: .init(
                top:    Palette.parchment,
                left:   Palette.parchment.darkened(by: 0.10),
                right:  Palette.parchment.darkened(by: 0.25),
                stroke: Palette.inkDark.withAlphaComponent(0.7)
            )
        )
        node.addChild(plat)
        let inner = CGSize(width: 30, height: 16)
        let body = IsoBuilder.cube(
            footprint: inner, height: 22,
            colors: .init(
                top:    Palette.parchment,
                left:   Palette.parchment.darkened(by: 0.12),
                right:  Palette.parchment.darkened(by: 0.28),
                stroke: Palette.inkDark.withAlphaComponent(0.7)
            )
        )
        body.position = CGPoint(x: 0, y: 6)
        node.addChild(body)
        let roof = IsoBuilder.pyramidRoof(
            footprint: inner, peak: 20,
            leftColor: Palette.ochre,
            rightColor: Palette.ochre.darkened(by: 0.20),
            strokeColor: Palette.inkDark.withAlphaComponent(0.7)
        )
        roof.position = CGPoint(x: 0, y: 6 + 22)
        node.addChild(roof)
        return node
    }

    private static func makeObelisk(tier: Int) -> SKNode {
        let node = SKNode()
        // База
        let base = IsoBuilder.cube(
            footprint: CGSize(width: 22, height: 12),
            height: 6,
            colors: .init(
                top:    Palette.stone.lightened(by: 0.10),
                left:   Palette.stone,
                right:  Palette.stone.darkened(by: 0.18),
                stroke: Palette.inkDark
            )
        )
        node.addChild(base)
        // Шпиль (узкий куб + треугольная вершина)
        let column = IsoBuilder.cube(
            footprint: CGSize(width: 8, height: 4),
            height: 36,
            colors: .init(
                top:    Palette.sandMid,
                left:   Palette.sandMid.darkened(by: 0.10),
                right:  Palette.sandMid.darkened(by: 0.22),
                stroke: Palette.inkDark
            )
        )
        column.position = CGPoint(x: 0, y: 6)
        node.addChild(column)
        let cap = IsoBuilder.pyramidRoof(
            footprint: CGSize(width: 8, height: 4),
            peak: 8,
            leftColor: Palette.ochre,
            rightColor: Palette.ochre.darkened(by: 0.20),
            strokeColor: Palette.inkDark
        )
        cap.position = CGPoint(x: 0, y: 6 + 36)
        node.addChild(cap)
        return node
    }

    // MARK: - Руины

    internal static func makeRuin(originalKind: UnitKind) -> SKNode {
        let node = SKNode()

        // Используем детерминированные значения от hashValue
        let h = abs(originalKind.hashValue)

        // Для дорог - плоский слой обломков
        if originalKind == .road {
            let strip = IsoBuilder.groundTile(
                width: tileWidth - 8,
                height: 8,
                fillColor: Palette.stone.darkened(by: 0.20),
                strokeColor: Palette.inkDark
            )
            node.addChild(strip)
            return node
        }

        // Для остальных юнитов: 2-3 коротких куба + трава + трещина
        let chunks = 2 + (h % 2)  // 2 или 3 куба
        let offsets: [(CGFloat, CGFloat)] = [(-8, 4), (6, -2), (0, 6)]

        for i in 0..<chunks {
            if i >= offsets.count { break }
            let offset = offsets[i]
            let chunkHeight = CGFloat(4 + (h % 5))  // Высота 4-8 pt, детерминирована

            let chunk = IsoBuilder.cube(
                footprint: CGSize(width: 8, height: 6),
                height: chunkHeight,
                colors: .init(
                    top: Palette.stone.lightened(by: 0.05).darkened(by: 0.30),
                    left: Palette.stone.darkened(by: 0.30),
                    right: Palette.stone.darkened(by: 0.45),
                    stroke: Palette.inkDark
                )
            )
            chunk.position = CGPoint(x: offset.0, y: offset.1)
            node.addChild(chunk)
        }

        // Заросли травы (3 зеленых кружка)
        let grassCount = 3
        for i in 0..<grassCount {
            let weed = SKShapeNode(circleOfRadius: 1.5)
            weed.fillColor = Palette.nileGreen.darkened(by: 0.15)
            weed.strokeColor = .clear

            // Детерминированные позиции для травы
            let angle = CGFloat(i) * 2.0 * .pi / CGFloat(grassCount)
            let radius: CGFloat = 7.0
            weed.position = CGPoint(
                x: radius * cos(angle),
                y: radius * sin(angle)
            )
            node.addChild(weed)
        }

        // Трещина (линия чёрного цвета)
        let crack = SKShapeNode()
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -8, y: -2))
        p.addLine(to: CGPoint(x: 8, y: 1))
        crack.path = p
        crack.strokeColor = Palette.inkDark.withAlphaComponent(0.4)
        crack.lineWidth = 0.5
        node.addChild(crack)

        return node
    }
}
