import XCTest
@testable import UploaderCore

final class CoreTests: XCTestCase {
    private var teams: [Team] {
        var a = Team(key: "a")
        a.label = "Fenerbahçe"; a.colors = ["sarı", "lacivert"]; a.keywords = ["Fenerbahçe", "tarfin"]
        a.players = [Player(number: "31", name: "Shavon Shields", qid: "Q1", category: "Shavon Shields"), Player(number: "4", name: "Nicolò Melli", category: "Nicolò Melli")]
        var b = Team(key: "b")
        b.label = "Beşiktaş"; b.colors = ["siyah"]; b.keywords = ["Beşiktaş", "fuzul"]
        b.players = [Player(number: "41", name: "Ante Žižić", category: "Ante Žižić"), Player(number: "4", name: "Lonnie Walker IV", category: "Lonnie Walker")]
        return [a, b]
    }

    private func det(_ number: String, y: Double = 0.5, h: Double = 0.06, hits: Int = 2, _ colors: [String: Double]) -> NumberDetection {
        NumberDetection(number: number, box: NormalizedBox(x0: 0.4, y0: y, x1: 0.46, y1: y + h), hits: hits, heightRatio: h, colors: colors)
    }

    func testColorPicksTeamAndNumberPicksPlayer() {
        let a = PhotoAnalysis(width: 3000, height: 2000, numbers: [det("31", ["lacivert": 0.39, "sarı": 0.33, "beyaz": 0.2]), det("41", y: 0.2, ["siyah": 0.65, "beyaz": 0.28])], texts: [])
        XCTAssertEqual(Matcher.match(a, teams: teams).players.map(\.name).sorted(), ["Ante Žižić", "Shavon Shields"])
    }

    func testSameNumberOnBothTeamsIsSplitByColor() {
        let a = PhotoAnalysis(width: 3000, height: 2000, numbers: [det("4", ["siyah": 0.64, "beyaz": 0.32])], texts: [])
        XCTAssertEqual(Matcher.match(a, teams: teams).players.first?.name, "Lonnie Walker IV")
    }

    func testTinyAndUnknownNumbersAreDropped() {
        let a = PhotoAnalysis(width: 3000, height: 2000, numbers: [det("0", h: 0.0006, ["turuncu": 1]), det("50", ["siyah": 0.7])], texts: [])
        let r = Matcher.match(a, teams: teams)
        XCTAssertTrue(r.players.isEmpty)
        XCTAssertEqual(r.unresolved.map(\.number), ["50"])
    }

    func testJerseyTextDecidesWhenColorIsUnclear() {
        let a = PhotoAnalysis(width: 3000, height: 2000, numbers: [det("41", hits: 1, ["gri": 0.6, "siyah": 0.2])],
                              texts: [TextDetection(text: "BESIKTAS", box: NormalizedBox(x0: 0.38, y0: 0.42, x1: 0.5, y1: 0.47))])
        XCTAssertEqual(Matcher.match(a, teams: teams).players.first?.name, "Ante Žižić")
    }

    func testKeywordMatchingToleratesOCRErrors() {
        XCTAssertTrue(Matcher.keywordHit("BESKTAR", keywords: ["Beşiktaş"]))
        XCTAssertTrue(Matcher.keywordHit("TARfin", keywords: ["tarfin"]))
        XCTAssertFalse(Matcher.keywordHit("umbro", keywords: ["Beşiktaş", "fuzul"]))
    }

    func testTitleAndWikitext() {
        let players = [MatchedPlayer(team: "a", number: "31", name: "Shavon Shields")]
        let template = "{oyuncular} {numaralar} - {maç} ({sıra})"
        XCTAssertEqual(PageBuilder.title(template: template, players: players, matchTitle: "Beşiktaş vs Fenerbahçe 20261122", seq: 7, ext: "jpg"), "Shavon Shields 31 - Beşiktaş vs Fenerbahçe 20261122 (7).jpg")
        XCTAssertEqual(PageBuilder.title(template: template, players: [], matchTitle: "A vs B", seq: 2, ext: "jpg"), "A vs B (2).jpg")
        let w = PageBuilder.wikitext(descriptionTr: PageBuilder.describe(players, matchTitle: "maç", lang: "tr"), descriptionEn: "", date: "2026-11-22 20:28:30", author: "[[User:X|X]]", license: "cc-by-sa-4.0", categories: ["Shavon Shields", "Shavon Shields", "M"])
        XCTAssertTrue(w.contains("{{self|cc-by-sa-4.0}}"))
        XCTAssertEqual(w.components(separatedBy: "[[Category:").count - 1, 2)
        XCTAssertTrue(w.hasPrefix("=={{int:filedesc}}=="))
    }

    func testRosterParsing() {
        let text = "* 31 [[Shavon Shields|Shields]]\n* 10 [[Melih Mahmutoğlu|Mahmutoğlu]] '''(K)'''\n{{TBL oyuncu | num =  0 | nat = TUR| ilk = Shane | son = Larkin| pos = PG}}\n{{player2 | num = 7 | first = Ali | last = Veli | dab = basketball }}"
        let r = Wikidata.parseRoster(text)
        XCTAssertEqual(r.map(\.number), ["0", "7", "10", "31"])
        XCTAssertEqual(r.map(\.name), ["Shane Larkin", "Ali Veli", "Melih Mahmutoğlu", "Shavon Shields"])
        XCTAssertEqual(r[1].title, "Ali Veli (basketball)")
    }

    func testTilesAndColors() {
        let t = ImageAnalyzer.tiles(width: 3000, height: 2000, cols: 3, rows: 2)
        XCTAssertEqual(t.count, 7)
        XCTAssertTrue(t.allSatisfy { $0.minX >= 0 && $0.maxX <= 3000 && $0.maxY <= 2000 })
        XCTAssertEqual(JerseyColor.name(r: 250, g: 230, b: 20), "sarı")
        XCTAssertEqual(JerseyColor.name(r: 15, g: 30, b: 90), "lacivert")
        XCTAssertEqual(JerseyColor.name(r: 10, g: 10, b: 10), "siyah")
    }

    func testNoRepeatNgram() {
        XCTAssertEqual(FlorenceOCR.bannedTokens([5, 6, 7, 9, 5, 6]), [7])
        XCTAssertTrue(FlorenceOCR.bannedTokens([5, 6]).isEmpty)
    }

    func testProjectRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var p = Project()
        p.match.teams = teams
        p.sync(fileNames: ["a.jpg", "b.jpg"])
        p.photos["a.jpg"]?.manual = [ManualPlayer(team: "a", number: "31")]
        try p.save(folder: dir)
        let loaded = try Project.load(folder: dir)
        XCTAssertEqual(loaded.photos.count, 2)
        XCTAssertEqual(loaded.photos["a.jpg"]?.manual, [ManualPlayer(team: "a", number: "31")])
        XCTAssertEqual(loaded.match.teams.map(\.label), ["Fenerbahçe", "Beşiktaş"])
    }
}
