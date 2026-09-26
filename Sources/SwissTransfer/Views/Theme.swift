import AppKit
import SwiftUI

enum Theme {
    static let brand = Color(red: 0x23 / 255, green: 0xA6 / 255, blue: 0x62 / 255)
    static let brandDark = Color(red: 0x11 / 255, green: 0x6B / 255, blue: 0x40 / 255)
    static let infomaniak = Color(red: 0x00 / 255, green: 0x98 / 255, blue: 1)
    static let ink = Color(red: 0x15 / 255, green: 0x17 / 255, blue: 0x1E / 255)
    static let muted = Color(red: 0x6E / 255, green: 0x74 / 255, blue: 0x86 / 255)
    static let line = Color.black.opacity(0.08)
    static let field = Color(red: 0.965, green: 0.97, blue: 0.98)
    static let danger = Color(red: 0.72, green: 0.16, blue: 0.12)
    static let terms = URL(string: "https://welcome.infomaniak.com/api/web-components/1/cgu/latest?id=94&locale=fr_FR")!
}

struct Wallpaper: View {
    var body: some View {
        GeometryReader { geo in
            if let url = Bundle.main.url(forResource: "wallpaper", withExtension: "jpg"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.72, blue: 0.38),
                        Color(red: 0.16, green: 0.28, blue: 0.14)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }
}

struct BrandHeader: View {
    var body: some View {
        HStack(spacing: 14) {
            Text("infomaniak")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Theme.infomaniak)
                .tracking(-0.6)
            Rectangle()
                .fill(Color.black.opacity(0.12))
                .frame(width: 1, height: 22)
            HStack(spacing: 8) {
                SwissTransferLogo(side: 40)
                Text("SwissTransfer")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct SwissTransferLogo: View {
    var side: CGFloat = 28

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: "swiss-transfer-logo", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                    .fill(Theme.brand)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.22, style: .continuous))
    }
}

struct BrandButton: View {
    var title: String
    var busy = false
    var enabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if busy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .foregroundStyle(.white)
        }
        .buttonStyle(BrandButtonStyle(enabled: enabled && !busy))
        .disabled(!enabled || busy)
        .onHover { inside in
            if inside, enabled { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

private struct BrandButtonStyle: ButtonStyle {
    var enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed && enabled ? Theme.brandDark : Theme.brand,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .opacity(enabled ? 1 : 0.45)
    }
}

struct LineField: View {
    var placeholder: String
    @Binding var text: String
    var secure = false

    var body: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 15))
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.line)
        }
    }
}

struct BannerText: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.danger)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct TermsLink: View {
    var body: some View {
        Button("Conditions d’utilisation") {
            NSWorkspace.shared.open(Theme.terms)
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundStyle(Theme.muted)
        .underline()
        .onHover { inside in
            if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

struct MarkButton: View {
    var systemName: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
        }
        .buttonStyle(MarkButtonStyle())
        .onHover { inside in
            if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

private struct MarkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? Theme.brandDark : Theme.brand,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
    }
}
