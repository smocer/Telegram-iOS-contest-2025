import Foundation
import SwiftSignalKit

public protocol TabBarBackgroundChangeSource {
    var invalidated: Signal<Void, NoError> { get }
}

public protocol TabBarBackgroundChangeProviding {
    var tabBarBackgroundChangeSource: TabBarBackgroundChangeSource { get }
}

public protocol TabBarBackgroundChangeSourceEmitting: TabBarBackgroundChangeSource {
    func invalidate()
}

public final class TabBarBackgroundChangeSourceImpl: TabBarBackgroundChangeSourceEmitting {
    private let invalidatedPipe = ValuePipe<Void>()

    public init() {
    }

    public var invalidated: Signal<Void, NoError> {
        return self.invalidatedPipe.signal()
    }

    public func invalidate() {
        self.invalidatedPipe.putNext(())
    }
}
