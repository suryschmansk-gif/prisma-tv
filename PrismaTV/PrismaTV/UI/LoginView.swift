import SwiftUI
import UIKit

struct LoginView: View {
    @EnvironmentObject private var lib: Library

    @State private var name = ""
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var loading = false
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field { case name, server, user, pass }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 14) {
                    AppLogo(size: 88)
                    Text("Prisma TV")
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(.white)
                    Text("Entre com os dados da sua linha Xtream Codes")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                .reveal()

                VStack(spacing: 14) {
                    Button {
                        pasteM3U()
                    } label: {
                        Label("Colar link M3U da área de transferência", systemImage: "doc.on.clipboard")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                                    .glass(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.pressable)

                    field("Nome da lista (opcional)", text: $name, icon: "tag", field: .name)
                    field("Servidor  ex: http://dominio.com:8080", text: $server, icon: "server.rack", field: .server, keyboard: .URL)
                    field("Usuário", text: $username, icon: "person", field: .user)

                    HStack(spacing: 12) {
                        Image(systemName: "lock").foregroundStyle(Theme.muted).frame(width: 22)
                        Group {
                            if showPassword {
                                TextField("Senha", text: $password)
                            } else {
                                SecureField("Senha", text: $password)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .pass)
                        .submitLabel(.go)
                        .onSubmit { submit() }
                        Button { showPassword.toggle() } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye").foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: submit) {
                    HStack(spacing: 10) {
                        if loading { ProgressView().tint(Theme.onPrimary) }
                        Text(loading ? "Conectando…" : "Entrar").font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(Theme.onPrimary)
                    .opacity(canSubmit ? 1 : 0.5)
                }
                .buttonStyle(.pressable)
                .disabled(!canSubmit || loading)

                Text("Seus dados ficam guardados só neste aparelho, protegidos pelo Keychain do iOS.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(
            ZStack {
                Theme.bg
                Circle().fill(Theme.accent.opacity(0.16)).frame(width: 440).blur(radius: 130).offset(y: -320)
            }
            .ignoresSafeArea()
        )
    }

    private var canSubmit: Bool {
        !server.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty
    }

    private func field(_ title: String, text: Binding<String>, icon: String, field: Field, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Theme.muted).frame(width: 22)
            TextField(title, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: field)
                .submitLabel(.next)
                .onSubmit { advance(from: field) }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .foregroundStyle(.white)
    }

    private func advance(from field: Field) {
        switch field {
        case .name: focus = .server
        case .server: focus = .user
        case .user: focus = .pass
        case .pass: submit()
        }
    }

    private func pasteM3U() {
        guard let text = UIPasteboard.general.string, let acc = Account.fromM3U(text) else {
            error = "Não encontrei um link M3U válido copiado. Ele deve conter username= e password=."
            return
        }
        error = nil
        server = acc.server
        username = acc.username
        password = acc.password
        if name.isEmpty { name = acc.name }
    }

    private func submit() {
        guard canSubmit, !loading else { return }
        focus = nil
        error = nil
        loading = true
        let account = Account(name: name,
                              server: server,
                              username: username.trimmingCharacters(in: .whitespaces),
                              password: password)
        Task {
            do {
                try await lib.login(account)
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            loading = false
        }
    }
}
