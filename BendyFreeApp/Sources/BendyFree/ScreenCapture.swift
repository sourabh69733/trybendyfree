import AppKit
import CoreGraphics

public final class ScreenCapture {
    public static func captureMainDisplay() -> CGImage? {
        let displayID = CGMainDisplayID()
        // Fast, hardware-accelerated capture of the main display
        if let image = CGDisplayCreateImage(displayID) {
            return image
        }
        
        // Fallback to WindowList if needed
        guard let screen = NSScreen.main else { return nil }
        return CGWindowListCreateImage(
            screen.frame,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        )
    }
}
