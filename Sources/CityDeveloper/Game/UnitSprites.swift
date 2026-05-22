import SpriteKit

/// Фабрика визуала юнита: тайл-земля + тень + куб + крыша + декорации.
enum UnitSprites {

    static let tileWidth: CGFloat = 64
    static let tileHeight: CGFloat = 32

    // MARK: - userData keys

    static let unitIdKey = "unitId"
    static let projectIdKey = "projectId"

    // MARK: - Категориальный tier-набор (4 категории × 5 stage = 20 спрайтов)

    /// Точка входа для GameScene: создаёт контейнер с shadow + ground + building.
    /// building.name = "building" — ключ для swapStageSprite.
    /// anchorPoint контейнера — default (SKNode не имеет anchorPoint); позиция = bottom-centre сетки.
    static func makeStageNode(unit: UnitState, stageOverride: Int? = nil) -> SKNode {
        let category = unit.kind.category
        let stage = stageOverride ?? max(unit.tier, 1)
        let container = SKNode()

        // Shadow
        let shadow = IsoBuilder.shadow(width: tileWidth - 4, height: tileHeight - 2)
        shadow.position = CGPoint(x: 4, y: -2)
        shadow.zPosition = -2
        container.addChild(shadow)

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

        // Building (categorical tier sprite)
        let building = makeCategoricalBuilding(category: category, stage: stage)
        building.name = "building"
        building.position = .zero
        container.addChild(building)

        container.userData = NSMutableDictionary()
        container.userData?[unitIdKey] = unit.id
        container.userData?[projectIdKey] = unit.projectId

        return container
    }

    /// Диспетчер по категории → stage sprite. stage зажат в [1..5].
    static func makeCategoricalBuilding(category: UnitCategory, stage: Int) -> SKNode {
        let s = max(1, min(stage, 5))
        switch category {
        case .residential:    return makeResidentialStage(s)
        case .infrastructure: return makeInfrastructureStage(s)
        case .production:     return makeProductionStage(s)
        case .social:         return makeSocialStage(s)
        }
    }

    // MARK: - Ground color per category

    private static func categoricalGroundColor(for category: UnitCategory) -> SKColor {
        switch category {
        case .residential:    return Palette.sandLight
        case .infrastructure: return Palette.sandMid
        case .production:     return Palette.clay.darkened(by: 0.10)
        case .social:         return Palette.parchment
        }
    }

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
            // Лачуга: низкий земляной куб
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

        // 1. Тень
        let shadow = IsoBuilder.shadow(width: tileWidth - 4, height: tileHeight - 2)
        shadow.position = CGPoint(x: 4, y: -2)
        shadow.zPosition = -2
        container.addChild(shadow)

        // 2. Тайл-земля под юнитом
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
        }

        return container
    }

    // MARK: - Тайл-земля под юнитом

    private static func groundColor(for kind: UnitKind) -> SKColor {
        switch kind {
        case .raw:           return Palette.clay.darkened(by: 0.15)        // вспаханное
        case .road:          return Palette.sandMid
        case .well:          return Palette.sandLight
        case .market, .forum: return Palette.sandLight.darkened(by: 0.05)  // мощёная плошадь
        case .temple, .obelisk: return Palette.parchment                   // светлый камень
        default:             return Palette.sandLight
        }
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
