import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var lib: Library
    @Environment(\.dismiss) private var dismiss
    @AppStorage("liveFormat") private var liveFormat = "ts"
    @AppStorage("tapSounds") private var tapSounds = true
    @State private var confirmLogout = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Conta") {
                    row("Lista", lib.account?.name ?? "-")
                    row("Servidor", URL(string: lib.account?.server ?? "")?.host ?? "-")
                    row("Usuário", lib.account?.username ?? "-")
                    if let u = lib.userInfo {
                        row("Situação", (u.status ?? "-").capitalized)
                        row("Expira em", u.expiration.map { Fmt.day.string(from: $0) } ?? "Sem data")
                        if let max = u.maxConnections {
                            row("Conexões", "\(u.activeConnections ?? 0) de \(max)")
                        }
                    }
                }

                Section {
                    row("Canais", "\(lib.catalog.channels.count)")
                    row("Filmes", "\(lib.catalog.movies.count)")
                    row("Séries", "\(lib.catalog.series.count)")
                    if let d = lib.lastUpdated {
                        row("Atualizado", d.formatted(.relative(presentation: .named)))
                    }
                    Button {
                        Task { await lib.refresh() }
                    } label: {
                        HStack {
                            Label("Atualizar listas agora", systemImage: "arrow.clockwise")
                            Spacer()
                            if lib.isRefreshing { ProgressView() }
                        }
                    }
                    .disabled(lib.isRefreshing)
                } header: {
                    Text("Biblioteca")
                } footer: {
                    Text("O app atualiza sozinho a cada 12 horas.")
                }

                Section {
                    Toggle("Som ao tocar nos botões", isOn: $tapSounds)
                    Picker("Formato da TV ao vivo", selection: $liveFormat) {
                        Text("MPEG-TS (recomendado)").tag("ts")
                        Text("HLS (m3u8)").tag("m3u8")
                    }
                } header: {
                    Text("Reprodução")
                } footer: {
                    Text("Se algum canal travar ou não abrir, experimente trocar o formato.")
                }

                Section {
                    Button("Sair da conta", role: .destructive) { confirmLogout = true }
                } footer: {
                    CreditFooter().padding(.top, 12)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Configurações")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
            }
            .confirmationDialog("Sair desta conta?", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("Sair", role: .destructive) {
                    dismiss()
                    lib.logout()
                }
            } message: {
                Text("Seu progresso e seus favoritos continuam salvos neste aparelho.")
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}
