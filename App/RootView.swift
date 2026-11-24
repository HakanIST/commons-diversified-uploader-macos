import SwiftUI
import UploaderCore

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { model.step }, set: { model.step = $0 ?? .match })) {
                Section("Adımlar") {
                    ForEach(Array(Step.allCases.enumerated()), id: \.element) { index, step in
                        Label {
                            HStack {
                                Text(step.title)
                                Spacer()
                                badge(for: step)
                            }
                        } icon: { Image(systemName: step.icon) }
                        .tag(step)
                        .padding(.vertical, 3)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            .safeAreaInset(edge: .bottom) { sidebarFooter }
        } detail: {
            VStack(spacing: 0) {
                if let activity = model.activity { ActivityBar(activity: activity) }
                Group {
                    if model.folder == nil {
                        WelcomeView()
                    } else {
                        switch model.step {
                        case .match: MatchView()
                        case .roster: RosterView()
                        case .photos: PhotosView()
                        case .upload: UploadView()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(model.folder == nil ? "Commons Diversified Uploader" : model.step.title)
            .animation(.snappy, value: model.activity != nil)
        }
        .alert("Bir sorun oluştu", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(model.alert ?? "") }
    }

    @ViewBuilder private func badge(for step: Step) -> some View {
        switch step {
        case .photos where !model.rows.isEmpty:
            Text("\(model.rows.count)").font(.caption).foregroundStyle(.secondary)
        case .upload where model.rows.contains(where: { $0.uploaded != nil }):
            Text("\(model.rows.filter { $0.uploaded != nil }.count)").font(.caption).foregroundStyle(.green)
        default: EmptyView()
        }
    }

    private var sidebarFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: model.username == nil ? "person.crop.circle.badge.questionmark" : "person.crop.circle.fill")
                .foregroundStyle(model.username == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.blue))
            Text(model.username ?? String(localized: "Oturum açılmadı")).font(.callout).lineLimit(1)
            Spacer()
        }
        .padding(12)
        .background(.bar)
    }
}

struct ActivityBar: View {
    @EnvironmentObject var model: AppModel
    let activity: ActivityState

    var body: some View {
        HStack(spacing: 12) {
            if let fraction = activity.fraction { ProgressView(value: fraction).frame(width: 180) } else { ProgressView().controlSize(.small) }
            Text(activity.message).font(.callout).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button("Durdur") { model.cancel() }.controlSize(.small)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(Theme.blue.opacity(0.1))
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct WelcomeView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            Image("Mark").resizable().frame(width: 128, height: 128)
            Text("Maç fotoğraflarınızı Commons'a taşıyın").font(.title2.weight(.semibold))
            Text("Bir maçın fotoğraflarını içeren klasörü seçin. Forma numaraları bu bilgisayarda okunur,\noyuncular kadrodan bulunur ve Commons kategorileri önerilir.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button { model.chooseFolder() } label: { Label("Klasör seç", systemImage: "folder").padding(.horizontal, 8) }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.blue)
        }
        .padding(40)
    }
}
