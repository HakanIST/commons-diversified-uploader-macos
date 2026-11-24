import SwiftUI
import UploaderCore

struct MatchView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Card {
                    HStack {
                        Image(systemName: "folder.fill").foregroundStyle(Theme.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.folder?.lastPathComponent ?? "").font(.headline)
                            Text("\(model.folder?.deletingLastPathComponent().path ?? "") · \(model.rows.count) fotoğraf").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Klasör değiştir") { model.chooseFolder() }
                    }
                }
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Array(model.project.match.teams.enumerated()), id: \.element.key) { index, team in
                        TeamCard(index: index, teamKey: team.key)
                    }
                }
                Card(title: String(localized: "Maç ve yükleme bilgileri"), systemImage: "text.badge.checkmark") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            field("Maç başlığı (dosya adında ve açıklamada kullanılır)") {
                                TextField("Beşiktaş vs Fenerbahçe BSL 20261122", text: $model.project.match.title)
                            }
                            field("Maç kategorisi (boşsa takım kategorileri kullanılır)") {
                                TextField("Kategori adı", text: $model.project.match.category)
                            }
                        }
                        GridRow {
                            Toggle("Maç kategorisi Commons'ta yoksa takım kategorilerinin altında oluştur", isOn: $model.project.match.createCategory)
                                .gridCellColumns(2)
                        }
                        GridRow {
                            field("Tüm fotoğraflara eklenecek diğer kategoriler (satır başına bir tane)") {
                                TextEditor(text: Binding(
                                    get: { model.project.match.extraCategories.joined(separator: "\n") },
                                    set: { model.project.match.extraCategories = $0.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
                                    .font(.body).frame(height: 70).scrollContentBackground(.hidden)
                                    .padding(6).background(.background, in: RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                            }
                            VStack(alignment: .leading, spacing: 12) {
                                field("Dosya adı şablonu — {oyuncular} {numaralar} {maç} {sıra}") {
                                    TextField("", text: $model.project.match.titleTemplate)
                                }
                                HStack(spacing: 16) {
                                    field("Yazar (boşsa Commons kullanıcı adınız)") { TextField("[[User:Ad|Ad]]", text: $model.project.match.author) }
                                    field("Lisans") {
                                        Picker("", selection: $model.project.match.license) {
                                            Text("CC BY-SA 4.0").tag("cc-by-sa-4.0")
                                            Text("CC BY 4.0").tag("cc-by-4.0")
                                            Text("CC0 (kamu malı)").tag("cc-zero")
                                        }.labelsHidden()
                                    }
                                }
                            }
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                }
            }
            .padding(20)
        }
    }

    private func field<V: View>(_ label: LocalizedStringKey, @ViewBuilder content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 5) { FieldLabel(label); content() }
    }
}

struct TeamCard: View {
    @EnvironmentObject var model: AppModel
    let index: Int
    let teamKey: String
    @State private var query = ""
    @State private var results: [WikidataHit]?
    @State private var loading = false

    private var team: Team { model.project.match.teams[model.teamIndex(teamKey)] }
    private var binding: Binding<Team> { $model.project.match.teams[model.teamIndex(teamKey)] }

    var body: some View {
        Card(title: team.label.isEmpty ? String(localized: "\(index + 1). takım") : team.label, systemImage: "tshirt") {
            HStack {
                TextField("Takım ara (ör. Fenerbahçe basketbol)", text: $query).onSubmit(search)
                Button("Ara", action: search).disabled(query.isEmpty || loading)
                if loading { ProgressView().controlSize(.small) }
            }
            if let results {
                VStack(alignment: .leading, spacing: 0) {
                    if results.isEmpty { Text("Sonuç yok").foregroundStyle(.secondary).padding(8) }
                    ForEach(results) { hit in
                        Button {
                            self.results = nil
                            loading = true
                            Task { await model.setTeam(teamKey, qid: hit.qid); loading = false }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(hit.label).fontWeight(.medium)
                                if !hit.description.isEmpty { Text(hit.description).font(.caption).foregroundStyle(.secondary) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5).padding(.horizontal, 8).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
            }
            if team.qid != nil {
                Text("\(team.players.count) oyuncu · \(team.category.isEmpty ? String(localized: "Commons kategorisi yok") : team.category)").font(.caption).foregroundStyle(.secondary)
            }
            FieldLabel("Bu maçtaki forma renkleri")
            FlowLayout(spacing: 6) {
                ForEach(JerseyColor.names, id: \.self) { color in
                    Chip(text: String(localized: String.LocalizationValue(color)), color: Theme.swatch(color), selected: team.colors.contains(color))
                        .onTapGesture {
                            if team.colors.contains(color) { binding.wrappedValue.colors.removeAll { $0 == color } } else { binding.wrappedValue.colors.append(color) }
                        }
                }
            }
            FieldLabel("Formadaki yazılar (takım adı, sponsor; virgülle)")
            TextField("", text: Binding(
                get: { team.keywords.joined(separator: ", ") },
                set: { binding.wrappedValue.keywords = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
            FieldLabel("Takımın Commons kategorisi")
            TextField("", text: binding.category)
        }
        .textFieldStyle(.roundedBorder)
    }

    private func search() {
        guard !query.isEmpty else { return }
        loading = true
        Task {
            do { results = try await Wikidata.search(query) } catch { model.alert = String(localized: "Arama yapılamadı: \(error.localizedDescription)") }
            loading = false
        }
    }
}

/// Satıra sığmayan ögeleri alt satıra geçiren yerleşim.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            for item in row.items { subviews[item.index].place(at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y), proposal: .unspecified) }
        }
    }

    private struct Row { var y: CGFloat; var height: CGFloat; var width: CGFloat; var items: [(index: Int, x: CGFloat)] }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [], current = Row(y: 0, height: 0, width: 0, items: [])
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if current.width + size.width > width, !current.items.isEmpty {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing, height: 0, width: 0, items: [])
            }
            current.items.append((i, current.width))
            current.width += size.width + spacing
            current.height = max(current.height, size.height)
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
