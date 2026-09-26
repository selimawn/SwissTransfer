import SwiftUI

struct DropPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 36)
            Button {
                model.pickFiles()
            } label: {
                VStack(spacing: 18) {
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Theme.brand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(spacing: 6) {
                        Text("Cliquer pour ajouter vos fichiers")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text(model.isTargeted ? "Déposez pour ajouter" : "ou déposez-les ici")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { inside in
                if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            }
            Spacer(minLength: 36)
            TermsLink()
                .padding(.bottom, 6)
        }
    }
}

struct ComposePane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(Format.count(model.files.count)) · \(Format.bytes(model.totalSize))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if model.step != .uploading {
                    Button("Ajouter") { model.pickFiles() }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.brand)
                }
            }
            .padding(.top, 18)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.files) { file in
                        FileRow(file: file, locked: model.step == .uploading) {
                            model.remove(file)
                        }
                    }
                }
            }
            .frame(maxHeight: 168)

            TextField("Message pour le destinataire", text: $model.message, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(2...4)
                .padding(12)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.line)
                }
                .disabled(model.step == .uploading)

            if model.protect {
                LineField(placeholder: "Mot de passe", text: $model.password, secure: true)
                    .disabled(model.step == .uploading)
            }
            Button(model.protect ? "Retirer le mot de passe" : "Protéger par mot de passe") {
                model.protect.toggle()
                if !model.protect { model.password = "" }
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.brand)
            .disabled(model.step == .uploading)

            HStack(spacing: 10) {
                OptionMenu(title: "Valable", selection: $model.days, choices: [
                    (1, "1 jour"), (3, "3 jours"), (7, "7 jours"), (15, "15 jours"), (30, "30 jours")
                ])
                .disabled(model.step == .uploading)
                OptionMenu(title: "Téléchargements", selection: $model.maxDownloads, choices: [
                    (1, "1"), (20, "20"), (100, "100"), (200, "200"), (250, "250")
                ])
                .disabled(model.step == .uploading)
            }

            HStack {
                Text("Depuis \(model.email)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                Spacer()
                if model.step != .uploading {
                    Button("Changer") { Task { await model.signOut() } }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.brand)
                }
            }

            if model.step == .uploading {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: model.progress.fraction)
                        .tint(Theme.brand)
                    HStack {
                        Text(model.progress.detail.isEmpty ? "Envoi…" : model.progress.detail)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int((model.progress.fraction * 100).rounded())) %")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    Text("\(Format.bytes(model.progress.bytesSent)) / \(Format.bytes(model.progress.bytesTotal))")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                    Button("Annuler") { model.cancelUpload() }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.danger)
                }
            } else {
                if let banner = model.banner {
                    BannerText(text: banner)
                }
                BrandButton(title: "Transférer", enabled: model.canTransfer) {
                    model.transfer()
                }
            }
        }
        .padding(.bottom, 8)
    }
}

struct DonePane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 28)
            Image(systemName: "checkmark")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Theme.brand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text("Transfert prêt")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 18)
            Text("Le lien est valable selon les options choisies.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .padding(.top, 6)
            Text(model.downloadURL ?? "")
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.top, 20)
            HStack(spacing: 10) {
                BrandButton(title: model.linkCopied ? "Copié" : "Copier le lien") {
                    model.copyLink()
                }
                Button("Ouvrir") { model.openLink() }
                    .buttonStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.brand)
                    .frame(height: 46)
                    .frame(maxWidth: .infinity)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(.top, 14)
            Button("Nouveau transfert") { model.newTransfer() }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.muted)
                .padding(.top, 16)
            Spacer(minLength: 12)
        }
    }
}

private struct FileRow: View {
    var file: LocalFile
    var locked: Bool
    var remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(Format.bytes(file.size))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            if !locked {
                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct OptionMenu: View {
    var title: String
    @Binding var selection: Int
    var choices: [(Int, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            Picker(title, selection: $selection) {
                ForEach(choices, id: \.0) { choice in
                    Text(choice.1).tag(choice.0)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
