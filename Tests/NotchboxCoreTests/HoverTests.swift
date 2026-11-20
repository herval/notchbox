import Foundation
import CoreGraphics
import Testing
@testable import NotchboxCore

@Test func stationaryPointerActivatesWithoutAnotherMouseEvent() {
    var hover = HoverActivation()
    let samples: [(UInt32?, Double, Bool)] = [(7, 1, false), (7, 1.13, true), (7, 1.3, false)]
    for (target, time, expected) in samples {
        let activated = hover.update(target: target, at: time)
        #expect(activated == expected)
    }
}

@Test func movementWithinTheSameDisplayDoesNotRestartDwell() {
    var hover = HoverActivation()
    for step in 0..<12 {
        let activated = hover.update(target: 42, at: Double(step) * 0.01)
        #expect(!activated)
    }
    let activated = hover.update(target: 42, at: 0.13)
    #expect(activated)
}

@Test func crossingAnotherDisplayOrLeavingRestartsDwell() {
    var hover = HoverActivation()
    let samples: [(UInt32?, Double, Bool)] = [
        (1, 0, false), (2, 0.1, false), (2, 0.15, false), (nil, 0.2, false), (2, 0.3, false), (2, 0.43, true)
    ]
    for (target, time, expected) in samples {
        let activated = hover.update(target: target, at: time)
        #expect(activated == expected)
    }
}

@Test func explicitCloseRearmsAfterPointerExits() {
    var hover = HoverActivation()
    hover.suppressUntilExit()
    let samples: [(UInt32?, Double, Bool)] = [(1, 0, false), (1, 2, false), (nil, 3, false), (1, 4, false), (1, 4.13, true)]
    for (target, time, expected) in samples {
        let activated = hover.update(target: target, at: time)
        #expect(activated == expected)
    }
}

@Test func triggerIncludesExactTopEdgeAndLipBelowNotch() {
    let geometry = PanelGeometry(screen: CGRect(x: -1800, y: 100, width: 1800, height: 1169), topInset: 38)
    #expect(geometry.triggerFrame.contains(CGPoint(x: -900, y: 1269)))
    #expect(geometry.triggerFrame.contains(CGPoint(x: -900, y: 1221)))
    #expect(!geometry.triggerFrame.contains(CGPoint(x: -900, y: 1200)))
    #expect(!geometry.triggerFrame.contains(CGPoint(x: -1200, y: 1269)))
}
