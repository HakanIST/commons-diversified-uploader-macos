import AppKit
import Foundation
import UploaderCore

// Geliştirme aracı. Kullanım: cdu-cli fixture <modelKlasörü> <png> <json>
let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { print("komutlar: fixture, analyze, roster, match"); exit(2) }

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
case "match":
    // cdu-cli match <fotoğrafKlasörü>: kayıtlı analizleri kadroyla eşleştirip özetler
    let project = try Project.load(folder: URL(fileURLWithPath: args[1]))
    for (name, record) in project.photos.sorted(by: { $0.key < $1.key }) {
        guard let analysis = record.analysis else { continue }
        let r = Matcher.match(analysis, teams: project.match.teams)
        print(name, r.players.map { "\($0.number) \($0.name)" }.joined(separator: ", "), r.unresolved.isEmpty ? "" : "| çözülemeyen: \(r.unresolved.map(\.number).joined(separator: ","))")
    }
case "stash":
    // cdu-cli stash <fotoğraf> <dosyaAdı>: kimlik bilgisini (JSON) standart girdiden okur, oturum açar ve dosyayı
    // yayımlamadan yalnızca geçici alana gönderir. Yükleme yolunu Commons'ta iz bırakmadan sınamak içindir.
    let input = FileHandle.standardInput.readDataToEndOfFile()
    let auth = try JSONDecoder().decode(CommonsAuth.self, from: input)
    if case .oauth(_, let tokens) = auth, tokens.needsRefresh { print("belirtecin süresi dolmak üzere; uygulamadan yeniden giriş yapın"); exit(3) }
    let sem = DispatchSemaphore(value: 0)
    Task {
        do {
            let client = CommonsClient(auth: auth)
            let name = try await client.login()
            print("oturum:", name.isEmpty ? "-" : "açıldı")
            let start = Date()
            let r = try await client.stashOnly(file: URL(fileURLWithPath: args[1]), filename: args[2])
            print("geçici alana gönderildi:", r.stashed, "| uyarılar:", r.warnings.isEmpty ? "yok" : r.warnings.joined(separator: ","), "| süre:", Int(Date().timeIntervalSince(start)), "sn")
        } catch { print("hata:", error.localizedDescription) }
        sem.signal()
    }
    sem.wait()
default:
    print("bilinmeyen komut"); exit(2)
}
