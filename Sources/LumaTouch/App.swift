import SwiftUI

@main struct LumaTouchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = Workspace()
    var body: some Scene {
        WindowGroup("Luma Touch") {
            ContentView(model: model)
                .frame(minWidth: 1070, minHeight: 770)
                .preferredColorScheme(model.dark ? .dark : .light)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    if model.pages.isEmpty { model.loadStarter() }
                    if CommandLine.arguments.contains("--verify-ui") { verifyUI() }
                }
        }
        .defaultSize(width: 1190, height: 880)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { Button("Import PDF…", action: model.importPDF).keyboardShortcut("o", modifiers: .command).disabled(model.busy) }
            CommandMenu("Playback") {
                Button("Play / Pause") { model.player.isPlaying ? model.player.pause() : model.player.play() }.keyboardShortcut("p", modifiers: [.command])
                Button("Stop all playback") { model.stopAll() }.keyboardShortcut(".", modifiers: [.command])
                Button("Previous word") { model.player.skipWord(-1) }.keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                Button("Next word") { model.player.skipWord(1) }.keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            }
            CommandGroup(replacing: .help) { Button("Morse reference sheet", action: model.openReference) }
        }
    }

    // Deterministic local UI verification without touching keys or sending requests.
    private func verifyUI() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            while model.busy { try? await Task.sleep(nanoseconds: 200_000_000) }
            let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("verification")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            @MainActor func snapshot(_ name: String) {
                guard let window = NSApp.windows.first(where: { $0.isVisible }), let view = window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: dir.appendingPathComponent(name + ".png")) }
            }
            snapshot("reader")
            model.screen = .practice
            try? await Task.sleep(nanoseconds: 700_000_000)
            snapshot("practice")
            model.screen = .connections
            try? await Task.sleep(nanoseconds: 700_000_000)
            snapshot("connections")
            model.dark = true
            try? await Task.sleep(nanoseconds: 700_000_000)
            snapshot("connections-dark")
            model.dark = false
            model.screen = .reader
            let result: [String: Any] = ["pages": model.pages.count, "title": model.title, "morseSymbols": model.player.symbols.count,
                                       "providers": Provider.allCases.map(\.rawValue), "networkRequests": 0]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted) { try? data.write(to: dir.appendingPathComponent("ui-result.json")) }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct ContentView: View {
    @ObservedObject var model: Workspace
    var body: some View {
        ZStack {
            Wallpaper()
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path").font(.system(size: 23, weight: .medium)).foregroundStyle(Color.ocean)
                    Text("luma").font(.system(size: 24, weight: .semibold, design: .rounded)).tracking(-1)
                    Text("TOUCH").font(.system(size: 9, weight: .bold)).tracking(2.5).foregroundStyle(.secondary).padding(.leading, 1)
                    Spacer()
                    Text("A different way to learn.").font(.system(size: 12)).foregroundStyle(.secondary)
                    Rectangle().fill(.primary.opacity(0.12)).frame(width: 1, height: 18).padding(.horizontal, 8)
                    Button { model.dark.toggle() } label: { Image(systemName: model.dark ? "sun.max" : "moon") }.buttonStyle(.plain).help("Toggle light and dark appearance").accessibilityLabel("Toggle light and dark appearance")
                    Button { model.solid.toggle() } label: { Image(systemName: model.solid ? "square.fill" : "square.lefthalf.filled") }.buttonStyle(.plain).help("Toggle solid surfaces").accessibilityLabel("Toggle solid surfaces")
                }.padding(.horizontal, 34).padding(.top, 31).padding(.bottom, 20)
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 9) {
                        Eyebrow(text: "Your space").padding(.bottom, 13).padding(.leading, 11)
                        ForEach(Screen.allCases, id: \.self) { screen in
                            Button {
                                model.stopAll()
                                model.screen = screen
                            } label: {
                                HStack(spacing: 11) {
                                    Image(systemName: screen.icon).font(.system(size: 16)).frame(width: 21)
                                    Text(screen.rawValue).font(.system(size: 13, weight: model.screen == screen ? .semibold : .regular))
                                    Spacer(minLength: 0)
                                }.padding(.horizontal, 12).padding(.vertical, 13)
                                    .background(.white.opacity(model.screen == screen ? 0.40 : 0), in: RoundedRectangle(cornerRadius: 13))
                            }.buttonStyle(.plain).accessibilityAddTraits(model.screen == screen ? [.isSelected] : [])
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "hand.point.up.braille").font(.system(size: 24)).foregroundStyle(Color.ocean)
                            Text("Small signals.\nMeaningful learning.").font(.system(size: 13, weight: .medium)).lineSpacing(4)
                            Text("An inclusive learning prototype. Built for curiosity.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                        }.padding(.horizontal, 10).padding(.bottom, 20)
                        Divider()
                        Button { model.screen = .connections } label: {
                            HStack(spacing: 7) {
                                Circle().fill(model.activeKey ? Color.green : Color.orange).frame(width: 6, height: 6)
                                Text(model.activeKey ? "\(model.provider.rawValue) key ready" : "Offline mode").font(.system(size: 11))
                            }.padding(10)
                        }.buttonStyle(.plain)
                    }.padding(18).frame(width: 180)
                    Rectangle().fill(.white.opacity(0.4)).frame(width: 1)
                    Group {
                        switch model.screen {
                        case .reader: ReaderView(model: model)
                        case .practice: PracticeView(model: model, player: model.practicePlayer)
                        case .connections: ConnectionsView(model: model)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }.glass(25, solid: model.solid).padding(.horizontal, 24)
                HStack(spacing: 5) {
                    ForEach(Screen.allCases, id: \.self) { screen in
                        DockButton(icon: screen.icon, title: screen.rawValue, selected: model.screen == screen) { model.stopAll(); model.screen = screen }
                    }
                    Rectangle().fill(.primary.opacity(0.12)).frame(width: 1, height: 31).padding(.horizontal, 5)
                    DockButton(icon: "doc.text", title: "Morse sheet", selected: false, action: model.openReference)
                }.padding(7).glass(24, solid: model.solid).padding(.vertical, 18)
            }
        }.tint(Color.ocean)
            .alert("Something needs attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK") { model.error = nil }
            } message: { Text(model.error ?? "") }
            .sheet(isPresented: $model.showPDF) {
                VStack(spacing: 12) {
                    HStack { Text("Original PDF").font(.headline); Spacer(); Button("Done") { model.showPDF = false } }
                    if let url = model.documentURL { OriginalPDF(url: url, page: model.selectedPage) }
                }.padding(20).frame(width: 760, height: 760)
            }
            .sheet(isPresented: $model.showTextEntry) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Your words, made tactile.").font(.title2.weight(.medium))
                    Text("Paste a short passage to read, listen to, or feel. This stays on your Mac.").foregroundStyle(.secondary)
                    TextEditor(text: $model.draft).font(.system(size: 17)).frame(height: 240).accessibilityLabel("Lesson text to import")
                    HStack { Button("Cancel") { model.showTextEntry = false }; Spacer(); Button("Open in reader", action: model.useText).buttonStyle(ActionStyle(prominent: true)).disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }.padding(30).frame(width: 630)
            }
    }
}
