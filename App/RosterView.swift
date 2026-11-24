import SwiftUI
import UploaderCore

struct RosterView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 16) {
                ForEach(model.project.match.teams, id: \.key) { team in RosterCard(teamKey: team.key) }
            }
            .padding(20)
        }
    }
}

struct RosterCard: View {
    @EnvironmentObject var model: AppModel
    let teamKey: String
    @State private var loading = false

    private var index: Int { model.teamIndex(teamKey) }
    private var team: Team { model.project.match.teams[index] }

    var body: some View {
        Card {
            HStack {
                Text(team.label.isEmpty ? "Takım seçilmedi" : team.label).font(.title3.weight(.semibold))
                Spacer()
                if loading { ProgressView().controlSize(.small) }
                if let qid = team.qid {
                    Button("Vikipedi'den yenile") { loading = true; Task { await model.setTeam(teamKey, qid: qid); loading = false } }.disabled(loading)
                }
                Button { model.project.match.teams[index].players.append(Player(number: "", name: "")) } label: { Label("Oyuncu ekle", systemImage: "plus") }
            }
            if let source = team.rosterSource {
                Text("Kaynak: \(source.lang).wikipedia.org — \(source.page). Maç günündeki kadroyla karşılaştırıp düzeltin.").font(.caption).foregroundStyle(.secondary)
            }
            if team.players.isEmpty {
                Text("Kadro boş. \"Maç\" adımından takımı seçin ya da oyuncuları elle ekleyin.").foregroundStyle(.secondary).padding(.vertical, 12)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow { FieldLabel("No"); FieldLabel("Oyuncu"); FieldLabel("Commons kategorisi"); Text("") }
                    ForEach($model.project.match.teams[index].players) { $player in
                        GridRow {
                            TextField("", text: $player.number).frame(width: 46).multilineTextAlignment(.center)
                            TextField("Ad Soyad", text: $player.name)
                            TextField("kategori yok", text: Binding(get: { player.category ?? "" }, set: { player.category = $0.isEmpty ? nil : $0 }))
                            Button { model.project.match.teams[index].players.removeAll { $0.id == player.id } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless).foregroundStyle(.secondary)
                        }
                    }
                }
                .textFieldStyle(.roundedBorder)
            }
        }
    }
}
