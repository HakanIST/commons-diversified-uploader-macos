import Foundation

public struct MatchedPlayer: Equatable, Identifiable, Sendable {
    public var team: String
    public var number: String
    public var name: String
    public var qid: String?
    public var category: String?
    public var box: NormalizedBox?
    public var confidence: Double?
    public var id: String { "\(team)-\(number)" }
}

public struct UnresolvedNumber: Equatable, Sendable {
    public var number: String
    public var box: NormalizedBox
    public var team: String?
}

public enum Matcher {
    /// Kare yüksekliğine oranla en küçük numara boyu.
    public static let minHeight = 0.018

    public static func normalize(_ s: String) -> String {
        let lowered = s.lowercased(with: Locale(identifier: "tr")).replacingOccurrences(of: "ı", with: "i")
        let folded = lowered.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en"))
        return String(folded.unicodeScalars.filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) })
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var prev = Array(0...b.count), cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            cur[0] = i
            for j in 1...max(b.count, 1) where !b.isEmpty {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return a.isEmpty ? b.count : prev[b.count]
    }

    public static func keywordHit(_ text: String, keywords: [String]) -> Bool {
        let t = normalize(text)
        guard t.count >= 4 else { return false }
        return keywords.contains { k in
            let n = normalize(k)
            guard n.count >= 4 else { return false }
            return t.contains(n) || (n.contains(t) && t.count >= n.count - 2) || editDistance(t, n) <= max(1, n.count / 3)
        }
    }

    private static func scores(_ det: NumberDetection, texts: [TextDetection], teams: [Team]) -> [Double] {
        let b = det.box, h = b.height
        return teams.map { team in
            let color = team.colors.reduce(0.0) { $0 + (det.colors[$1] ?? 0) }
            // Numaranın hemen üstünde/altında takım adı ya da sponsor yazısı var mı?
            let near = texts.contains { t in
                let overlapX = min(t.box.x1, b.x1 + h) - max(t.box.x0, b.x0 - h) > 0
                let dy = min(abs(t.box.y1 - b.y0), abs(t.box.y0 - b.y1))
                return overlapX && dy < h * 2.5 && keywordHit(t.text, keywords: team.keywords)
            }
            return color + (near ? 0.6 : 0)
        }
    }

    private static func sameNumber(_ a: String, _ b: String) -> Bool {
        a == b || (Int(a) != nil && Int(a) == Int(b) && !(a.hasPrefix("0") && a.count > 1) == !(b.hasPrefix("0") && b.count > 1))
    }

    public static func match(_ analysis: PhotoAnalysis, teams: [Team]) -> (players: [MatchedPlayer], unresolved: [UnresolvedNumber]) {
        var players: [MatchedPlayer] = [], unresolved: [UnresolvedNumber] = []
        for det in analysis.numbers where det.heightRatio >= minHeight {
            let s = scores(det, texts: analysis.texts, teams: teams)
            let order = s.indices.sorted { s[$0] > s[$1] }
            let inRoster = teams.map { team in team.players.first { sameNumber($0.number, det.number) } }
            var ti: Int?
            if let best = order.first, s[best] >= 0.4, order.count < 2 || s[best] - s[order[1]] >= 0.15 { ti = best }
            // Numara yalnızca bir takımın kadrosunda varsa ve renk karşı çıkmıyorsa onu seç.
            if ti == nil || inRoster[ti!] == nil {
                let only = inRoster.indices.filter { inRoster[$0] != nil }
                if only.count == 1, s[only[0]] >= 0.25, ti == nil || s[only[0]] >= s[ti!] - 0.1 { ti = only[0] }
            }
            guard let t = ti, let player = inRoster[t] else {
                unresolved.append(UnresolvedNumber(number: det.number, box: det.box, team: ti.map { teams[$0].key }))
                continue
            }
            let confidence = ((min(1, s[t]) * (det.hits > 1 ? 1 : 0.85)) * 100).rounded() / 100
            if let i = players.firstIndex(where: { $0.team == teams[t].key && $0.number == player.number }) {
                players[i].confidence = max(players[i].confidence ?? 0, confidence)
                continue
            }
            players.append(MatchedPlayer(team: teams[t].key, number: player.number, name: player.name, qid: player.qid, category: player.category, box: det.box, confidence: confidence))
        }
        players.sort { ($0.box?.height ?? 0) > ($1.box?.height ?? 0) }
        return (players, unresolved)
    }
}

public enum PageBuilder {
    /// Şablon alanları: {oyuncular} {numaralar} {maç} {sıra}
    public static func title(template: String, players: [MatchedPlayer], matchTitle: String, seq: Int, ext: String) -> String {
        let shown = players.prefix(3)
        var t = template
            .replacingOccurrences(of: "{oyuncular}", with: shown.map(\.name).joined(separator: ", "))
            .replacingOccurrences(of: "{numaralar}", with: shown.map(\.number).joined(separator: ", "))
            .replacingOccurrences(of: "{maç}", with: matchTitle)
            .replacingOccurrences(of: "{sıra}", with: String(seq))
        t = t.replacingOccurrences(of: "[#<>\\[\\]|{}:/\\\\]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\(\\s*\\)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "^[\\s\\-–,]+|[\\s\\-–,]+$", with: "", options: .regularExpression)
        return "\(t).\(ext)"
    }

    public static func describe(_ players: [MatchedPlayer], matchTitle: String, lang: String) -> String {
        let names = players.map(\.name)
        guard let last = names.last else { return matchTitle }
        let list = names.count > 1 ? "\(names.dropLast().joined(separator: ", ")) \(lang == "tr" ? "ve" : "and") \(last)" : last
        return matchTitle.isEmpty ? list : "\(list), \(matchTitle)"
    }

    public static func wikitext(descriptionTr: String, descriptionEn: String, date: String?, author: String, license: String, categories: [String]) -> String {
        var desc: [String] = []
        if !descriptionTr.isEmpty { desc.append("{{tr|1=\(descriptionTr)}}") }
        if !descriptionEn.isEmpty { desc.append("{{en|1=\(descriptionEn)}}") }
        var seen = Set<String>()
        let cats = categories.filter { !$0.isEmpty && seen.insert($0).inserted }.map { "[[Category:\($0)]]" }.joined(separator: "\n")
        return """
        =={{int:filedesc}}==
        {{Information
        |description=\(desc.joined(separator: "\n"))
        |date=\(date ?? "")
        |source={{own}}
        |author=\(author)
        }}

        =={{int:license-header}}==
        {{self|\(license)}}

        \(cats.isEmpty ? "{{subst:unc}}" : cats)

        """
    }
}
