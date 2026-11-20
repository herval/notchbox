import Foundation
import CoreGraphics
import Testing
@testable import NotchboxCore

@Test func geometryUsesHardwareNotchOnOffsetDisplay() {
    let geometry = PanelGeometry(
        screen: CGRect(x: -1728, y: 200, width: 1728, height: 1117), topInset: 38,
        leftArea: CGRect(x: -1728, y: 1279, width: 764, height: 38),
        rightArea: CGRect(x: -764, y: 1279, width: 764, height: 38))
    #expect(geometry.notch.midX == -864)
    #expect(geometry.expandedFrame().midX == -864)
    #expect(geometry.expandedFrame().maxY == 1317)
    #expect(geometry.triggerFrame.contains(CGPoint(x: -864, y: 1275)))
    #expect(!geometry.triggerFrame.contains(CGPoint(x: -1100, y: 1290)))
}

@Test func geometryFitsSmallExternalDisplay() {
    let geometry = PanelGeometry(screen: CGRect(x: 100, y: -600, width: 640, height: 480), topInset: 0)
    let frame = geometry.expandedFrame()
    #expect(frame.minX >= 116)
    #expect(frame.maxX <= 724)
    #expect(frame.minY >= -536)
    #expect(frame.maxY == -120)
    #expect(geometry.notch.midX == 420)
}

@Test func navigationWrapsAndClosingSelectedChoosesNeighbor() {
    let a = UUID(), b = UUID(), c = UUID()
    var tabs = TabSelection()
    [a, b, c].forEach { tabs.append($0) }
    tabs.advance(by: 1)
    #expect(tabs.selected == a)
    tabs.advance(by: -1)
    #expect(tabs.selected == c)
    tabs.select(b)
    tabs.remove(b)
    #expect(tabs.selected == c)
    tabs.remove(c)
    #expect(tabs.selected == a)
    tabs.remove(a)
    #expect(tabs.selected == nil)
    #expect(tabs.ids.isEmpty)
    tabs.advance(by: -1)
    #expect(tabs.selected == nil)
}

@Test func closingBackgroundTabPreservesSelectionAndInvalidSelectionsAreIgnored() {
    let a = UUID(), b = UUID()
    var tabs = TabSelection()
    tabs.append(a)
    tabs.append(b)
    tabs.append(b)
    tabs.select(index: 25)
    tabs.select(UUID())
    tabs.remove(a)
    #expect(tabs.ids == [b])
    #expect(tabs.selected == b)
}
