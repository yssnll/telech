import AVKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: PlayerStore
    @State private var pendingDelete: OfflineVideo?

    private let colors = TelechPalette()

    var body: some View {
        ZStack {
            colors.background.ignoresSafeArea()
            LinearGradient(
                colors: [colors.overlay, colors.background, colors.background],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    header
                    tabs
                    if store.activeTab == .playback {
                        playbackView
                    } else {
                        offlineView
                    }
                    footer
                }
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .alert(store.alertTitle, isPresented: $store.showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.alertMessage)
        }
        .confirmationDialog(
            "Supprimer la vidéo ?",
            item: $pendingDelete
        ) { video in
            Button("Supprimer", role: .destructive) {
                store.removeOffline(video)
            }
            Button("Annuler", role: .cancel) {}
        } message: { video in
            Text("\(video.filename) sera retirée de l’onglet Hors ligne.")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colors.primary)
                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(colors.primaryForeground)
            }
            .frame(width: 46, height: 46)
            .rotationEffect(.degrees(-8))

            VStack(alignment: .leading, spacing: 2) {
                Text("LECTEUR VIDÉO")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(colors.accent)
                Text("Regarder, puis garder.")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .tracking(-0.8)
                    .foregroundStyle(colors.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 13, weight: .semibold))
                Text("local")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(colors.secondaryForeground)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(colors.secondary, in: Capsule())
        }
        .padding(.horizontal, 22)
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            tabButton(
                title: "Lecture",
                icon: "play.circle",
                tab: .playback,
                count: nil
            )
            tabButton(
                title: "Hors ligne",
                icon: "arrow.down.circle",
                tab: .offline,
                count: store.offlineVideos.count > 0 ? store.offlineVideos.count : nil
            )
        }
        .padding(4)
        .background(colors.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(colors.border, lineWidth: 1)
        }
        .padding(.horizontal, 18)
        .padding(.top, 22)
    }

    private func tabButton(
        title: String,
        icon: String,
        tab: AppTab,
        count: Int?
    ) -> some View {
        Button {
            store.activeTab = tab
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                if let count {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(store.activeTab == tab ? colors.primary : colors.foreground)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(
                            store.activeTab == tab ? colors.primaryForeground : colors.secondary,
                            in: Circle()
                        )
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(store.activeTab == tab ? colors.primaryForeground : colors.mutedForeground)
            .background(
                store.activeTab == tab ? colors.primary : .clear,
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var playbackView: some View {
        VStack(spacing: 0) {
            Text("Collez le lien d’une vidéo ou d’une playlist .m3u8, regardez-la, puis gardez-la sur l’iPhone.")
                .font(.system(size: 14))
                .foregroundStyle(colors.mutedForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 20)

            playerPanel
            statusRow
            addressCard

            if let message = store.downloadMessage {
                downloadStatus(message)
            }
            if store.playbackState == .error, let message = store.errorMessage {
                errorCard(message)
            }
            if !store.history.isEmpty {
                historySection
            }
        }
    }

    private var playerPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(colors.videoBackground)

            if store.activeURL != nil {
                VideoPlayer(player: store.player)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "play")
                        .font(.system(size: 31, weight: .medium))
                        .foregroundStyle(colors.primary)
                        .frame(width: 70, height: 70)
                        .background(colors.secondary, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .padding(.bottom, 8)
                    Text("Votre vidéo apparaîtra ici")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(colors.foreground)
                    Text("La lecture et l’enregistrement se font depuis cet écran.")
                        .font(.system(size: 13))
                        .foregroundStyle(colors.mutedForeground)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 30)
            }

            if store.activeURL != nil, store.playbackState == .loading {
                Text("CHARGEMENT")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(colors.warning)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(colors.overlay.opacity(0.92), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(12)
            }
        }
        .aspectRatio(1.6, contentMode: .fit)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(colors.border, lineWidth: 1)
        }
        .padding(.horizontal, 18)
    }

    private var statusRow: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(store.playbackState.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(colors.mutedForeground)
            Spacer(minLength: 8)
            if let activeURL = store.activeURL {
                Text(store.activeTitle ?? URLUtilities.shortened(activeURL))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(colors.foreground)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .frame(minHeight: 22)
    }

    private var addressCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Adresse de la vidéo")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colors.foreground)
                Spacer()
                Text("MP4 / HLS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(colors.mutedForeground)
            }
            .padding(.bottom, 10)

            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 18))
                    .foregroundStyle(colors.mutedForeground)
                TextField("https://…/video.m3u8", text: $store.urlText)
                    .font(.system(size: 13))
                    .foregroundStyle(colors.foreground)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .onSubmit { store.openStream() }
                if !store.urlText.isEmpty {
                    Button {
                        store.urlText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(colors.mutedForeground)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(colors.input, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(colors.border, lineWidth: 1)
            }

            HStack(spacing: 9) {
                Button {
                    store.openStream()
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "play.fill")
                        Text("Lire")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(colors.primaryForeground)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(colors.primary, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    store.downloadActive()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.down.to.line")
                        Text(store.downloadState == .working ? "Téléchargement…" : "Hors ligne")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(colors.secondaryForeground)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    .background(colors.secondary, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(colors.border, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(store.downloadState == .working || URLUtilities.isLocal(store.activeURL ?? ""))
                .opacity(store.downloadState == .working ? 0.55 : 1)
            }
            .padding(.top, 12)
        }
        .padding(16)
        .background(colors.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(colors.border, lineWidth: 1)
        }
        .padding(18)
        .padding(.top, 15)
    }

    private func downloadStatus(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: store.downloadState == .working ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                .font(.system(size: 18))
                .foregroundStyle(colors.accent)
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(colors.secondaryForeground)
                if store.downloadState == .working {
                    ProgressView(value: store.downloadProgress ?? 0)
                        .tint(colors.accent)
                    if let progress = store.downloadProgress {
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 10))
                            .foregroundStyle(colors.mutedForeground)
                    }
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(colors.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(colors.border, lineWidth: 1)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "shield")
                .font(.system(size: 21))
                .foregroundStyle(colors.destructive)
                .frame(width: 38, height: 38)
                .background(colors.destructive.opacity(0.13), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(store.failureTitle())
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(colors.foreground)
                Text("\(message) \(store.failureExplanation())")
                    .font(.system(size: 12))
                    .foregroundStyle(colors.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                Button(store.showDetails ? "Masquer le diagnostic" : "Voir le diagnostic") {
                    store.showDetails.toggle()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(colors.accent)
                .buttonStyle(.plain)
                if store.showDetails {
                    Text("Les vidéos protégées, chiffrées ou limitées à une page web ne peuvent pas être récupérées par une app autonome.")
                        .font(.system(size: 12))
                        .foregroundStyle(colors.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(15)
        .background(colors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(colors.destructive, lineWidth: 1)
        }
        .padding(.horizontal, 18)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Récents")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(colors.foreground)
                Spacer()
                Button("Effacer") {
                    store.clearHistory()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(colors.mutedForeground)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            ForEach(store.history, id: \.self) { item in
                Button {
                    store.openRecent(item)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(colors.accent)
                            .frame(width: 34, height: 34)
                            .background(colors.secondary, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        Text(URLUtilities.shortened(item))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(colors.foreground)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16))
                            .foregroundStyle(colors.mutedForeground)
                    }
                    .padding(.horizontal, 11)
                    .frame(minHeight: 58)
                    .background(colors.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(colors.border, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 26)
    }

    private var offlineView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 7) {
                Image(systemName: "icloud.and.arrow.down")
                    .font(.system(size: 28))
                    .foregroundStyle(colors.accent)
                    .frame(width: 62, height: 62)
                    .background(colors.secondary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(.bottom, 6)
                Text("Vos vidéos, même sans réseau.")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .tracking(-0.4)
                    .foregroundStyle(colors.foreground)
                    .multilineTextAlignment(.center)
                Text("Les vidéos téléchargées restent dans le stockage privé de cette app.")
                    .font(.system(size: 13))
                    .foregroundStyle(colors.mutedForeground)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 24)

            if store.offlineVideos.isEmpty {
                emptyOffline
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("\(store.offlineVideos.count) vidéo\(store.offlineVideos.count > 1 ? "s" : "")")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(colors.foreground)
                        Spacer()
                        Text("Stockage privé")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(colors.mutedForeground)
                    }
                    .padding(.horizontal, 4)

                    ForEach(store.offlineVideos) { video in
                        offlineRow(video)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private var emptyOffline: some View {
        VStack(spacing: 7) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 28))
                .foregroundStyle(colors.mutedForeground)
                .padding(.bottom, 5)
            Text("Aucune vidéo hors ligne")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(colors.foreground)
            Text("Ouvrez l’onglet Lecture, collez un lien, puis appuyez sur Hors ligne.")
                .font(.system(size: 13))
                .foregroundStyle(colors.mutedForeground)
                .multilineTextAlignment(.center)
            Button {
                store.activeTab = .playback
            } label: {
                Label("Ajouter une vidéo", systemImage: "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(colors.primaryForeground)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 46)
                    .background(colors.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 11)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 34)
        .frame(maxWidth: .infinity)
        .background(colors.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(colors.border, lineWidth: 1)
        }
        .padding(.horizontal, 18)
    }

    private func offlineRow(_ video: OfflineVideo) -> some View {
        HStack(spacing: 10) {
            Button {
                store.playOffline(video)
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(colors.accent)
                        .frame(width: 58, height: 58)
                        .background(colors.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(video.filename)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(colors.foreground)
                            .lineLimit(1)
                        Text("\(URLUtilities.formatBytes(video.size)) · \(URLUtilities.formatDate(video.createdAt))")
                            .font(.system(size: 10))
                            .foregroundStyle(colors.mutedForeground)
                            .lineLimit(1)
                        Text("Fichier vidéo local")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(colors.accent)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "play.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(colors.primary)
                }
            }
            .buttonStyle(.plain)

            Button {
                pendingDelete = video
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 18))
                    .foregroundStyle(colors.destructive)
                    .frame(width: 34, height: 42)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Supprimer \(video.filename)")
        }
        .padding(10)
        .background(colors.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(colors.border, lineWidth: 1)
        }
    }

    private var footer: some View {
        Label("Vidéos conservées uniquement sur cet appareil", systemImage: "lock")
            .font(.system(size: 11))
            .foregroundStyle(colors.mutedForeground)
            .padding(.top, 28)
    }

    private var statusColor: Color {
        switch store.playbackState {
        case .idle: return colors.mutedForeground
        case .loading: return colors.warning
        case .ready: return colors.success
        case .error: return colors.destructive
        }
    }
}

private struct TelechPalette {
    let foreground = Color(hex: "#F7F8FB")
    let background = Color(hex: "#0D1020")
    let card = Color(hex: "#171B2D")
    let primary = Color(hex: "#FF725C")
    let primaryForeground = Color(hex: "#17111B")
    let secondary = Color(hex: "#242941")
    let secondaryForeground = Color(hex: "#F7F8FB")
    let mutedForeground = Color(hex: "#9BA3BD")
    let accent = Color(hex: "#A8E6CF")
    let destructive = Color(hex: "#FF625F")
    let border = Color(hex: "#2D3450")
    let input = Color(hex: "#252C45")
    let overlay = Color(hex: "#111528")
    let videoBackground = Color(hex: "#080A12")
    let success = Color(hex: "#A8E6CF")
    let warning = Color(hex: "#FFD166")
}

private extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var number: UInt64 = 0
        Scanner(string: value).scanHexInt64(&number)
        self.init(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }
}
