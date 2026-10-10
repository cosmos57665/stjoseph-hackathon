import SwiftUI

struct ConnectionsView: View {
    @ObservedObject var model: Workspace
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 9) {
                    Eyebrow(text: "Your AI, your choice")
                    Text("A little intelligence.\nA lot more access.").font(.system(size: 37, weight: .medium)).tracking(-1.3)
                    Text("Connect one provider to transcribe PDF pages and simplify lessons.").foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Provider.allCases) { provider in ProviderCard(model: model, provider: provider) }
                }
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: "lock.shield").font(.title2).foregroundStyle(Color.ocean)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Private until you choose AI").font(.headline)
                        Text("Pasted keys stay in memory unless you select Save to Keychain. AI transcription sends page images to the selected provider; Simplify sends the current page text. Their API pricing and data policies apply. Importing, practicing and Morse playback work offline.")
                            .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
                    }
                }.padding(22).glass(solid: model.solid)
                Text("Model availability changes. The model ID is editable; choose a model with image input for PDF transcription. Test connection makes a small billable text request.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(30)
        }
    }
}

struct ProviderCard: View {
    @ObservedObject var model: Workspace
    let provider: Provider
    var key: Binding<String> { Binding(get: { model.keys[provider] ?? "" }, set: {
        model.keys[provider] = $0
        model.connectionMessages[provider] = model.saved.contains(provider) ? "Edited for this session. Save again to update Keychain." : "Key available for this session."
    }) }
    var modelID: Binding<String> { Binding(get: { model.models[provider] ?? provider.defaultModel }, set: {
        model.models[provider] = $0
        UserDefaults.standard.set($0, forKey: "model.\(provider.rawValue)")
        model.connectionMessages[provider] = "Model changed. Test the connection again."
    }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: provider.symbol).font(.system(size: 22)).foregroundStyle(Color.ocean)
                    .frame(width: 44, height: 44).background(.white.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
                Spacer()
                if model.provider == provider { Text("ACTIVE").font(.system(size: 9, weight: .bold)).tracking(1.1).padding(7).background(Color.ocean.opacity(0.12), in: Capsule()) }
            }
            Text(provider.rawValue).font(.system(size: 23, weight: .semibold))
            Text(provider == .gemini ? "Google's multimodal models" : provider == .openRouter ? "Your choice of vision models" : "Fast multimodal inference").font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 7) {
                Text("API key").font(.caption.weight(.semibold))
                SecureField("Paste your \(provider.rawValue) key", text: key).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("\(provider.rawValue) API key")
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Vision model ID").font(.caption.weight(.semibold))
                TextField("Model ID", text: modelID).textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced)).accessibilityLabel("\(provider.rawValue) model ID")
            }
            Button { model.provider = provider; UserDefaults.standard.set(provider.rawValue, forKey: "activeProvider") } label: {
                Label(model.provider == provider ? "Selected provider" : "Use \(provider.rawValue)", systemImage: model.provider == provider ? "checkmark.circle.fill" : "circle")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(ActionStyle(prominent: model.provider == provider))
            HStack {
                Button(model.testing.contains(provider) ? "Testing…" : "Test connection") { model.test(provider) }
                    .disabled(key.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.testing.contains(provider))
                Spacer()
                Link("Get key ↗", destination: provider.keyURL)
            }.font(.caption)
            Divider()
            HStack {
                Button("Save to Keychain") { model.saveKey(provider) }.disabled(key.wrappedValue.isEmpty)
                Spacer()
                Button("Forget") { model.forgetKey(provider) }
            }.font(.system(size: 11))
            Text(model.connectionMessages[provider] ?? (model.saved.contains(provider) ? "Loaded from macOS Keychain." : "No key yet. Paste one above to start."))
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
                .accessibilityLabel("\(provider.rawValue) status: \(model.connectionMessages[provider] ?? "Not connected")")
        }.padding(21).frame(maxWidth: .infinity, alignment: .topLeading).glass(22, solid: model.solid)
    }
}
