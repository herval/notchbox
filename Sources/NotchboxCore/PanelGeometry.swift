import Foundation
import CoreGraphics

/// All coordinates use the global, bottom-left AppKit screen coordinate system.
public struct PanelGeometry {
    public let screen: CGRect
    public let topInset: CGFloat
    public let notch: CGRect

    public init(screen: CGRect, topInset: CGFloat, leftArea: CGRect? = nil, rightArea: CGRect? = nil) {
        self.screen = screen
        self.topInset = max(topInset, 24)
        if topInset > 0, let left = leftArea, let right = rightArea, right.minX > left.maxX {
            notch = CGRect(x: left.maxX, y: screen.maxY - topInset,
                           width: right.minX - left.maxX, height: topInset)
        } else {
            notch = CGRect(x: screen.midX - 88, y: screen.maxY - self.topInset,
                           width: 176, height: self.topInset)
        }
    }

    public var triggerFrame: CGRect {
        // Include the exact top edge and a small lip below the camera cutout.
        CGRect(x: notch.minX - 12, y: notch.minY - 12,
               width: notch.width + 24, height: notch.height + 14)
    }

    public func expandedFrame(width: CGFloat = 900, height: CGFloat = 460) -> CGRect {
        let width = min(width, max(1, screen.width - 32))
        let height = min(height + topInset, max(1, screen.height - 64))
        let x = min(max(notch.midX - width / 2, screen.minX + 16), screen.maxX - width - 16)
        return CGRect(x: x, y: screen.maxY - height, width: width, height: height)
    }
}
