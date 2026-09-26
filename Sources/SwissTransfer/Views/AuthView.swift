import SwiftUI

struct WelcomePane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 28)
            MarkButton(systemName: "envelope.fill") {
                model.beginAuthentication()
            }
            Text("Confirmez votre e-mail")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 22)
            Text("Aucun compte n’est nécessaire, et aucun compte ne sera créé. SwissTransfer envoie seulement un code à votre adresse.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .padding(.top, 8)
            if !model.files.isEmpty {
                Text("\(Format.count(model.files.count)) en attente")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.brand)
                    .padding(.top, 12)
            }
            BrandButton(title: "S’authentifier chez Infomaniak") {
                model.beginAuthentication()
            }
            .padding(.top, 26)
            Spacer(minLength: 28)
            TermsLink()
                .padding(.bottom, 6)
        }
    }
}

struct EmailPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 36)
            Text("Votre adresse e-mail")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("Un code de 6 caractères sera envoyé à cette adresse. Cela ne crée pas de compte.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .padding(.top, 8)
            LineField(placeholder: "nom@exemple.com", text: $model.email)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                .onSubmit { Task { await model.sendCode() } }
                .padding(.top, 22)
            if let banner = model.banner {
                BannerText(text: banner)
                    .padding(.top, 12)
            }
            BrandButton(title: "Recevoir le code", busy: model.busy) {
                Task { await model.sendCode() }
            }
            .padding(.top, 16)
            backLink("Retour") {
                model.banner = nil
                model.step = .welcome
            }
            .padding(.top, 18)
            Spacer(minLength: 28)
        }
    }
}

struct CodePane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 36)
            Text("Entrez le code")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("Envoyé à \(model.email). Six caractères, sans créer de compte.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            TextField("ABC123", text: $model.code)
                .textFieldStyle(.plain)
                .font(.system(size: 28, weight: .medium, design: .monospaced))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.ink)
                .textContentType(.oneTimeCode)
                .frame(height: 56)
                .padding(.horizontal, 12)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.line)
                }
                .padding(.top, 22)
                .onSubmit { Task { await model.confirm() } }
                .onChange(of: model.code) { _, newValue in
                    let cleaned = String(newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                    if cleaned != newValue {
                        model.code = cleaned
                        return
                    }
                    if cleaned.count == 6 {
                        Task { await model.confirm() }
                    }
                }
            if let banner = model.banner {
                BannerText(text: banner)
                    .padding(.top, 12)
            }
            BrandButton(
                title: "Confirmer",
                busy: model.busy,
                enabled: model.code.filter { $0.isLetter || $0.isNumber }.count == 6
            ) {
                Task { await model.confirm() }
            }
            .padding(.top, 16)
            textButton("Renvoyer le code") {
                Task { await model.sendCode() }
            }
            .padding(.top, 16)
            .disabled(model.busy)
            backLink("Modifier l’adresse") {
                model.code = ""
                model.banner = nil
                model.step = .email
            }
            .padding(.top, 10)
            .disabled(model.busy)
            Spacer(minLength: 28)
        }
    }
}

@MainActor
private func backLink(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 5) {
            Image(systemName: "chevron.left")
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(Theme.muted)
    }
    .buttonStyle(.plain)
}

@MainActor
private func textButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(title, action: action)
        .buttonStyle(.plain)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Theme.brand)
}
