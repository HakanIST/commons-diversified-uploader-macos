import SwiftUI
import UploaderCore

struct PhotosView: View {
    @EnvironmentObject var model: AppModel
    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { model.startAnalysis() } label: {
                    Label(model.pendingCount > 0 ? String(localized: "Analiz et (\(model.pendingCount))") : String(localized: "Tümü analiz edildi"), systemImage: "sparkle.magnifyingglass")
                }
                .buttonStyle(.borderedProminent).tint(Theme.blue).disabled(model.isBusy || model.pendingCount == 0)
                Spacer()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(PhotoFilter.allCases) { f in
                            Chip(text: "\(f.title) \(model.rows.filter(f.matches).count)", selected: model.filter == f).onTapGesture { model.filter = f }
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            HSplitView {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(model.filteredRows) { row in
                            PhotoCard(row: row, selected: row.name == model.selection).onTapGesture { model.selection = row.name }
                        }
                    }
                    .padding(16)
                    if model.filteredRows.isEmpty { Text("Bu süzgeçte fotoğraf yok.").foregroundStyle(.secondary).padding(60) }
                }
                .frame(minWidth: 460)
                PhotoInspector().frame(minWidth: 340, idealWidth: 400, maxWidth: 520)
            }
        }
    }
}

struct PhotoCard: View {
    @EnvironmentObject var model: AppModel
    let row: PhotoRow
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.aspectRatio(3 / 2, contentMode: .fit)
                .overlay { Thumbnail(url: model.url(for: row.name)) }
                .clipped()
                .overlay(alignment: .topTrailing) { status.padding(6) }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.players.isEmpty ? (row.analyzed ? String(localized: "Oyuncu bulunamadı") : String(localized: "Analiz bekliyor")) : row.players.map { "\($0.number) \($0.name)" }.joined(separator: ", "))
                    .font(.callout.weight(.medium)).lineLimit(1).foregroundStyle(row.players.isEmpty ? .secondary : .primary)
                HStack(spacing: 4) {
                    Text(row.name).font(.caption).foregroundStyle(.secondary)
                    if !row.unresolved.isEmpty { Text("· ? \(row.unresolved.map(\.number).joined(separator: ", "))").font(.caption).foregroundStyle(.orange) }
                }
            }
            .padding(8)
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? Theme.blue : Color.primary.opacity(0.08), lineWidth: selected ? 2.5 : 1))
        .opacity(row.include ? 1 : 0.45)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var status: some View {
        if row.uploaded != nil { tag("Yüklendi", .green) } else if row.uploadError != nil { tag("Hata", .red) }
    }

    private func tag(_ text: LocalizedStringKey, _ color: Color) -> some View {
        Text(text).font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2).background(color, in: Capsule()).foregroundStyle(.white)
    }
}

struct PhotoInspector: View {
    @EnvironmentObject var model: AppModel
    @State private var addTeam = "a"
    @State private var addNumber = ""

    var body: some View {
        if let row = model.selectedRow {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Thumbnail(url: model.url(for: row.name), maxPixel: 1400)
                        .aspectRatio(aspect(row), contentMode: .fit)
                        .overlay { GeometryReader { geo in boxes(row, size: geo.size) } }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Toggle(isOn: Binding(get: { row.include }, set: { model.project.photos[row.name]?.include = $0 })) {
                        Text("Bu fotoğrafı yükle").fontWeight(.medium) + Text("  \(row.name)\(row.date.map { " · \($0)" } ?? "")").foregroundStyle(.secondary).font(.caption)
                    }
                    playersSection(row)
                    VStack(alignment: .leading, spacing: 5) {
                        FieldLabel("Commons dosya adı")
                        TextField("", text: Binding(get: { row.title }, set: { model.project.photos[row.name]?.title = $0.isEmpty ? nil : $0 }), axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        if row.customTitle { Button("Şablondaki ada dön") { model.project.photos[row.name]?.title = nil }.buttonStyle(.link).font(.caption) }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        FieldLabel("Kategoriler")
                        if row.categories.isEmpty {
                            Label("Kategori yok: maç ya da takım kategorisi girin.", systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                        }
                        ForEach(row.categories, id: \.self) { Label($0, systemImage: "folder").font(.callout) }
                    }
                    if let up = row.uploaded {
                        if let s = up.url, let url = URL(string: s) { Link(destination: url) { Label(up.title, systemImage: "checkmark.seal.fill") }.foregroundStyle(.green) }
                    }
                    if let e = row.uploadError { Label(e, systemImage: "xmark.octagon").foregroundStyle(.red).font(.callout) }
                    if let e = row.error { Label("Analiz hatası: \(e)", systemImage: "xmark.octagon").foregroundStyle(.red).font(.callout) }
                    Button { model.project.photos[row.name]?.analysis = nil; model.startAnalysis(only: [row.name]) } label: { Label("Yeniden analiz et", systemImage: "arrow.clockwise") }
                        .disabled(model.isBusy)
                }
                .padding(16)
            }
            .background(.background)
        } else {
            Text("Ayrıntı için bir fotoğraf seçin.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
        }
    }

    private func aspect(_ row: PhotoRow) -> CGFloat {
        guard let a = model.project.photos[row.name]?.analysis, a.height > 0 else { return 3 / 2 }
        return CGFloat(a.width) / CGFloat(a.height)
    }

    @ViewBuilder private func boxes(_ row: PhotoRow, size: CGSize) -> some View {
        ForEach(row.players) { p in
            if let b = p.box { boxView(b, label: "\(p.number) \(p.name)", color: .green, size: size) }
        }
        ForEach(Array(row.unresolved.enumerated()), id: \.offset) { _, u in
            boxView(u.box, label: "\(u.number) ?", color: .orange, size: size)
        }
    }

    private func boxView(_ b: NormalizedBox, label: String, color: Color, size: CGSize) -> some View {
        let rect = CGRect(x: b.x0 * size.width, y: b.y0 * size.height, width: b.width * size.width, height: b.height * size.height)
        return RoundedRectangle(cornerRadius: 3).strokeBorder(color, lineWidth: 2)
            .frame(width: max(rect.width, 6), height: max(rect.height, 6))
            .overlay(alignment: .topLeading) {
                Text(label).font(.system(size: 10, weight: .semibold)).padding(.horizontal, 4).padding(.vertical, 1)
                    .background(color, in: RoundedRectangle(cornerRadius: 3)).foregroundStyle(.black)
                    .fixedSize().alignmentGuide(.top) { $0[.bottom] + 2 }
            }
            .position(x: rect.midX, y: rect.midY)
    }

    private func teamLabel(_ key: String) -> String {
        model.project.match.teams.first { $0.key == key }.map { $0.label.isEmpty ? key.uppercased() : $0.label } ?? key
    }

    @ViewBuilder private func playersSection(_ row: PhotoRow) -> some View {
        let manual = row.players.map { ManualPlayer(team: $0.team, number: $0.number) }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                FieldLabel(row.manual ? "Oyuncular (elle düzenlendi)" : "Oyuncular")
                if row.manual { Button("Otomatiğe dön") { model.project.photos[row.name]?.manual = nil }.buttonStyle(.link).font(.caption) }
            }
            if row.players.isEmpty { Text("Oyuncu yok.").font(.callout).foregroundStyle(.secondary) }
            ForEach(Array(row.players.enumerated()), id: \.element.id) { i, p in
                HStack(spacing: 10) {
                    Text(p.number).font(.callout.weight(.bold)).frame(width: 34, height: 26).background(Theme.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.name)
                        HStack(spacing: 4) {
                            Text(teamLabel(p.team))
                            if let c = p.confidence { Text("· güven %\(Int(c * 100))") }
                            if p.category == nil { Text("· kategorisi yok").foregroundStyle(.orange) }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { var m = manual; m.remove(at: i); model.project.photos[row.name]?.manual = m } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
            HStack {
                Picker("", selection: $addTeam) { ForEach(model.project.match.teams, id: \.key) { Text(teamLabel($0.key)).tag($0.key) } }.labelsHidden().frame(maxWidth: 130)
                Picker("", selection: $addNumber) {
                    Text("Oyuncu seç").tag("")
                    ForEach(model.project.match.teams.first { $0.key == addTeam }?.players ?? []) { Text("\($0.number) \($0.name)").tag($0.number) }
                }.labelsHidden()
                Button("Ekle") {
                    guard !addNumber.isEmpty, !manual.contains(ManualPlayer(team: addTeam, number: addNumber)) else { return }
                    model.project.photos[row.name]?.manual = manual + [ManualPlayer(team: addTeam, number: addNumber)]
                }.disabled(addNumber.isEmpty)
            }
        }
    }
}
