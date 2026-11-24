import SwiftUI
import UploaderCore

struct UploadView: View {
    @EnvironmentObject var model: AppModel
    @State private var botUser = ""
    @State private var botPassword = ""
    @State private var token = ""
    @State private var confirming = false
    @State private var checking = false

    var body: some View {
        let ready = model.readyRows
        let done = model.rows.filter { $0.uploaded != nil }
        let failed = model.rows.filter { $0.uploadError != nil && $0.uploaded == nil }
        ScrollView {
            VStack(spacing: 16) {
                authCard
                Card {
                    HStack(spacing: 28) {
                        stat(ready.count, "yüklenecek", Theme.blue)
                        stat(done.count, "yüklendi", .green)
                        stat(failed.count, "hatalı", .red)
                        stat(model.rows.filter { !$0.include }.count, "hariç tutuldu", .secondary)
                        Spacer()
                    }
                    HStack {
                        Button { checking = true; Task { await model.runCheck(); checking = false } } label: { Label("Kategorileri ve dosya adlarını denetle", systemImage: "checklist") }
                            .disabled(checking || ready.isEmpty)
                        if checking { ProgressView().controlSize(.small) }
                        Spacer()
                        Button { confirming = true } label: { Label("\(ready.count) fotoğrafı yükle", systemImage: "arrow.up.circle.fill").padding(.horizontal, 6) }
                            .buttonStyle(.borderedProminent).tint(Theme.blue).controlSize(.large)
                            .disabled(model.isBusy || model.username == nil || ready.isEmpty)
                    }
                    if let c = model.check { checkResult(c) }
                }
                if let first = ready.first {
                    Card(title: String(localized: "Örnek sayfa metni: \(first.title)"), systemImage: "doc.plaintext") {
                        Text(model.wikitext(for: first)).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                if !done.isEmpty || !failed.isEmpty {
                    Card(title: String(localized: "Sonuçlar"), systemImage: "list.bullet.rectangle") {
                        ForEach(failed) { r in Label("\(r.name): \(r.uploadError ?? "")", systemImage: "xmark.octagon").foregroundStyle(.red).font(.callout) }
                        ForEach(done) { r in
                            if let s = r.uploaded?.url, let url = URL(string: s) { Link(r.uploaded?.title ?? r.title, destination: url).font(.callout) } else { Text(r.uploaded?.title ?? r.title).font(.callout) }
                        }
                    }
                }
            }
            .padding(20)
        }
        .confirmationDialog("\(ready.count) fotoğraf \(model.username ?? "") hesabıyla Wikimedia Commons'a herkese açık olarak yüklenecek.", isPresented: $confirming, titleVisibility: .visible) {
            Button("Yükle") { model.startUpload() }
            Button("Vazgeç", role: .cancel) {}
        } message: { Text("Yüklenen dosyalar seçtiğiniz özgür lisansla yayımlanır; bu işlem geri alınamaz.") }
    }

    private func stat(_ value: Int, _ label: LocalizedStringKey, _ color: some ShapeStyle) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)").font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func checkResult(_ c: UploadCheck) -> some View {
        Divider()
        if c.missingCategories.isEmpty {
            Label("Tüm kategoriler Commons'ta mevcut.", systemImage: "checkmark.circle").foregroundStyle(.green)
        } else {
            Label("Commons'ta bulunmayan kategoriler (\(c.missingCategories.count)):", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            ForEach(c.missingCategories, id: \.self) { Text("• \($0)").font(.callout) }
        }
        if c.takenTitles.isEmpty {
            Label("Dosya adları kullanılabilir.", systemImage: "checkmark.circle").foregroundStyle(.green)
        } else {
            Label("Bu adlarla dosya zaten var (\(c.takenTitles.count)):", systemImage: "xmark.octagon").foregroundStyle(.red)
            ForEach(c.takenTitles.prefix(20), id: \.self) { Text("• \($0)").font(.callout) }
        }
    }

    @ViewBuilder private var authCard: some View {
        if let user = model.username {
            Card {
                HStack {
                    Image(systemName: "person.crop.circle.fill.badge.checkmark").font(.title2).foregroundStyle(Theme.blue)
                    Text("Commons oturumu: ").foregroundStyle(.secondary) + Text(user).fontWeight(.semibold)
                    Spacer()
                    Button("Oturumu kapat") { model.logout() }
                }
            }
        } else {
            Card(title: String(localized: "Commons oturumu"), systemImage: "key") {
                Text("Commons'ta Special:BotPasswords sayfasından \"Dosya yükle\" ve \"Sayfa oluştur, düzenle\" izinleriyle bir bot parolası oluşturun. Kimlik bilgisi bu Mac'in Anahtar Zinciri'nde saklanır.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    TextField("Kullanıcı@botadı", text: $botUser)
                    SecureField("Bot parolası", text: $botPassword)
                    Button("Oturum aç") { Task { await model.login(.botPassword(username: botUser.trimmingCharacters(in: .whitespaces), password: botPassword)); botPassword = "" } }
                        .buttonStyle(.borderedProminent).tint(Theme.blue).disabled(botUser.isEmpty || botPassword.isEmpty)
                }
                HStack {
                    SecureField("ya da OAuth 2.0 erişim belirteci (yalnızca sahibinin kullandığı uygulama)", text: $token)
                    Button("Belirteçle aç") { Task { await model.login(.oauth2(token: token.trimmingCharacters(in: .whitespacesAndNewlines))); token = "" } }.disabled(token.isEmpty)
                }
            }
            .textFieldStyle(.roundedBorder)
        }
    }
}
