import Foundation

struct DistrictPlanner {

    func allocateNextOrigin(currentIndex: Int) -> GridPoint {
        // Растущая спираль от центра карты.
        // i = 0 → (0,0). Дальше — по виткам.
        if currentIndex == 0 { return GridPoint(x: 0, y: 0) }

        let layer = Int(((Double(currentIndex) + 1).squareRoot() + 1) / 2)
        let layerSize = 2 * layer
        let firstInLayer = (2 * layer - 1) * (2 * layer - 1)
        let offsetInLayer = currentIndex - firstInLayer
        let side = offsetInLayer / layerSize
        let stepInSide = offsetInLayer % layerSize

        var x = 0, y = 0
        switch side {
        case 0: x = layer; y = -layer + 1 + stepInSide
        case 1: x = layer - 1 - stepInSide; y = layer
        case 2: x = -layer; y = layer - 1 - stepInSide
        case 3: x = -layer + 1 + stepInSide; y = -layer
        default: break
        }

        let spacing = 14
        return GridPoint(x: x * spacing, y: y * spacing)
    }
}
