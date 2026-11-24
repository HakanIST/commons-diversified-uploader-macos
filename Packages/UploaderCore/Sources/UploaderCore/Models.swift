import CoreGraphics
import Foundation

/// 0…1 aralığında, görüntü boyutuna oranlı kutu (sol üst köşe başlangıç).
public struct NormalizedBox: Codable, Equatable, Sendable {
    public var x0, y0, x1, y1: Double
    public init(x0: Double, y0: Double, x1: Double, y1: Double) { self.x0 = x0; self.y0 = y0; self.x1 = x1; self.y1 = y1 }
    public var width: Double { x1 - x0 }
    public var height: Double { y1 - y0 }
}

public struct NumberDetection: Codable, Equatable, Sendable {
    public var number: String
    public var box: NormalizedBox
    public var hits: Int
    public var heightRatio: Double
    /// Numara çevresindeki (forma gövdesi) renk adlarının payı.
    public var colors: [String: Double]
    public init(number: String, box: NormalizedBox, hits: Int, heightRatio: Double, colors: [String: Double]) {
        self.number = number; self.box = box; self.hits = hits; self.heightRatio = heightRatio; self.colors = colors
    }
}

public struct TextDetection: Codable, Equatable, Sendable {
    public var text: String
    public var box: NormalizedBox
    public init(text: String, box: NormalizedBox) { self.text = text; self.box = box }
}

public struct PhotoAnalysis: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var numbers: [NumberDetection]
    public var texts: [TextDetection]
    public init(width: Int, height: Int, numbers: [NumberDetection], texts: [TextDetection]) {
        self.width = width; self.height = height; self.numbers = numbers; self.texts = texts
    }
}

public struct Player: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var number: String
    public var name: String
    public var qid: String?
    public var category: String?
    public init(number: String, name: String, qid: String? = nil, category: String? = nil) {
        self.number = number; self.name = name; self.qid = qid; self.category = category
    }
    enum CodingKeys: String, CodingKey { case number, name, qid, category }
}

public struct RosterSource: Codable, Equatable, Sendable {
    public var lang: String
    public var page: String
    public init(lang: String, page: String) { self.lang = lang; self.page = page }
}

public struct Team: Codable, Equatable, Identifiable, Sendable {
    public var key: String
    public var qid: String?
    public var label = ""
    public var category = ""
    public var colors: [String] = []
    public var keywords: [String] = []
    public var players: [Player] = []
    public var rosterSource: RosterSource?
    public var id: String { key }
    public init(key: String) { self.key = key }
}

public struct MatchInfo: Codable, Equatable, Sendable {
    public var title = ""
    public var category = ""
    public var createCategory = false
    public var extraCategories: [String] = []
    public var author = ""
    public var license = "cc-by-sa-4.0"
    public var titleTemplate = MatchInfo.defaultTitleTemplate
    /// Yeni projelerde arayüz diline göre Türkçe ya da İngilizce alan adları kullanılır; ikisi de her zaman geçerlidir.
    public static var defaultTitleTemplate: String {
        Bundle.main.preferredLocalizations.first == "tr" ? "{oyuncular} {numaralar} - {maç} ({sıra})" : "{players} {numbers} - {match} ({n})"
    }
    public var teams: [Team] = [Team(key: "a"), Team(key: "b")]
    public init() {}
}

public struct ManualPlayer: Codable, Equatable, Sendable {
    public var team: String
    public var number: String
    public init(team: String, number: String) { self.team = team; self.number = number }
}

public struct UploadResult: Codable, Equatable, Sendable {
    public var title: String
    public var url: String?
    public init(title: String, url: String?) { self.title = title; self.url = url }
}

public struct PhotoRecord: Codable, Equatable, Sendable {
    public var include = true
    public var date: String?
    public var analysis: PhotoAnalysis?
    public var manual: [ManualPlayer]?
    public var title: String?
    public var uploaded: UploadResult?
    public var uploadError: String?
    public var error: String?
    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        include = try c.decodeIfPresent(Bool.self, forKey: .include) ?? true
        date = try c.decodeIfPresent(String.self, forKey: .date)
        analysis = try c.decodeIfPresent(PhotoAnalysis.self, forKey: .analysis)
        manual = try c.decodeIfPresent([ManualPlayer].self, forKey: .manual)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        uploaded = try c.decodeIfPresent(UploadResult.self, forKey: .uploaded)
        uploadError = try c.decodeIfPresent(String.self, forKey: .uploadError)
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }
}

/// Fotoğraf klasöründe saklanan proje dosyası (commons-yukleme.json).
public struct Project: Codable, Equatable, Sendable {
    public static let fileName = "commons-yukleme.json"
    public var match = MatchInfo()
    public var photos: [String: PhotoRecord] = [:]
    public init() {}

    public static func load(folder: URL) throws -> Project {
        let url = folder.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return Project() }
        return try JSONDecoder().decode(Project.self, from: Data(contentsOf: url))
    }

    public func save(folder: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: folder.appendingPathComponent(Self.fileName), options: .atomic)
    }

    /// Klasördeki görüntülerle kayıtları eşitler.
    public mutating func sync(fileNames: [String]) {
        for name in fileNames where photos[name] == nil { photos[name] = PhotoRecord() }
        for name in photos.keys where !fileNames.contains(name) { photos[name] = nil }
    }

    public static func imageFiles(in folder: URL) -> [String] {
        let exts: Set<String> = ["jpg", "jpeg", "png", "tif", "tiff"]
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { !$0.hasPrefix(".") && exts.contains(($0 as NSString).pathExtension.lowercased()) }.sorted()
    }
}
