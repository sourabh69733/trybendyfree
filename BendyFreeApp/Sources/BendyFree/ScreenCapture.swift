import AppKit
import CoreImage

struct DesktopSnapshot {
    let sharp: CGImage
    let blurred: CGImage
}

enum CaptureFailure: Error {
    case busy, permissionRequired, imageUnavailable

    var message: String {
        switch self {
        case .busy: return "Capture busy — reopen the lid and retry"
        case .permissionRequired: return "Screen Recording permission required"
        case .imageUnavailable: return "Screen capture failed — reopen the lid and retry"
        }
    }
}

@MainActor
public enum ScreenCapture {
    private static let queue = DispatchQueue(label: "in.trybendyfree.capture", qos: .userInitiated)
    private static var isBusy = false

    /// A single capture may be in flight. Never block the UI or queue old snapshots.
    static func capture(displayID: CGDirectDisplayID, completion: @escaping (Result<DesktopSnapshot, CaptureFailure>) -> Void) {
        guard CGPreflightScreenCaptureAccess() else {
            completion(.failure(.permissionRequired))
            return
        }
        guard !isBusy else {
            completion(.failure(.busy))
            return
        }
        isBusy = true
        queue.async {
            let snapshot: DesktopSnapshot? = autoreleasepool {
                guard let image = CGDisplayCreateImage(displayID) else { return nil }
                let source = CIImage(cgImage: image)
                // Blur needs less resolution than the sharp desktop layer.
                let scale = min(1, 1600 / CGFloat(image.width))
                let small = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                let blurred = small.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 20 * scale])
                let context = CIContext(options: [.useSoftwareRenderer: false])
                let buffer = context.createCGImage(blurred, from: small.extent) ?? image
                return DesktopSnapshot(sharp: image, blurred: buffer)
            }
            DispatchQueue.main.async {
                isBusy = false
                if let snapshot { completion(.success(snapshot)) }
                else { completion(.failure(.imageUnavailable)) }
            }
        }
    }
}
