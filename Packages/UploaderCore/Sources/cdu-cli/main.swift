import AppKit
import Foundation
import UploaderCore

// Geliştirme aracı. Kullanım: cdu-cli fixture <modelKlasörü> <png> <json>
let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { print("komut: fixture"); exit(2) }

func rgb(from url: URL, size: Int) -> [UInt8] {
    let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
    let image = CGImageSourceCreateImageAtIndex(src, 0, nil)!
    var rgba = [UInt8](repeating: 0, count: size * size * 4)
    let ctx = CGContext(data: &rgba, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    var out = [UInt8](repeating: 0, count: size * size * 3)
    for i in 0..<(size * size) { out[i * 3] = rgba[i * 4]; out[i * 3 + 1] = rgba[i * 4 + 1]; out[i * 3 + 2] = rgba[i * 4 + 2] }
    return out
}

switch command {
case "fixture":
    let ocr = try FlorenceOCR(modelDirectory: URL(fileURLWithPath: args[1]))
    let expected = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[3]))) as! [String: Any]
    let start = Date()
    let tokens = try ocr.generate(rgb768: rgb(from: URL(fileURLWithPath: args[2]), size: 768))
    print("süre:", Int(Date().timeIntervalSince(start) * 1000), "ms")
    let want = (expected["tokenIds"] as! [Int]).map(Int64.init)
    print(tokens == want ? "BELİRTEÇLER AYNI (\(tokens.count))" : "FARKLI\n beklenen: \(want)\n bulunan:  \(tokens)")
    print(ocr.decode(tokens))
case "analyze":
    // cdu-cli analyze <modelKlasörü> <fotoğraf>...
    let analyzer = ImageAnalyzer(ocr: try FlorenceOCR(modelDirectory: URL(fileURLWithPath: args[1])))
    for path in args.dropFirst(2) {
        let start = Date()
        let a = try analyzer.analyze(URL(fileURLWithPath: path))
        let nums = a.numbers.map { n in "\(n.number)[\(n.colors.sorted { $0.value > $1.value }.prefix(2).map { "\($0.key)\(Int($0.value * 100))" }.joined(separator: "+")) h\(n.heightRatio) x\(n.hits)]" }
        print((path as NSString).lastPathComponent, "\(Int(Date().timeIntervalSince(start) * 1000))ms", nums.joined(separator: " "), "|", a.texts.map(\.text).joined(separator: ","))
    }
case "roster":
    // cdu-cli roster <QID>
    let sem = DispatchSemaphore(value: 0)
    Task {
        do {
            let r = try await Wikidata.roster(teamQID: args[1])
            print(r.team.label, "|", r.team.category ?? "-", "|", r.source?.page ?? "-")
            for p in r.players { print(" ", p.number, p.name, p.qid ?? "-", "|", p.category ?? "-") }
        } catch { print("hata:", error.localizedDescription) }
        sem.signal()
    }
    sem.wait()
default:
    print("bilinmeyen komut"); exit(2)
}
