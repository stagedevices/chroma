import Foundation

public protocol SetlistService: AnyObject {
    func loadSets() -> [PerformanceSet]
}

public final class PlaceholderSetlistService: SetlistService {
    private let sets: [PerformanceSet]

    public init(sets: [PerformanceSet] = []) {
        self.sets = sets
    }

    public func loadSets() -> [PerformanceSet] {
        sets
    }
}
