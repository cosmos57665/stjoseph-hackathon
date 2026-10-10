import SwiftUI
import CoreImage.CIFilterBuiltins

struct PhonePairingView: View {
    @ObservedObject var phone: PhoneBridge
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Feel it on your Android", systemImage: "iphone.radiowaves.left.and.right").font(.title2.weight(.medium))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("1. Connect your phone and Mac to the same Wi-Fi.\n2. Scan this code in your phone camera and open it in Chrome.\n3. Tap Enable vibration, then press ⌥Z on your Mac.")
                .lineSpacing(6)
            HStack(alignment: .top, spacing: 20) {
                if let link = phone.links.first, let qr = qr(link) {
                    Image(nsImage: qr).interpolation(.none).resizable().frame(width: 190, height: 190)
                        .padding(12).background(.white).accessibilityLabel("Phone pairing QR code; pairing links follow")
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text(phone.status).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text("Keep the phone screen awake and this page visible. ⌥Z toggles between the phone and Mac; playback pauses when switching.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    Button("Test phone: dot, dash") { phone.test() }.disabled(!phone.ready)
                    Button("Stop pairing") { phone.shutdown() }
                    Button("Start / restart pairing") { phone.shutdown(); phone.start() }
                }
            }
            ForEach(phone.links, id: \.self) { link in
                Text(link).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            }
            Text("Pairing links are temporary. Anyone with the link on this network can receive haptic timings. No keys or PDF text are sent. Local HTTP is intended for your trusted Wi-Fi. School guest Wi-Fi may block connections between devices.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(28).frame(width: 660)
            .onAppear { phone.start() }
    }
    private func qr(_ value: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(value.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

struct PhoneOutputBadge: View {
    @ObservedObject var phone: PhoneBridge
    var body: some View {
        Label(phone.enabled ? "Android output · ⌥Z" : "Mac output · ⌥Z", systemImage: phone.enabled ? "iphone" : "hand.draw")
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.ocean)
    }
}
