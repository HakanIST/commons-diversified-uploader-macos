import AppKit
import Security
import SwiftUI
import UploaderCore

enum Step: String, CaseIterable, Identifiable {
    case match, roster, photos, upload
    var id: String { rawValue }
    var title: String {
        switch self { case .match: "Maç"; case .roster: "Kadrolar"; case .photos: "Fotoğraflar"; case .upload: "Yükleme" }
    }
    var icon: String {
        switch self { case .match: "sportscourt"; case .roster: "person.3"; case .photos: "photo.on.rectangle.angled"; case .upload: "arrow.up.circle" }
    }
}

enum PhotoFilter: String, CaseIterable, Identifiable {
    case all, found, unresolved, none, pending
    var id: String { rawValue }
    var title: String {
        switch self { case .all: "Tümü"; case .found: "Oyuncu bulundu"; case .unresolved: "Çözülemeyen numara"; case .none: "Oyuncu yok"; case .pending: "Analiz edilmedi" }
    }
    func matches(_ r: PhotoRow) -> Bool {
        switch self {
        case .all: true
        case .found: !r.players.isEmpty
        case .unresolved: !r.unresolved.isEmpty
        case .none: r.analyzed && r.players.isEmpty
        case .pending: !r.analyzed
        }
    }
}

/// Bir fotoğrafın arayüzde gösterilen, hesaplanmış hâli.
struct PhotoRow: Identifiable, Equatable {
    var name: String
    var include: Bool
    var analyzed: Bool
    var date: String?
    var players: [MatchedPlayer]
    var unresolved: [UnresolvedNumber]
    var manual: Bool
    var title: String
    var customTitle: Bool
    var categories: [String]
    var uploaded: UploadResult?
    var uploadError: String?
    var error: String?
    var id: String { name }
}

struct ActivityState: Equatable {
    enum Kind { case analysis, upload, download }
    var kind: Kind
    var message: String
    var fraction: Double?
}

struct UploadCheck {
    var missingCategories: [String]
    var takenTitles: [String]
}

@MainActor
final class AppModel: ObservableObject {
    @Published var folder: URL?
    @Published var project = Project() { didSet { if project != oldValue { rebuildRows(); scheduleSave() } } }
    @Published private(set) var rows: [PhotoRow] = []
    @Published var step: Step = .match
    @Published var filter: PhotoFilter = .all
    @Published var selection: String?
    @Published var activity: ActivityState?
    @Published var username: String?
    @Published var alert: String?
    @Published var check: UploadCheck?

    private var commons: CommonsClient?
    private var task: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var scopedFolder: URL?
    private var ocr: FlorenceOCR?

    var selectedRow: PhotoRow? { rows.first { $0.name == selection } }
    var filteredRows: [PhotoRow] { rows.filter(filter.matches) }
    var pendingCount: Int { rows.filter { !$0.analyzed }.count }
    var readyRows: [PhotoRow] { rows.filter { $0.include && $0.uploaded == nil } }
    var isBusy: Bool { activity != nil }

    // MARK: Klasör

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Seç"
        panel.message = "Maç fotoğraflarının bulunduğu klasörü seçin"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let data = try? url.bookmarkData(options: .withSecurityScope) { UserDefaults.standard.set(data, forKey: "folderBookmark") }
        open(url)
    }

    func restore() async {
        if let path = ProcessInfo.processInfo.environment["CDU_FOLDER"] {
            open(URL(fileURLWithPath: path))
        } else if let data = UserDefaults.standard.data(forKey: "folderBookmark") {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale) { open(url) }
        }
        if let step = ProcessInfo.processInfo.environment["CDU_STEP"].flatMap(Step.init) { self.step = step }
        #if DEBUG
        if let list = ProcessInfo.processInfo.environment["CDU_ANALYZE"] {
            let names = list.split(separator: ",").map(String.init)
            selection = names.last
            startAnalysis(only: names)
        }
        if let sel = ProcessInfo.processInfo.environment["CDU_SELECT"] { selection = sel; filter = .found }
        #endif
        if let auth = Keychain.load() {
            let client = CommonsClient(auth: auth)
            if let name = try? await client.login() { commons = client; username = name }
        }
    }

    private func open(_ url: URL) {
        scopedFolder?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        scopedFolder = url
        do {
            var p = try Project.load(folder: url)
            p.sync(fileNames: Project.imageFiles(in: url))
            folder = url
            project = p
            selection = rows.first?.name
            check = nil
        } catch {
            alert = "Proje dosyası okunamadı: \(error.localizedDescription)"
        }
    }

    func url(for name: String) -> URL? { folder?.appendingPathComponent(name) }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled, let self, let folder = self.folder else { return }
            do { try self.project.save(folder: folder) } catch { self.alert = "Proje kaydedilemedi: \(error.localizedDescription)" }
        }
    }

    // MARK: Hesaplanan satırlar

    private func players(for record: PhotoRecord) -> [MatchedPlayer] {
        let teams = project.match.teams
        if let manual = record.manual {
            return manual.compactMap { m in
                guard let team = teams.first(where: { $0.key == m.team }), let p = team.players.first(where: { $0.number == m.number }) else { return nil }
                return MatchedPlayer(team: m.team, number: p.number, name: p.name, qid: p.qid, category: p.category)
            }
        }
        return record.analysis.map { Matcher.match($0, teams: teams).players } ?? []
    }

    var baseCategories: [String] {
        let m = project.match
        let base = m.category.isEmpty ? m.teams.map(\.category).filter { !$0.isEmpty } : [m.category]
        return base + m.extraCategories
    }

    private func rebuildRows() {
        let m = project.match
        let base = baseCategories
        // Maç başlığı girilmediyse dosya adları klasör adından türetilir.
        let matchTitle = m.title.isEmpty ? (folder?.lastPathComponent ?? "") : m.title
        rows = project.photos.keys.sorted().enumerated().map { index, name in
            let record = project.photos[name]!
            let players = players(for: record)
            let unresolved = record.manual == nil ? (record.analysis.map { Matcher.match($0, teams: m.teams).unresolved } ?? []) : []
            let ext = (name as NSString).pathExtension.lowercased()
            let title = record.title ?? PageBuilder.title(template: m.titleTemplate, players: players, matchTitle: matchTitle, seq: index + 1, ext: ext)
            var seen = Set<String>()
            let categories = (players.compactMap(\.category) + base).filter { !$0.isEmpty && seen.insert($0).inserted }
            return PhotoRow(name: name, include: record.include, analyzed: record.analysis != nil, date: record.date, players: players, unresolved: unresolved,
                            manual: record.manual != nil, title: title, customTitle: record.title != nil, categories: categories,
                            uploaded: record.uploaded, uploadError: record.uploadError, error: record.error)
        }
    }

    func wikitext(for row: PhotoRow) -> String {
        let m = project.match
        let user = username ?? "Kullanıcı"
        return PageBuilder.wikitext(descriptionTr: PageBuilder.describe(row.players, matchTitle: m.title, lang: "tr"),
                                    descriptionEn: PageBuilder.describe(row.players, matchTitle: m.title, lang: "en"),
                                    date: row.date, author: m.author.isEmpty ? "[[User:\(user)|\(user)]]" : m.author, license: m.license, categories: row.categories)
    }

    // MARK: Takımlar

    func teamIndex(_ key: String) -> Int { project.match.teams.firstIndex { $0.key == key } ?? 0 }

    func setTeam(_ key: String, qid: String) async {
        do {
            let r = try await Wikidata.roster(teamQID: qid)
            let i = teamIndex(key)
            var team = project.match.teams[i]
            let short = r.team.label.replacingOccurrences(of: "\\s*\\(.*\\)$", with: "", options: .regularExpression)
            team.qid = qid; team.label = short; team.category = r.team.category ?? ""
            team.players = r.players; team.rosterSource = r.source
            if team.keywords.isEmpty { team.keywords = [short] }
            project.match.teams[i] = team
        } catch {
            alert = "Kadro getirilemedi: \(error.localizedDescription)"
        }
    }

    // MARK: Analiz

    func startAnalysis(only: [String]? = nil) {
        guard !isBusy, let folder else { return }
        let names = rows.filter { only?.contains($0.name) ?? !$0.analyzed }.map(\.name)
        guard !names.isEmpty else { return }
        activity = ActivityState(kind: .download, message: "Model hazırlanıyor…", fraction: nil)
        task = Task {
            do {
                let dir = ProcessInfo.processInfo.environment["CDU_MODEL_DIR"].map { URL(fileURLWithPath: $0) } ?? ModelStore.defaultDirectory
                if !FlorenceOCR.isInstalled(at: dir) {
                    try await ModelStore.ensure(at: dir) { fraction, file in
                        Task { @MainActor in self.activity = ActivityState(kind: .download, message: "Model indiriliyor (yaklaşık 1 GB): \(file)", fraction: fraction) }
                    }
                }
                if ocr == nil {
                    activity = ActivityState(kind: .analysis, message: "Model yükleniyor…", fraction: nil)
                    ocr = try await Task.detached { try FlorenceOCR(modelDirectory: dir) }.value
                }
                let analyzer = ImageAnalyzer(ocr: ocr!)
                for (i, name) in names.enumerated() {
                    if Task.isCancelled { break }
                    activity = ActivityState(kind: .analysis, message: "\(name) (\(i + 1)/\(names.count))", fraction: Double(i) / Double(names.count))
                    let url = folder.appendingPathComponent(name)
                    let result = await Task.detached { () -> Result<(PhotoAnalysis, String?), Error> in
                        Result { (try analyzer.analyze(url), ImageLoader.captureDate(url)) }
                    }.value
                    switch result {
                    case .success(let (analysis, date)):
                        project.photos[name]?.analysis = analysis
                        project.photos[name]?.date = date
                        project.photos[name]?.error = nil
                    case .failure(let error):
                        project.photos[name]?.error = error.localizedDescription
                    }
                }
            } catch {
                alert = "Analiz başlatılamadı: \(error.localizedDescription)"
            }
            activity = nil
        }
    }

    func cancel() { task?.cancel() }

    // MARK: Commons

    func login(_ auth: CommonsAuth) async {
        let client = CommonsClient(auth: auth)
        do {
            username = try await client.login()
            commons = client
            Keychain.save(auth)
        } catch {
            alert = error.localizedDescription
        }
    }

    func logout() {
        commons = nil; username = nil
        Keychain.clear()
    }

    func runCheck() async {
        let client = commons ?? CommonsClient(auth: nil)
        let ready = readyRows
        var seen = Set<String>()
        let cats = ready.flatMap(\.categories).filter { seen.insert($0).inserted }
        do {
            let ex = try await client.existing(cats.map { "Category:\($0)" } + ready.map { "File:\($0.title)" })
            check = UploadCheck(missingCategories: cats.filter { ex["Category:\($0)"] != true }, takenTitles: ready.map(\.title).filter { ex["File:\($0)"] == true })
        } catch {
            alert = "Denetim yapılamadı: \(error.localizedDescription)"
        }
    }

    func startUpload() {
        guard !isBusy, let commons, let folder else { return }
        let list = readyRows
        let match = project.match
        activity = ActivityState(kind: .upload, message: "Yükleme başlıyor…", fraction: 0)
        task = Task {
            do {
                if match.createCategory, !match.category.isEmpty, try await commons.existing(["Category:\(match.category)"])["Category:\(match.category)"] != true {
                    let parents = match.teams.map(\.category).filter { !$0.isEmpty }.map { "[[Category:\($0)]]" }.joined(separator: "\n")
                    try await commons.createCategory(match.category, text: parents + "\n")
                }
            } catch {
                alert = "Maç kategorisi oluşturulamadı: \(error.localizedDescription)"
            }
            for (i, row) in list.enumerated() {
                if Task.isCancelled { break }
                let total = Double(list.count)
                activity = ActivityState(kind: .upload, message: "\(row.title) (\(i + 1)/\(list.count))", fraction: Double(i) / total)
                do {
                    let outcome = try await commons.upload(file: folder.appendingPathComponent(row.name), filename: row.title, text: wikitext(for: row), comment: "Commons Diversified Uploader ile yüklendi") { fraction in
                        Task { @MainActor in self.activity = ActivityState(kind: .upload, message: "\(row.title) (\(i + 1)/\(list.count))", fraction: (Double(i) + fraction) / total) }
                    }
                    switch outcome {
                    case .success(let title, let pageID, let url):
                        project.photos[row.name]?.uploaded = UploadResult(title: title, url: url)
                        project.photos[row.name]?.uploadError = nil
                        if let pageID {
                            do { try await commons.addDepicts(pageID: pageID, qids: row.players.compactMap(\.qid)) } catch {
                                project.photos[row.name]?.uploadError = "Yüklendi, ancak görünen kişiler eklenemedi: \(error.localizedDescription)"
                            }
                        }
                    case .blocked(let reason):
                        project.photos[row.name]?.uploadError = reason
                    }
                } catch is CancellationError {
                    break
                } catch {
                    project.photos[row.name]?.uploadError = error.localizedDescription
                }
            }
            activity = nil
        }
    }
}

enum Keychain {
    private static let service = "tr.tall.CommonsDiversifiedUploader.commons"

    static func save(_ auth: CommonsAuth) {
        guard let data = try? JSONEncoder().encode(auth) else { return }
        clear()
        SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "auth", kSecValueData: data] as CFDictionary, nil)
    }

    static func load() -> CommonsAuth? {
        var out: CFTypeRef?
        let q = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "auth", kSecReturnData: true] as CFDictionary
        guard SecItemCopyMatching(q, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(CommonsAuth.self, from: data)
    }

    static func clear() {
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "auth"] as CFDictionary)
    }
}

/// Küçük resimleri arka planda üretir ve bellekte tutar.
@MainActor
final class Thumbnails: ObservableObject {
    static let shared = Thumbnails()
    private let cache = NSCache<NSURL, NSImage>()

    func image(for url: URL, maxPixel: Int) async -> NSImage? {
        let key = url.appendingPathExtension("\(maxPixel)") as NSURL
        if let hit = cache.object(forKey: key) { return hit }
        let image = await Task.detached(priority: .utility) { () -> NSImage? in
            guard let cg = ImageLoader.load(url, maxPixel: maxPixel) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}

struct Thumbnail: View {
    let url: URL?
    var maxPixel = 480
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image { Image(nsImage: image).resizable().scaledToFill() } else { ProgressView().controlSize(.small) }
        }
        .task(id: url) {
            guard let url else { return }
            image = await Thumbnails.shared.image(for: url, maxPixel: maxPixel)
        }
    }
}
