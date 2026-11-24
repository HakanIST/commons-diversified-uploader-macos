import CoreGraphics
import Foundation
import ImageIO

public enum JerseyColor {
    public static let names = ["siyah", "beyaz", "gri", "kırmızı", "turuncu", "sarı", "yeşil", "turkuaz", "mavi", "lacivert", "mor", "pembe", "bordo"]

    public static func name(r: UInt8, g: UInt8, b: UInt8) -> String {
        let rf = Double(r), gf = Double(g), bf = Double(b)
        let mx = max(rf, gf, bf), mn = min(rf, gf, bf)
        let v = mx / 255, s = mx == 0 ? 0 : (mx - mn) / mx
        if v < 0.2 { return "siyah" }
        if s < 0.18 { return v > 0.75 ? "beyaz" : v < 0.35 ? "siyah" : "gri" }
        let d = mx - mn
        var h: Double
        if mx == rf { h = ((gf - bf) / d).truncatingRemainder(dividingBy: 6) } else if mx == gf { h = (bf - rf) / d + 2 } else { h = (rf - gf) / d + 4 }
        h = (h * 60 + 360).truncatingRemainder(dividingBy: 360)
        if h < 15 || h >= 345 { return v < 0.5 ? "bordo" : "kırmızı" }
        if h < 40 { return v < 0.45 ? "bordo" : "turuncu" }
        if h < 70 { return "sarı" }
        if h < 160 { return "yeşil" }
        if h < 195 { return "turkuaz" }
        if h < 255 { return v < 0.45 ? "lacivert" : "mavi" }
        if h < 290 { return "mor" }
        return v < 0.5 ? "bordo" : "pembe"
    }
}

/// Satır sıralı RGB piksel tamponu.
struct RGBImage {
    let width: Int, height: Int
    var data: [UInt8]

    init?(cgImage: CGImage, width: Int, height: Int, crop: CGRect? = nil) {
        self.width = width; self.height = height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &rgba, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        let source = crop.flatMap { cgImage.cropping(to: $0) } ?? cgImage
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        data = [UInt8](repeating: 0, count: width * height * 3)
        for i in 0..<(width * height) {
            data[i * 3] = rgba[i * 4]; data[i * 3 + 1] = rgba[i * 4 + 1]; data[i * 3 + 2] = rgba[i * 4 + 2]
        }
    }
}

public enum ImageLoader {
    /// EXIF yönü uygulanmış, uzun kenarı en çok `maxPixel` olan görüntü.
    public static func load(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// EXIF çekim zamanı, "YYYY-MM-DD HH:MM:SS" biçiminde.
    public static func captureDate(_ url: URL) -> String? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let raw = (exif[kCGImagePropertyExifDateTimeOriginal] ?? exif[kCGImagePropertyExifDateTimeDigitized]) as? String,
              raw.count >= 19 else { return nil }
        let parts = raw.split(separator: " ")
        guard parts.count == 2 else { return nil }
        return parts[0].replacingOccurrences(of: ":", with: "-") + " " + parts[1]
    }
}

public final class ImageAnalyzer {
    public static let workLongSide = 3072
    private let ocr: FlorenceOCR

    public init(ocr: FlorenceOCR) { self.ocr = ocr }

    /// Tam kare + örtüşen ızgara parçaları.
    public static func tiles(width: Int, height: Int, cols: Int, rows: Int, overlap: Double = 0.25) -> [CGRect] {
        var out = [CGRect(x: 0, y: 0, width: width, height: height)]
        guard cols * rows > 1 else { return out }
        let tw = Int((Double(width) / (Double(cols) - Double(cols - 1) * overlap)).rounded())
        let th = Int((Double(height) / (Double(rows) - Double(rows - 1) * overlap)).rounded())
        for r in 0..<rows { for c in 0..<cols {
            let x = cols == 1 ? 0 : Int((Double(c * (width - tw)) / Double(cols - 1)).rounded())
            let y = rows == 1 ? 0 : Int((Double(r * (height - th)) / Double(rows - 1)).rounded())
            out.append(CGRect(x: x, y: y, width: tw, height: th))
        } }
        return out
    }

    static func colors(around rect: CGRect, in image: RGBImage) -> [String: Double] {
        let x0 = max(0, Int((rect.minX - rect.width * 0.6).rounded())), x1 = min(image.width, Int((rect.maxX + rect.width * 0.6).rounded()))
        let y0 = max(0, Int((rect.minY - rect.height * 0.5).rounded())), y1 = min(image.height, Int((rect.maxY + rect.height * 0.5).rounded()))
        guard x1 > x0, y1 > y0 else { return [:] }
        let step = max(1, Int((Double(min(x1 - x0, y1 - y0)) / 40).rounded()))
        var hist: [String: Int] = [:]
        var n = 0
        for y in stride(from: y0, to: y1, by: step) { for x in stride(from: x0, to: x1, by: step) {
            let i = (y * image.width + x) * 3
            hist[JerseyColor.name(r: image.data[i], g: image.data[i + 1], b: image.data[i + 2]), default: 0] += 1
            n += 1
        } }
        return hist.mapValues { (Double($0) / Double(n) * 1000).rounded() / 1000 }
    }

    private static func iou(_ a: CGRect, _ b: CGRect) -> Double {
        let i = a.intersection(b)
        guard !i.isNull else { return 0 }
        let inter = i.width * i.height
        let union = a.width * a.height + b.width * b.height - inter
        return union > 0 ? Double(inter / union) : 0
    }

    public func analyze(_ url: URL, grid: (cols: Int, rows: Int) = (3, 2)) throws -> PhotoAnalysis {
        guard let image = ImageLoader.load(url, maxPixel: Self.workLongSide),
              let full = RGBImage(cgImage: image, width: image.width, height: image.height) else {
            throw OrtError(description: L("Görüntü açılamadı: \(url.lastPathComponent)"))
        }
        let W = image.width, H = image.height
        let (cols, rows) = W >= H ? grid : (grid.rows, grid.cols)
        var merged: [(region: TextRegion, hits: Int)] = []
        for tile in Self.tiles(width: W, height: H, cols: cols, rows: rows) {
            guard let input = RGBImage(cgImage: image, width: FlorenceOCR.inputSize, height: FlorenceOCR.inputSize, crop: tile) else { continue }
            for var region in try ocr.recognize(rgb768: input.data, imageSize: tile.size) {
                region.rect = region.rect.offsetBy(dx: tile.minX, dy: tile.minY)
                if let i = merged.firstIndex(where: { $0.region.text == region.text && Self.iou($0.region.rect, region.rect) > 0.3 }) {
                    merged[i].hits += 1
                } else {
                    merged.append((region, 1))
                }
            }
        }
        var numbers: [NumberDetection] = [], texts: [TextDetection] = []
        for (region, hits) in merged {
            let r = region.rect
            let box = NormalizedBox(x0: r.minX / CGFloat(W), y0: r.minY / CGFloat(H), x1: r.maxX / CGFloat(W), y1: r.maxY / CGFloat(H))
            if region.text.count <= 2, !region.text.isEmpty, region.text.allSatisfy({ $0.isASCII && $0.isNumber }) {
                numbers.append(NumberDetection(number: region.text, box: box, hits: hits, heightRatio: (box.height * 10000).rounded() / 10000, colors: Self.colors(around: r, in: full)))
            } else if region.text.count >= 3 {
                texts.append(TextDetection(text: region.text, box: box))
            }
        }
        return PhotoAnalysis(width: W, height: H, numbers: numbers, texts: texts)
    }
}
