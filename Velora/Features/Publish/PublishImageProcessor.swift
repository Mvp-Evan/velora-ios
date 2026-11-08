import UIKit
import ImageIO

/// Client image norms for publish (DES-v1.3-02-05 PUB-03):
/// HEIC→JPEG, long edge 2048, strip EXIF GPS, recommended <1.5MB after compress.
enum PublishImageProcessor {
    struct Result {
        let jpeg: Data
        let sha256: String
        let width: Int
        let height: Int
    }

    enum ProcessError: Error {
        case invalidImage
        case tooLargeBeforeCompress
        case compressFailed
    }

    static func process(_ raw: Data) throws -> Result {
        if let err = PublishImageNorms.validateRawSize(raw.count) {
            _ = err
            throw ProcessError.tooLargeBeforeCompress
        }
        guard let image = decodeStrippingGPS(raw) else { throw ProcessError.invalidImage }
        let resized = image.resized(maxSide: CGFloat(PublishLimits.maxSidePx))
        guard let jpeg = resized.jpegData(compressionQuality: CGFloat(PublishLimits.jpegQuality)) else {
            throw ProcessError.compressFailed
        }
        // Soft second pass if still heavy
        var out = jpeg
        if out.count > PublishLimits.recommendedBytesAfterCompress {
            if let tighter = resized.jpegData(compressionQuality: 0.72) {
                out = tighter
            }
        }
        let sha = PublishImageNorms.sha256Hex(out)
        return Result(
            jpeg: out,
            sha256: sha,
            width: Int(resized.size.width.rounded()),
            height: Int(resized.size.height.rounded())
        )
    }

    /// Decode via ImageIO without GPS; redrawing also drops EXIF.
    private static func decodeStrippingGPS(_ data: Data) -> UIImage? {
        let srcOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, srcOptions as CFDictionary) else {
            return UIImage(data: data)
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        if let gps = props?[kCGImagePropertyGPSDictionary] as? [CFString: Any], !gps.isEmpty {
            // Force re-encode path without location by drawing into a clean bitmap.
        }
        let decodeOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(PublishLimits.maxSidePx),
        ]
        if let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, decodeOpts as CFDictionary) {
            return UIImage(cgImage: cg)
        }
        return UIImage(data: data)
    }
}

extension UIImage {
    func resized(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale = maxSide / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let r = UIGraphicsImageRenderer(size: newSize, format: format)
        return r.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
