import SpriteKit

// MARK: - Citizen model (reference type for mutable currentGrid)

final class Citizen {
    let id: UUID
    let projectId: String
    let node: SKNode
    var currentGrid: GridPoint

    init(id: UUID, projectId: String, node: SKNode, currentGrid: GridPoint) {
        self.id = id
        self.projectId = projectId
        self.node = node
        self.currentGrid = currentGrid
    }
}

// MARK: - CitizenManager

final class CitizenManager {

    weak var engine: CityEngine?
    weak var scene: GameScene?

    // Flat dict by UUID for O(1) lookup; project-index for grouping
    private var citizens: [UUID: Citizen] = [:]
    private var citizensByProject: [String: Set<UUID>] = [:]
    private var citizensLeaving: Set<UUID> = []

    // Monotonically increasing seed — never reuses same seed after removal
    private var nextCitizenSeed: Int = 0

    private let speed: CGFloat = 30       // pt/sec screen
    private let globalCap = 150

    // MARK: - Public lifecycle

    func start() {
        let tick = SKAction.repeatForever(SKAction.sequence([
            SKAction.wait(forDuration: 2.0),
            SKAction.run { [weak self] in self?.tick() }
        ]))
        scene?.run(tick, withKey: "citizenTick")
    }

    func stop() {
        scene?.removeAction(forKey: "citizenTick")
    }

    // MARK: - Target calculation

    private func targetCount(for project: ProjectState) -> Int {
        if project.unitIds.isEmpty || project.decayLevel == 4 { return 0 }
        if project.stage < 2 { return 0 }
        let formula = min(20, project.stage * 2 + project.unitIds.count / 4)
        return max(3, formula)
    }

    // MARK: - Tick

    private func tick() {
        guard let engine = engine else { return }

        // 1. Compute desired targets
        var desired: [(id: String, target: Int, lastActivity: Date)] = []
        for project in engine.state.projects.values {
            desired.append((project.id, targetCount(for: project), project.lastActivityAt))
        }

        // 2. Global cap — prioritise by lastActivityAt descending
        let sortedDesired = desired.sorted { $0.lastActivity > $1.lastActivity }
        var remaining = globalCap
        var allocated: [String: Int] = [:]
        for entry in sortedDesired {
            let alloc = min(entry.target, remaining)
            allocated[entry.id] = alloc
            remaining -= alloc
        }

        // 3. Apply: spawn or remove per project
        for (projectId, target) in allocated {
            guard let project = engine.state.projects[projectId] else { continue }
            // citizens.count includes leaving — prevents double-spawn
            let currentCount = citizensByProject[projectId]?.count ?? 0
            if currentCount < target {
                for _ in 0..<(target - currentCount) {
                    spawnCitizen(in: project)
                }
            } else if currentCount > target {
                let toRemove = currentCount - target
                removeCitizens(projectId: projectId, count: toRemove)
            }
        }

        // 4. Cleanup projects removed from state
        let stateProjectIds = Set(engine.state.projects.keys)
        for projectId in citizensByProject.keys where !stateProjectIds.contains(projectId) {
            removeAllCitizens(projectId: projectId)
        }

        // 5. Publish per-project active count to UI bridge.
        // Ключи — все проекты из state, чтобы пустые кварталы получали явный 0.
        var snapshot: [String: Int] = [:]
        snapshot.reserveCapacity(engine.state.projects.count)
        for projectId in engine.state.projects.keys {
            snapshot[projectId] = activeCitizenCount(for: projectId)
        }
        scene?.bridge?.populationByProject = snapshot
    }

    // MARK: - Waypoints

    private func waypoints(for project: ProjectState) -> [GridPoint] {
        guard let engine = engine else { return [] }
        let units = project.unitIds.compactMap { engine.state.units[$0.uuidString] }

        // Priority 1: road tiles
        let roads = units.filter { $0.kind == .road }.map { $0.position }
        if !roads.isEmpty { return roads }

        // Priority 2: non-residential civic buildings
        let nonRes = units.filter {
            [UnitKind.forum, .market, .well, .warehouse].contains($0.kind)
        }.map { $0.position }
        if !nonRes.isEmpty { return nonRes }

        // Priority 3: 6 random points ±4 from districtOrigin
        let origin = project.districtOrigin
        return (0..<6).map { _ in
            GridPoint(
                x: origin.x + Int.random(in: -4...4),
                y: origin.y + Int.random(in: -4...4)
            )
        }
    }

    // MARK: - Spawn

    private func spawnCitizen(in project: ProjectState) {
        guard let scene = scene else { return }
        let waypts = waypoints(for: project)
        guard let firstWp = waypts.randomElement() else { return }

        let seed = nextCitizenSeed
        nextCitizenSeed += 1

        let node = CitizenSprites.makeCitizen(seed: seed)
        node.isUserInteractionEnabled = false
        node.alpha = 0
        node.position = scene.isoPosition(grid: firstWp)
        node.zPosition = -CGFloat(firstWp.x + firstWp.y) + 0.5

        scene.worldNode.addChild(node)

        let citizenId = UUID()
        let citizen = Citizen(id: citizenId, projectId: project.id, node: node, currentGrid: firstWp)
        citizens[citizenId] = citizen
        citizensByProject[project.id, default: []].insert(citizenId)

        node.run(SKAction.fadeIn(withDuration: 1.0))
        walk(citizen: citizen)
    }

    // MARK: - Walk

    private func walk(citizen: Citizen) {
        guard let engine = engine,
              let project = engine.state.projects[citizen.projectId],
              let scene = scene else { return }

        let waypts = waypoints(for: project)
        guard let next = waypts.filter({ $0 != citizen.currentGrid }).randomElement() else { return }

        // Bounding box check: <= 6 inclusive from districtOrigin
        let origin = project.districtOrigin
        let dx = next.x - origin.x
        let dy = next.y - origin.y
        guard abs(dx) <= 6 && abs(dy) <= 6 else {
            walkFallback(citizen: citizen, project: project)
            return
        }

        let targetPos = scene.isoPosition(grid: next)
        let distance = hypot(
            targetPos.x - citizen.node.position.x,
            targetPos.y - citizen.node.position.y
        )
        let duration = distance / speed

        let citizenId = citizen.id
        citizen.node.run(SKAction.move(to: targetPos, duration: duration)) { [weak self] in
            guard let self,
                  let c = self.citizens[citizenId],
                  !self.citizensLeaving.contains(citizenId) else { return }
            c.currentGrid = next
            c.node.zPosition = -CGFloat(next.x + next.y) + 0.5
            self.walk(citizen: c)
        }
    }

    /// Fallback: picks a waypoint strictly within ±6 of districtOrigin.
    /// If none found, uses districtOrigin itself.
    private func walkFallback(citizen: Citizen, project: ProjectState) {
        guard let scene = scene else { return }
        let origin = project.districtOrigin
        let waypts = waypoints(for: project)
        let bounded = waypts.filter { wp in
            abs(wp.x - origin.x) <= 6 && abs(wp.y - origin.y) <= 6
        }
        let next = bounded.filter { $0 != citizen.currentGrid }.randomElement()
            ?? bounded.randomElement()
            ?? origin

        let targetPos = scene.isoPosition(grid: next)
        let distance = hypot(
            targetPos.x - citizen.node.position.x,
            targetPos.y - citizen.node.position.y
        )
        let duration = distance / speed

        let citizenId = citizen.id
        citizen.node.run(SKAction.move(to: targetPos, duration: duration)) { [weak self] in
            guard let self,
                  let c = self.citizens[citizenId],
                  !self.citizensLeaving.contains(citizenId) else { return }
            c.currentGrid = next
            c.node.zPosition = -CGFloat(next.x + next.y) + 0.5
            self.walk(citizen: c)
        }
    }

    // MARK: - Public read API

    /// Количество активных жителей проекта на сцене (без тех, кто доигрывает fade-out).
    /// Безопасно читать с main thread — CitizenManager main-bound (SKAction).
    func activeCitizenCount(for projectId: String) -> Int {
        guard let ids = citizensByProject[projectId] else { return 0 }
        return ids.subtracting(citizensLeaving).count
    }

    #if DEBUG
    /// Test-only seam: вкатывает UUID в индексы без полноценного spawn
    /// (тот зависит от scene/engine). Имя с префиксом `_test` — для grep'а.
    /// Доступен ТОЛЬКО в Debug-сборке.
    func _testSeed(projectId: String, leaving: Bool) -> UUID {
        let id = UUID()
        citizensByProject[projectId, default: []].insert(id)
        if leaving { citizensLeaving.insert(id) }
        return id
    }
    #endif

    // MARK: - Remove (two-phase)

    private func removeCitizens(projectId: String, count: Int) {
        guard let projectCitizens = citizensByProject[projectId] else { return }
        let ids = projectCitizens.filter { !citizensLeaving.contains($0) }.prefix(count)
        for id in ids {
            citizensLeaving.insert(id)
            guard let c = citizens[id] else { continue }
            c.node.removeAllActions()
            let capturedId = id
            c.node.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 1.0),
                SKAction.run { [weak self] in
                    self?.citizens.removeValue(forKey: capturedId)
                    self?.citizensByProject[projectId]?.remove(capturedId)
                    self?.citizensLeaving.remove(capturedId)
                },
                SKAction.removeFromParent()
            ]))
        }
    }

    private func removeAllCitizens(projectId: String) {
        guard let projectCitizens = citizensByProject[projectId] else { return }
        let count = projectCitizens.count
        removeCitizens(projectId: projectId, count: count)
    }
}
