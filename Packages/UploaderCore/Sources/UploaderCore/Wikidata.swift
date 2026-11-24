import Foundation

public struct WikidataHit: Identifiable, Equatable, Sendable {
    public var qid: String
    public var label: String
    public var description: String
    public var category: String?
    public var id: String { qid }
}

public struct TeamInfo: Sendable {
    public var qid: String
    public var label: String
    public var category: String?
    public var articles: [String: String]
}

/// Takım arama, Vikipedi kadro şablonundan numara → oyuncu tablosu, oyuncuların Commons kategorileri.
public enum Wikidata {
    static let api = "https://www.wikidata.org/w/api.php"
    static func wiki(_ lang: String) -> String { "https://\(lang).wikipedia.org/w/api.php" }

    public static func search(_ query: String, lang: String = "tr") async throws -> [WikidataHit] {
        let d = try await HTTP.getJSON(api, ["action": "wbsearchentities", "search": query, "language": lang, "uselang": lang, "type": "item", "limit": "10", "format": "json"])
        return (d["search"] as? [[String: Any]] ?? []).compactMap { r in
            guard let id = r["id"] as? String else { return nil }
            return WikidataHit(qid: id, label: r["label"] as? String ?? id, description: r["description"] as? String ?? "")
        }
    }

    static func entities(_ qids: [String]) async throws -> [String: [String: Any]] {
        var out: [String: [String: Any]] = [:]
        let unique = Array(Set(qids)).sorted()
        for start in stride(from: 0, to: unique.count, by: 50) {
            let part = unique[start..<min(start + 50, unique.count)]
            let d = try await HTTP.getJSON(api, ["action": "wbgetentities", "ids": part.joined(separator: "|"), "props": "labels|claims|sitelinks", "languages": "tr|en", "format": "json"])
            for (k, v) in d["entities"] as? [String: [String: Any]] ?? [:] { out[k] = v }
        }
        return out
    }

    static func claimValues(_ entity: [String: Any], _ property: String) -> [Any] {
        ((entity["claims"] as? [String: Any])?[property] as? [[String: Any]] ?? []).compactMap {
            (($0["mainsnak"] as? [String: Any])?["datavalue"] as? [String: Any])?["value"]
        }
    }

    static func commonsCategory(_ entity: [String: Any]) -> String? {
        if let p373 = claimValues(entity, "P373").first as? String { return p373 }
        let title = ((entity["sitelinks"] as? [String: Any])?["commonswiki"] as? [String: Any])?["title"] as? String
        return title.flatMap { $0.hasPrefix("Category:") ? String($0.dropFirst(9)) : nil }
    }

    static func label(_ entity: [String: Any]) -> String? {
        let labels = entity["labels"] as? [String: [String: Any]]
        return (labels?["tr"]?["value"] ?? labels?["en"]?["value"]) as? String
    }

    static func isHuman(_ entity: [String: Any]) -> Bool {
        claimValues(entity, "P31").contains { ($0 as? [String: Any])?["id"] as? String == "Q5" }
    }

    public static func team(_ qid: String) async throws -> TeamInfo {
        guard let e = try await entities([qid])[qid], e["missing"] == nil else { throw HTTP.Failure(message: L("Wikidata ögesi bulunamadı: \(qid)")) }
        let links = e["sitelinks"] as? [String: [String: Any]] ?? [:]
        var articles: [String: String] = [:]
        for lang in ["tr", "en"] { if let t = links["\(lang)wiki"]?["title"] as? String { articles[lang] = t } }
        return TeamInfo(qid: qid, label: label(e) ?? qid, category: commonsCategory(e), articles: articles)
    }

    struct RosterEntry: Equatable { var number: String; var name: String; var title: String? }

    /// Kadro şablonu vikimetninden numara, ad ve madde başlığı çıkarır.
    static func parseRoster(_ wikitext: String) -> [RosterEntry] {
        var players: [String: RosterEntry] = [:]
        func add(_ number: String, _ name: String, _ title: String?) {
            let number = number.trimmingCharacters(in: .whitespaces)
            guard (1...2).contains(number.count), number.allSatisfy({ $0.isASCII && $0.isNumber }) else { return }
            let name = name.replacingOccurrences(of: "'''?|<[^>]+>", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            let title = title?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            if let prev = players[number], name.count <= prev.name.count {
                if prev.title == nil { players[number]?.title = title }
            } else {
                // Tam adı taşıyan (şablon satırı) kaydı, kısa etiketli liste satırına tercih et.
                players[number] = RosterEntry(number: number, name: name.nilIfEmpty ?? players[number]?.name ?? title ?? "", title: title ?? players[number]?.title)
            }
        }
        let ns = wikitext as NSString
        // {{TBL oyuncu | num = 5 | ilk = Sertaç | son = Şanlı}} ve {{player2 | num | first | last | dab}}
        let tpl = try! NSRegularExpression(pattern: "\\{\\{\\s*(?:TBL oyuncu|[Pp]layer\\d?|[Bb]asketball player\\d?)\\s*\\|([^{}]*)\\}\\}")
        for m in tpl.matches(in: wikitext, range: NSRange(location: 0, length: ns.length)) {
            var f: [String: String] = [:]
            for part in ns.substring(with: m.range(at: 1)).split(separator: "|", omittingEmptySubsequences: false) {
                guard let eq = part.firstIndex(of: "=") else { continue }
                f[part[..<eq].trimmingCharacters(in: .whitespaces).lowercased()] = part[part.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            }
            let full = "\(f["ilk"] ?? f["first"] ?? "") \(f["son"] ?? f["last"] ?? "")".trimmingCharacters(in: .whitespaces)
            let name = full.nilIfEmpty ?? f["name"] ?? f["ad"] ?? ""
            let link = (f["bağlantı"] ?? f["link"])?.nilIfEmpty
            let title = link ?? (f["dab"]?.nilIfEmpty).map { "\(name) (\($0))" } ?? name
            add(f["num"] ?? f["no"] ?? "", name, title)
        }
        // "* 31 [[Shavon Shields|Shields]]"
        let line = try! NSRegularExpression(pattern: "^\\*\\s*(\\d{1,2})\\s+\\[\\[([^\\]|]+)(?:\\|[^\\]]*)?\\]\\]", options: .anchorsMatchLines)
        for m in line.matches(in: wikitext, range: NSRange(location: 0, length: ns.length)) {
            add(ns.substring(with: m.range(at: 1)), ns.substring(with: m.range(at: 2)), ns.substring(with: m.range(at: 2)))
        }
        return players.values.sorted { (Int($0.number) ?? 0, $0.number) < (Int($1.number) ?? 0, $1.number) }
    }

    static func pages(_ d: [String: Any]) -> [[String: Any]] { (d["query"] as? [String: Any])?["pages"] as? [[String: Any]] ?? [] }

    static func rosterTemplate(lang: String, article: String) async throws -> String? {
        let d = try await HTTP.getJSON(wiki(lang), ["action": "query", "prop": "templates", "titles": article, "tlnamespace": "10", "tllimit": "max", "redirects": "1", "format": "json", "formatversion": "2"])
        let names = (pages(d).first?["templates"] as? [[String: Any]] ?? []).compactMap { $0["title"] as? String }
        let needle = lang == "tr" ? "kadro" : "roster"
        let base = article.replacingOccurrences(of: "\\s*\\(.*\\)$", with: "", options: .regularExpression).split(separator: " ").first.map { $0.lowercased() } ?? ""
        return names.first { $0.lowercased().contains(needle) && $0.lowercased().contains(base) }
    }

    static func wikitext(lang: String, title: String) async throws -> String {
        let d = try await HTTP.getJSON(wiki(lang), ["action": "query", "prop": "revisions", "rvprop": "content", "rvslots": "main", "titles": title, "redirects": "1", "format": "json", "formatversion": "2"])
        let rev = (pages(d).first?["revisions"] as? [[String: Any]])?.first
        return ((rev?["slots"] as? [String: Any])?["main"] as? [String: Any])?["content"] as? String ?? ""
    }

    static func qids(lang: String, titles: [String]) async throws -> [String: String] {
        var map: [String: String] = [:]
        let unique = Array(Set(titles)).sorted()
        for start in stride(from: 0, to: unique.count, by: 50) {
            let part = unique[start..<min(start + 50, unique.count)]
            let d = try await HTTP.getJSON(wiki(lang), ["action": "query", "prop": "pageprops", "ppprop": "wikibase_item", "titles": part.joined(separator: "|"), "redirects": "1", "format": "json", "formatversion": "2"])
            let q = d["query"] as? [String: Any] ?? [:]
            var alias: [String: String] = [:]
            for n in q["normalized"] as? [[String: String]] ?? [] { if let to = n["to"], let from = n["from"] { alias[to] = from } }
            for r in q["redirects"] as? [[String: Any]] ?? [] {
                if let to = r["to"] as? String, let from = r["from"] as? String { alias[to] = alias[from] ?? from }
            }
            for p in q["pages"] as? [[String: Any]] ?? [] {
                guard let title = p["title"] as? String, let qid = (p["pageprops"] as? [String: Any])?["wikibase_item"] as? String else { continue }
                map[title] = qid
                if let a = alias[title] { map[a] = qid }
            }
        }
        return map
    }

    /// Bir takımın güncel kadrosu: numara, ad, Wikidata ögesi ve Commons kategorisi.
    public static func roster(teamQID: String) async throws -> (team: TeamInfo, players: [Player], source: RosterSource?) {
        let info = try await team(teamQID)
        var entries: [RosterEntry] = [], source: RosterSource?
        for lang in ["tr", "en"] {
            guard let article = info.articles[lang] else { continue }
            let page = try await rosterTemplate(lang: lang, article: article) ?? article
            let parsed = parseRoster(try await wikitext(lang: lang, title: page))
            if parsed.count > entries.count { entries = parsed; source = RosterSource(lang: lang, page: page) }
            if entries.count >= 8 { break }
        }
        var players = entries.map { Player(number: $0.number, name: $0.name) }
        if let source, !entries.isEmpty {
            let map = try await qids(lang: source.lang, titles: entries.compactMap(\.title))
            let ents = try await entities(entries.compactMap { $0.title.flatMap { map[$0] } })
            for (i, entry) in entries.enumerated() {
                // Anlam ayrımı ya da başka bir şeye giden bağlantıları ele.
                guard let title = entry.title, let qid = map[title], let e = ents[qid], isHuman(e) else { continue }
                players[i].qid = qid
                players[i].category = commonsCategory(e)
            }
        }
        return (info, players, source)
    }

    /// Elle girilen bir oyuncu adı için kişi araması.
    public static func searchPeople(_ query: String) async throws -> [WikidataHit] {
        let hits = try await search(query)
        guard !hits.isEmpty else { return [] }
        let ents = try await entities(hits.map(\.qid))
        return hits.compactMap { h in
            guard let e = ents[h.qid], isHuman(e) else { return nil }
            var h = h
            h.category = commonsCategory(e)
            return h
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
