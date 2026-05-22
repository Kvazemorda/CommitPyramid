import Foundation

enum StageRules {

    static func computeStage(taskCount: Int, ageDays: Int) -> Int {
        // Простая формула MVP: stage растёт от taskCount и плавно — от возраста.
        // Стадии 0..5.
        let byCount: Int
        switch taskCount {
        case 0...1:    byCount = 0
        case 2...5:    byCount = 1
        case 6...12:   byCount = 2
        case 13...25:  byCount = 3
        case 26...50:  byCount = 4
        default:       byCount = 5
        }
        let byAge: Int
        switch ageDays {
        case 0...3:     byAge = 0
        case 4...14:    byAge = 1
        case 15...45:   byAge = 2
        case 46...120:  byAge = 3
        case 121...365: byAge = 4
        default:        byAge = 5
        }
        return min(byCount, byAge)
    }
}
