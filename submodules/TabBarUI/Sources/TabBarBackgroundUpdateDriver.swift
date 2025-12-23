import Foundation
import UIKit
import SwiftSignalKit
import Display

protocol TabBarBackgroundCaptureInvalidating: AnyObject {
    func invalidateBackgroundCapture()
}

final class TabBarBackgroundUpdateDriver {
    private weak var invalidator: TabBarBackgroundCaptureInvalidating?

    private let invalidatedDisposable = MetaDisposable()

    private var displayLink: CADisplayLink?

    private var isVisible: Bool = false
    private var needsInvalidation: Bool = false
    private var keepAliveFramesRemaining: Int = 0

    init(invalidator: TabBarBackgroundCaptureInvalidating) {
        self.invalidator = invalidator
    }

    deinit {
        self.invalidatedDisposable.dispose()
        self.displayLink?.invalidate()
    }

    func setIsVisible(_ value: Bool) {
        self.isVisible = value
        self.updateDisplayLinkIfNeeded()
    }

    func setSource(_ source: TabBarBackgroundChangeSource?) {
        self.invalidatedDisposable.set(nil)

        self.needsInvalidation = false
        self.keepAliveFramesRemaining = 0

        if let source {
            self.invalidatedDisposable.set((source.invalidated
            |> deliverOnMainQueue).start(next: { [weak self] _ in
                self?.requestInvalidation()
            }))
        }

        self.updateDisplayLinkIfNeeded()
    }

    func warmup(frames: Int) {
        guard frames > 0 else {
            return
        }
        self.keepAliveFramesRemaining = max(self.keepAliveFramesRemaining, frames)
        self.updateDisplayLinkIfNeeded()
    }

    private func requestInvalidation() {
        self.needsInvalidation = true
        self.keepAliveFramesRemaining = max(self.keepAliveFramesRemaining, 2)
        self.updateDisplayLinkIfNeeded()
    }

    private func updateDisplayLinkIfNeeded() {
        let shouldRun = self.isVisible && (self.needsInvalidation || self.keepAliveFramesRemaining > 0)

        if shouldRun {
            if self.displayLink == nil {
                let displayLink = CADisplayLink(target: self, selector: #selector(self.displayLinkTick))
                displayLink.add(to: .main, forMode: .common)
                self.displayLink = displayLink
            }
        } else {
            self.displayLink?.invalidate()
            self.displayLink = nil
        }
    }

    @objc private func displayLinkTick() {
        guard self.isVisible else {
            self.updateDisplayLinkIfNeeded()
            return
        }

        if self.needsInvalidation || self.keepAliveFramesRemaining > 0 {
            self.invalidator?.invalidateBackgroundCapture()
        }

        self.needsInvalidation = false
        if self.keepAliveFramesRemaining > 0 {
            self.keepAliveFramesRemaining -= 1
        }

        self.updateDisplayLinkIfNeeded()
    }
}
