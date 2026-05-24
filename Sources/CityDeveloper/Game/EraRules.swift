import Foundation

/// TASK-050 F-25: вычисление эпохи (0..3) после stage 5.
/// Pure (без I/O), testable без CityEngine.
enum EraRules {
    static func computeEra(taskCount: Int, stage: Int, ageDays: Int) -> Int {
        guard stage >= 5 else { return 0 }
        if taskCount >= 2000 && ageDays >= 365 { return 3 }
        if taskCount >= 500  && ageDays >= 180 { return 2 }
        if taskCount >= 100  && ageDays >= 30  { return 1 }
        return 0
    }
}
