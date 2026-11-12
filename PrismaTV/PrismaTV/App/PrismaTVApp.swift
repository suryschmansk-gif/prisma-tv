import SwiftUI
import AVFoundation

@main
struct PrismaTVApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var library = Library()

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(library.progress)
                .environmentObject(library.favorites)
                .environmentObject(library.epg)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var lib: Library
    @State private var showSplash = true

    var body: some View {
        ZStack {
            Group {
                if lib.account == nil {
                    LoginView()
                } else if lib.isEmpty, let message = lib.failureMessage {
                    FailureView(message: message)
                } else if lib.isEmpty {
                    LoadingView()
                } else {
                    MainTabs()
                }
            }
            .transition(.opacity)

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: lib.account == nil)
        .animation(.easeInOut(duration: 0.35), value: lib.isEmpty)
        .task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeInOut(duration: 0.6)) { showSplash = false }
        }
        .fullScreenCover(item: $lib.player) { request in
            PlayerView(request: request)
                .environmentObject(lib)
                .environmentObject(lib.progress)
                .environmentObject(lib.favorites)
                .environmentObject(lib.epg)
        }
    }
}

// MARK: - Abertura animada

struct SplashView: View {
    @State private var step = 0

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            Circle()
                .fill(Theme.accent.opacity(0.22))
                .frame(width: 340, height: 340)
                .blur(radius: 90)
                .scaleEffect(step > 0 ? 1.15 : 0.5)
                .opacity(step > 0 ? 1 : 0)
            VStack(spacing: 18) {
                AppLogo(size: 96)
                    .scaleEffect(step > 0 ? 1 : 0.6)
                    .opacity(step > 0 ? 1 : 0)
                    .rotation3DEffect(.degrees(step > 0 ? 0 : -25), axis: (x: 1, y: 0, z: 0))
                Text("Prisma TV")
                    .font(.system(size: 30, weight: .heavy))
                    .tracking(-0.5)
                    .foregroundStyle(.white)
                    .opacity(step > 1 ? 1 : 0)
                    .offset(y: step > 1 ? 0 : 12)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) { step = 1 }
            withAnimation(.easeOut(duration: 0.5).delay(0.35)) { step = 2 }
        }
    }
}

// MARK: - Abas (barra flutuante de vidro)

enum AppTab: Hashable { case series, movies, live, search }

struct MainTabs: View {
    @State private var tab: AppTab = .series

    var body: some View {
        ZStack {
            page(.series) { SectionView(kind: .series) }
            page(.movies) { SectionView(kind: .movie) }
            page(.live) { LiveView() }
            page(.search) { SearchView() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GlassTabBar(selection: $tab)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func page<Content: View>(_ t: AppTab, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .opacity(tab == t ? 1 : 0)
            .scaleEffect(tab == t ? 1 : 0.985)
            .allowsHitTesting(tab == t)
            .accessibilityHidden(tab != t)
            .animation(.easeInOut(duration: 0.25), value: tab)
    }
}

struct GlassTabBar: View {
    @Binding var selection: AppTab
    @Namespace private var pill

    private struct Item: Identifiable {
        let tab: AppTab
        let title: String
        let icon: String
        var id: String { title }
    }

    private let items = [
        Item(tab: .series, title: "Séries", icon: "play.rectangle.on.rectangle.fill"),
        Item(tab: .movies, title: "Filmes", icon: "film.fill"),
        Item(tab: .live, title: "TV", icon: "tv.fill"),
        Item(tab: .search, title: "Buscar", icon: "magnifyingglass"),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items) { item in
                let active = selection == item.tab
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = item.tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon).font(.system(size: 18, weight: .semibold))
                        Text(item.title).font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(active ? Theme.accent : Color.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background {
                        if active {
                            Capsule()
                                .fill(Theme.accent.opacity(0.16))
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(6)
        .glass(Capsule(), dark: true)
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
    }
}

// MARK: - Carregando / erro

struct LoadingView: View {
    @State private var pulse = false
    var body: some View {
        VStack(spacing: 22) {
            AppLogo(size: 84)
                .scaleEffect(pulse ? 1.05 : 0.95)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
            Text("Carregando sua lista…")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            ProgressView().tint(Theme.accent)
            Text("Na primeira vez pode levar até um minuto.\nDepois disso o app abre na hora.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
        .onAppear { pulse = true }
    }
}

struct FailureView: View {
    let message: String
    @EnvironmentObject private var lib: Library

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 46))
                .foregroundStyle(Theme.accent)
            Text("Não consegui carregar a lista")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
            PrimaryButton(title: "Tentar de novo", icon: "arrow.clockwise") {
                Task { await lib.refresh() }
            }
            .frame(maxWidth: 320)
            Button("Trocar de conta") { lib.logout() }
                .foregroundStyle(Theme.accent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
    }
}
