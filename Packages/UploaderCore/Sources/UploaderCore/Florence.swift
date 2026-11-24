import CoreGraphics
import Foundation

/// Görüntüde okunan bir yazı ve piksel cinsinden sınır kutusu.
public struct TextRegion: Equatable, Sendable {
    public var text: String
    public var rect: CGRect
}

/// Florence-2 (base-ft) modelini ONNX Runtime ile çalıştırır: yazıları bölgeleriyle okur.
public final class FlorenceOCR {
    public static let modelFiles = ["onnx/vision_encoder.onnx", "onnx/embed_tokens.onnx", "onnx/encoder_model.onnx", "onnx/decoder_model_merged.onnx", "tokenizer.json"]
    public static let repository = "onnx-community/Florence-2-base-ft"

    static let inputSize = 768
    // "What is the text in the image, with regions?" isteminin belirteçleri (<OCR_WITH_REGION> görevi).
    static let promptIDs: [Int64] = [0, 2264, 16, 5, 2788, 11, 5, 2274, 6, 19, 3806, 116, 2]
    static let bos: Int64 = 0, eos: Int64 = 2, decoderStart: Int64 = 2
    static let layers = 6, heads = 12, headDim = 64, noRepeatNgram = 3

    private let vision, embed, encoder, decoder: OrtSession
    private let tokenizer: FlorenceTokenizer

    public init(modelDirectory: URL) throws {
        func path(_ f: String) -> String { modelDirectory.appendingPathComponent(f).path }
        vision = try OrtSession(path: path("onnx/vision_encoder.onnx"))
        embed = try OrtSession(path: path("onnx/embed_tokens.onnx"))
        encoder = try OrtSession(path: path("onnx/encoder_model.onnx"))
        decoder = try OrtSession(path: path("onnx/decoder_model_merged.onnx"))
        tokenizer = try FlorenceTokenizer(url: modelDirectory.appendingPathComponent("tokenizer.json"))
    }

    public static func isInstalled(at directory: URL) -> Bool {
        modelFiles.allSatisfy { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
    }

    /// - Parameter rgb: 768x768, satır sıralı RGB baytları.
    public func generate(rgb768: [UInt8], maxNewTokens: Int = 192) throws -> [Int64] {
        let n = Self.inputSize * Self.inputSize
        precondition(rgb768.count == n * 3)
        let mean: [Float] = [0.485, 0.456, 0.406], std: [Float] = [0.229, 0.224, 0.225]
        var pixels = [Float](repeating: 0, count: n * 3)
        for c in 0..<3 {
            let m = mean[c], s = std[c]
            for i in 0..<n { pixels[c * n + i] = (Float(rgb768[i * 3 + c]) / 255 - m) / s }
        }
        let image = try vision.run([("pixel_values", OrtTensor(floats: pixels, shape: [1, 3, Self.inputSize, Self.inputSize]))], outputs: ["image_features"])[0]
        let prompt = try embed.run([("input_ids", OrtTensor(int64s: Self.promptIDs, shape: [1, Self.promptIDs.count]))], outputs: ["inputs_embeds"])[0]
        let imageShape = image.shape, dim = imageShape[2]
        let seq = imageShape[1] + Self.promptIDs.count
        let merged = try image.floats() + prompt.floats()
        let mask = try OrtTensor(int64s: [Int64](repeating: 1, count: seq), shape: [1, seq])
        let hidden = try encoder.run([("attention_mask", mask), ("inputs_embeds", OrtTensor(floats: merged, shape: [1, seq, dim]))], outputs: ["last_hidden_state"])[0]

        var outputNames = ["logits"]
        for i in 0..<Self.layers { for part in ["decoder.key", "decoder.value", "encoder.key", "encoder.value"] { outputNames.append("present.\(i).\(part)") } }
        var past: [String: OrtTensor] = [:]
        for name in outputNames.dropFirst() {
            past[name.replacingOccurrences(of: "present", with: "past_key_values")] = try OrtTensor(floats: [], shape: [1, Self.heads, 0, Self.headDim])
        }
        var tokens: [Int64] = [Self.decoderStart]
        let yes = try OrtTensor(bool: true), no = try OrtTensor(bool: false)
        for step in 0..<maxNewTokens {
            let last = try embed.run([("input_ids", OrtTensor(int64s: [tokens.last!], shape: [1, 1]))], outputs: ["inputs_embeds"])[0]
            var inputs: [(String, OrtTensor)] = [("encoder_attention_mask", mask), ("encoder_hidden_states", hidden), ("inputs_embeds", last), ("use_cache_branch", step == 0 ? no : yes)]
            inputs.append(contentsOf: past.map { ($0.key, $0.value) })
            let out = try decoder.run(inputs, outputs: outputNames)
            for (i, name) in outputNames.enumerated().dropFirst() {
                // Kodlayıcı dikkat önbelleği yalnızca ilk adımda üretilir; sonraki adımlarda aynısı kullanılır.
                if step > 0 && name.contains(".encoder.") { continue }
                past[name.replacingOccurrences(of: "present", with: "past_key_values")] = out[i]
            }
            let next: Int64
            if step == 0 {
                next = Self.bos // forced_bos_token_id
            } else if step == maxNewTokens - 1 {
                next = Self.eos
            } else {
                let banned = Self.bannedTokens(tokens)
                next = try out[0].withFloats { logits in
                    let vocab = logits.count
                    var best = 0
                    var bestValue = -Float.infinity
                    for i in 0..<vocab where logits[i] > bestValue && !banned.contains(Int64(i)) {
                        best = i; bestValue = logits[i]
                    }
                    return Int64(best)
                }
            }
            tokens.append(next)
            if next == Self.eos { break }
        }
        return tokens
    }

    /// no_repeat_ngram_size: daha önce görülen bir üçlüyü tamamlayacak belirteçler yasaklanır.
    static func bannedTokens(_ tokens: [Int64]) -> Set<Int64> {
        let n = noRepeatNgram
        guard tokens.count >= n else { return [] }
        let prefix = Array(tokens.suffix(n - 1))
        var banned = Set<Int64>()
        for i in 0...(tokens.count - n) where Array(tokens[i..<(i + n - 1)]) == prefix {
            banned.insert(tokens[i + n - 1])
        }
        return banned
    }

    public func recognize(rgb768: [UInt8], imageSize: CGSize) throws -> [TextRegion] {
        tokenizer.parseRegions(try generate(rgb768: rgb768), imageSize: imageSize)
    }

    public func decode(_ tokens: [Int64]) -> String { tokenizer.decode(tokens, skipSpecial: false) }
}

/// tokenizer.json içinden yalnızca kod çözme için gerekenleri okur (bayt düzeyinde BPE).
final class FlorenceTokenizer {
    private var idToToken: [Int64: String] = [:]
    private var locValue: [Int64: Int] = [:]
    private var special = Set<Int64>()
    private static let byteDecoder: [Unicode.Scalar: UInt8] = {
        // GPT-2 bayt ↔ karakter eşlemesi
        var bs: [Int] = Array(33...126) + Array(161...172) + Array(174...255)
        var cs = bs
        var n = 0
        for b in 0..<256 where !bs.contains(b) {
            bs.append(b); cs.append(256 + n); n += 1
        }
        var map: [Unicode.Scalar: UInt8] = [:]
        for (b, c) in zip(bs, cs) { map[Unicode.Scalar(c)!] = UInt8(b) }
        return map
    }()

    init(url: URL) throws {
        guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
              let model = root["model"] as? [String: Any], let vocab = model["vocab"] as? [String: Int] else {
            throw OrtError(description: "tokenizer.json okunamadı")
        }
        for (token, id) in vocab { idToToken[Int64(id)] = token }
        for added in root["added_tokens"] as? [[String: Any]] ?? [] {
            guard let id = added["id"] as? Int, let content = added["content"] as? String else { continue }
            idToToken[Int64(id)] = content
            special.insert(Int64(id))
            if content.hasPrefix("<loc_"), let v = Int(content.dropFirst(5).dropLast()) { locValue[Int64(id)] = v }
        }
    }

    private func text(_ ids: [Int64]) -> String {
        var bytes: [UInt8] = []
        for id in ids {
            guard let token = idToToken[id] else { continue }
            if special.contains(id) { bytes.append(contentsOf: Array(token.utf8)); continue }
            for scalar in token.unicodeScalars {
                if let b = Self.byteDecoder[scalar] { bytes.append(b) } else { bytes.append(contentsOf: Array(String(scalar).utf8)) }
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    func decode(_ ids: [Int64], skipSpecial: Bool) -> String {
        text(skipSpecial ? ids.filter { !special.contains($0) } : ids)
    }

    /// "yazı<loc×8>yazı<loc×8>…" dizisini bölgelere ayırır; konumlar 0–999 aralığında nicemlenmiştir.
    func parseRegions(_ ids: [Int64], imageSize: CGSize) -> [TextRegion] {
        var regions: [TextRegion] = []
        var textIDs: [Int64] = [], locs: [Int] = []
        func flush() {
            defer { textIDs = []; locs = [] }
            guard locs.count == 8 else { return }
            let label = text(textIDs).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { return }
            let xs = stride(from: 0, to: 8, by: 2).map { (CGFloat(locs[$0]) + 0.5) / 1000 * imageSize.width }
            let ys = stride(from: 1, to: 8, by: 2).map { (CGFloat(locs[$0]) + 0.5) / 1000 * imageSize.height }
            regions.append(TextRegion(text: label, rect: CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)))
        }
        for id in ids {
            if let v = locValue[id] {
                locs.append(v)
                if locs.count == 8 { flush() }
            } else if special.contains(id) {
                continue
            } else {
                if !locs.isEmpty { locs = [] } // eksik kutu: at
                textIDs.append(id)
            }
        }
        return regions
    }
}
