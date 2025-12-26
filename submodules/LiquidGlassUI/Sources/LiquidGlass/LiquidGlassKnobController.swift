import UIKit

final class LiquidGlassTabSelectorController: LiquidGlassKnobSink {
    var onSelectionCommit: ((Int) -> Void)?
    var onResting: (() -> Void)?

    var restingFrameForIndex: ((Int) -> CGRect)?
    var liquidFrameForIndex: ((Int) -> CGRect)?
    weak var staticKnobLayer: CALayer?

    private(set) var selectorState: SelectorState = .resting(selectedIndex: 0)

    private let engine: LiquidGlassKnobEngine

    private var pendingSnapIndex: Int?
    private var pendingTapCommitIndex: Int?

    init(engine: LiquidGlassKnobEngine) {
        self.engine = engine
    }

    // MARK: - LiquidGlassKnobSink

    func beginAnimation(fromIndex: Int, mode: BeginMode) {
        guard
            case .resting = selectorState,
            let staticKnobLayer,
            let restingFrame = restingFrameForIndex?(fromIndex),
            let liquidFrame = liquidFrameForIndex?(fromIndex)
        else { return }

        let targetMode: TargetMode
        switch mode {
        case .tap(let toIndex):
            targetMode = .tapToIndex(toIndex)
        case .pan:
            targetMode = .interactivePan
        }

        pendingSnapIndex = nil
        pendingTapCommitIndex = nil

        transition(to: .transitioningToLiquid(fromIndex: fromIndex, target: targetMode))

        engine.beginHandoff(restingFrame: restingFrame, liquidFrame: liquidFrame, staticLayer: staticKnobLayer) { [weak self] in
            self?.handleTransitionInCompleted(fromIndex: fromIndex, target: targetMode)
        }

        if case .tapToIndex(let toIndex) = targetMode {
            startTapTravel(toIndex: toIndex, duringHandoff: true)
        }
    }

    func updateInteractive(x: CGFloat, velocity: CGFloat) {
        guard allowsInteractiveUpdates(in: selectorState) else { return }

        let centerY: CGFloat
        switch selectorState {
        case .transitioningToLiquid(let fromIndex, target: .interactivePan),
             .liquidInteractive(let fromIndex):
            if let frame = liquidFrameForIndex?(fromIndex) {
                centerY = frame.midY
            } else {
                centerY = engine.shapeDriver.presentationState.center.y
            }
        default:
            return
        }

        let center = CGPoint(x: x, y: centerY)
        engine.updateCenter(center, staticLayer: staticKnobLayer)
    }

    func snap(toIndex: Int) {
        switch selectorState {
        case .transitioningToLiquid(_, target: .interactivePan):
            pendingSnapIndex = toIndex
            return
        case .liquidInteractive(let fromIndex):
            startSnap(fromIndex: fromIndex, toIndex: toIndex)
        default:
            return
        }
    }

    func endAnimation(finalIndex: Int) {
        guard let staticKnobLayer else { return }

        switch selectorState {
        case .liquidAnimating(_, let toIndex) where toIndex == finalIndex,
             .snappingToIndex(_, let toIndex) where toIndex == finalIndex:
            break
        default:
            return
        }

        transition(to: .transitioningToResting(selectedIndex: finalIndex))

        guard let restingFrame = restingFrameForIndex?(finalIndex),
              let liquidFrame = liquidFrameForIndex?(finalIndex)
        else { return }

        engine.endHandoff(restingFrame: restingFrame, liquidFrame: liquidFrame, staticLayer: staticKnobLayer) { [weak self] in
            guard let self else { return }
            self.transition(to: .resting(selectedIndex: finalIndex))
            self.onResting?()
        }
    }

    // MARK: - Selector internals

    private func allowsInteractiveUpdates(in state: SelectorState) -> Bool {
        switch state {
        case .transitioningToLiquid(_, target: .interactivePan), .liquidInteractive:
            return true
        default:
            return false
        }
    }

    private func handleTransitionInCompleted(fromIndex: Int, target: TargetMode) {
        guard
            case .transitioningToLiquid(let currentFromIndex, let currentTarget) = selectorState,
            currentFromIndex == fromIndex,
            currentTarget == target
        else { return }

        switch target {
        case .tapToIndex(let toIndex):
            transition(to: .liquidAnimating(fromIndex: fromIndex, toIndex: toIndex))
            if pendingTapCommitIndex == toIndex {
                pendingTapCommitIndex = nil
                onSelectionCommit?(toIndex)
            }
        case .interactivePan:
            transition(to: .liquidInteractive(fromIndex: fromIndex))
            if let pendingSnapIndex {
                self.pendingSnapIndex = nil
                startSnap(fromIndex: fromIndex, toIndex: pendingSnapIndex)
            }
        }
    }

    private func startTapTravel(toIndex: Int, duringHandoff: Bool) {
        guard let targetFrame = restingFrameForIndex?(toIndex) else { return }
        let targetCenter = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
        let duration = engine.travelDuration(to: targetCenter)

        let completion: () -> Void = { [weak self] in
            self?.handleTapTravelCompleted(toIndex: toIndex)
        }

        if duringHandoff {
            engine.startTravelDuringHandoff(to: targetCenter, duration: duration, timing: .easeInOut, completion: completion)
        } else {
            engine.startTravel(to: targetCenter, duration: duration, timing: .easeInOut, completion: completion)
        }
    }

    private func handleTapTravelCompleted(toIndex: Int) {
        switch selectorState {
        case .transitioningToLiquid(_, target: .tapToIndex(let expected)) where expected == toIndex:
            pendingTapCommitIndex = toIndex
        case .liquidAnimating(_, let expected) where expected == toIndex,
             .snappingToIndex(_, let expected) where expected == toIndex:
            onSelectionCommit?(toIndex)
        default:
            break
        }
    }

    private func startSnap(fromIndex: Int, toIndex: Int) {
        transition(to: .snappingToIndex(fromIndex: fromIndex, toIndex: toIndex))
        guard let targetFrame = restingFrameForIndex?(toIndex) else { return }
        let targetCenter = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
        engine.startTravel(to: targetCenter, duration: engine.snapDuration(to: targetCenter), timing: .spring(dampingRatio: engine.snapSpringDampingRatio)) { [weak self] in
            self?.onSelectionCommit?(toIndex)
        }
    }

    private func transition(to newState: SelectorState) {
        guard isValidTransition(from: selectorState, to: newState) else {
            assertionFailure("Invalid selector transition \(selectorState) → \(newState)")
            return
        }
        selectorState = newState
        engine.motionMode = allowsInteractiveUpdates(in: newState) ? .interactive : .travel
    }

    private func isValidTransition(from oldState: SelectorState, to newState: SelectorState) -> Bool {
        switch (oldState, newState) {
        case (.resting, .transitioningToLiquid):
            return true
        case let (.transitioningToLiquid(_, target), .liquidAnimating) where isTapTarget(target):
            return true
        case let (.transitioningToLiquid(_, target), .liquidInteractive) where target == .interactivePan:
            return true
        case (.liquidInteractive, .snappingToIndex):
            return true
        case (.liquidAnimating, .transitioningToResting):
            return true
        case (.snappingToIndex, .transitioningToResting):
            return true
        case (.transitioningToResting, .resting):
            return true
        default:
            return false
        }
    }

    private func isTapTarget(_ target: TargetMode) -> Bool {
        switch target {
        case .tapToIndex:
            return true
        case .interactivePan:
            return false
        }
    }
}
