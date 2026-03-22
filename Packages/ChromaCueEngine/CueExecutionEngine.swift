import Foundation
import Combine

public final class CueExecutionEngine: ObservableObject {
    @Published public private(set) var activeCueIndex: Int?
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var loadedSet: PerformanceSet?

    private let cueAdvanceSubject = PassthroughSubject<PerformanceCue, Never>()
    public var cueAdvancePublisher: AnyPublisher<PerformanceCue, Never> {
        cueAdvanceSubject.eraseToAnyPublisher()
    }

    private var advanceTimer: DispatchWorkItem?

    public init() {}

    // MARK: - Control

    public func load(set: PerformanceSet) {
        stop()
        loadedSet = set
    }

    public func start() {
        guard let set = loadedSet, !set.cues.isEmpty else { return }
        isRunning = true
        activeCueIndex = 0
        fireCue(at: 0, in: set)
    }

    public func advanceToNext() {
        guard isRunning, let set = loadedSet, let current = activeCueIndex else { return }
        let next = current + 1
        guard next < set.cues.count else {
            stop()
            return
        }
        cancelPendingAdvance()
        activeCueIndex = next
        fireCue(at: next, in: set)
    }

    public func stop() {
        cancelPendingAdvance()
        isRunning = false
        activeCueIndex = nil
    }

    public func reset() {
        stop()
    }

    // MARK: - Execution

    private func fireCue(at index: Int, in set: PerformanceSet) {
        let cue = set.cues[index]
        cueAdvanceSubject.send(cue)

        // Schedule auto-advance if the next cue has a delay
        let nextIndex = index + 1
        guard nextIndex < set.cues.count else { return }
        let nextCue = set.cues[nextIndex]
        guard nextCue.delayFromPrevious > 0 else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning, self.activeCueIndex == index else { return }
            self.activeCueIndex = nextIndex
            self.fireCue(at: nextIndex, in: set)
        }
        advanceTimer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + nextCue.delayFromPrevious, execute: workItem)
    }

    private func cancelPendingAdvance() {
        advanceTimer?.cancel()
        advanceTimer = nil
    }
}
