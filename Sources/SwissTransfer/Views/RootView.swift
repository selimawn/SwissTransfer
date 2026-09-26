import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Wallpaper()
            card
                .padding(48)
        }
        .frame(minWidth: 960, minHeight: 700)
        .preferredColorScheme(.light)
        .dropDestination(for: URL.self) { urls, _ in
            model.importFiles(urls)
            return true
        } isTargeted: { targeted in
            model.isTargeted = targeted
        }
        .onAppear(perform: styleWindows)
        .task {
            try? await Task.sleep(for: .milliseconds(200))
            styleWindows()
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            BrandHeader()
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 16)
            Rectangle()
                .fill(Theme.line)
                .frame(height: 1)
            Group {
                switch model.step {
                case .welcome:
                    WelcomePane(model: model)
                case .email:
                    EmailPane(model: model)
                case .code:
                    CodePane(model: model)
                case .drop:
                    DropPane(model: model)
                case .compose, .uploading:
                    ComposePane(model: model)
                case .done:
                    DonePane(model: model)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, minHeight: 500, alignment: .top)
        }
        .frame(width: 480)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 36, y: 16)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(model.isTargeted ? Theme.brand : .clear, lineWidth: 3)
        }
        .animation(.easeInOut(duration: 0.2), value: model.step)
    }

    private func styleWindows() {
        for window in NSApp.windows {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.backgroundColor = .black
            window.styleMask.insert(.fullSizeContentView)
        }
    }
}
