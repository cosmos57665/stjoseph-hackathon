import AppKit
import Combine
import Network
import Darwin

/// A short-lived LAN receiver. Only numeric haptic patterns cross this connection.
@MainActor final class PhoneBridge: ObservableObject {
    @Published private(set) var links: [String] = []
    @Published private(set) var ready = false
    @Published private(set) var enabled = false
    @Published private(set) var status = "Connect an Android phone on the same Wi-Fi."
    var onDisconnect: (() -> Void)?
    private var listener: NWListener?
    private var clients: [UUID: NWConnection] = [:]
    private var stream: NWConnection?
    private var streamID: UUID?
    private var token = UUID().uuidString + UUID().uuidString
    private var lastReady = Date.distantPast
    private var timer: Timer?
    private(set) var port: UInt16?

    func start() {
        guard listener == nil else { return }
        token = UUID().uuidString + UUID().uuidString
        do {
            let server = try NWListener(using: .tcp, on: .any)
            listener = server
            server.stateUpdateHandler = { [weak self, weak server] state in
                Task { @MainActor in
                guard let self, self.listener === server else { return }
                switch state {
                case .ready:
                    guard let port = server?.port?.rawValue else { return }
                    self.port = port
                    self.links = Self.addresses().map { "http://\($0):\(port)/?token=\(self.token)" }
                    self.status = self.links.isEmpty ? "No Wi-Fi address found. Connect both devices to the same Wi-Fi and restart pairing." : "Open a pairing link on Android Chrome, then tap Enable vibration."
                case .failed:
                    self.shutdown(); self.status = "Could not start pairing. Check macOS Local Network / firewall access and retry."
                default: break
                }
            }
            }
            server.newConnectionHandler = { [weak self] connection in Task { @MainActor in self?.accept(connection) } }
            server.start(queue: .main)
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if self.ready && Date().timeIntervalSince(self.lastReady) > 5 { self.lostPhone() }
                    self.emit(["heartbeat": true])
                }
            }
            status = "Starting local pairing…"
        } catch { status = "Could not start the local connection. Try again." }
    }

    @discardableResult func toggle() -> Bool {
        if enabled { emit(["pattern": [0]]); enabled = false; status = "Output: Mac trackpad."; return false }
        guard ready, stream != nil else { start(); status = "Pair your phone and tap Enable vibration first."; return false }
        enabled = true; status = "Output: Android phone. Keep Chrome visible and the screen awake."
        emit(["pattern": [100, 120, 100]])
        return true
    }
    @discardableResult func play(_ pattern: [Int]) -> Bool {
        guard enabled, ready, stream != nil else { return false }
        guard Self.validPattern(pattern) else { return false }
        emit(["pattern": pattern]); return true
    }
    func stop() { if enabled { emit(["pattern": [0]]) } }
    func test() {
        guard ready else { status = "Tap Enable vibration on the phone first."; return }
        emit(["pattern": [180, 180, 540]])
    }
    func shutdown() {
        emit(["pattern": [0]])
        listener?.cancel(); listener = nil
        timer?.invalidate(); timer = nil
        for connection in clients.values { connection.cancel() }
        clients = [:]; stream = nil; streamID = nil; links = []; port = nil
        let wasEnabled = enabled; enabled = false; ready = false
        status = "Phone disconnected. Output: Mac trackpad."
        if wasEnabled { onDisconnect?() }
    }
    private func lostPhone() {
        let wasEnabled = enabled
        enabled = false; ready = false; lastReady = .distantPast
        status = "Phone unavailable. Playback paused; output returned to Mac. Re-enable on the phone."
        if wasEnabled { onDisconnect?() }
    }
    static func validPattern(_ pattern: [Int]) -> Bool {
        !pattern.isEmpty && pattern.count <= 64 && pattern.allSatisfy { (0...2000).contains($0) } && pattern.reduce(0, +) <= 15000
    }
    private func emit(_ payload: [String: Any]) {
        guard let stream, let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        stream.send(content: Data("data: \(String(decoding: data, as: UTF8.self))\n\n".utf8), completion: .contentProcessed { [weak self, weak stream] error in
            Task { @MainActor in
                if error != nil, let self, self.stream === stream { self.lostPhone(); self.stream = nil }
            }
        })
    }
    private func accept(_ connection: NWConnection) {
        guard clients.count < 24 else { connection.cancel(); return }
        let id = UUID(); clients[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
            guard let self else { return }
            if case .failed = state { self.close(id) }
            if case .cancelled = state { self.close(id) }
        }
        }
        connection.start(queue: .main)
        receive(connection, id: id, buffer: Data())
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self, weak connection] in
            guard let self, self.streamID != id else { return }; connection?.cancel(); self.clients.removeValue(forKey: id)
        }
    }
    private func close(_ id: UUID) {
        clients.removeValue(forKey: id)
        if streamID == id { stream = nil; streamID = nil; lostPhone() }
    }
    private func receive(_ connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            Task { @MainActor in
            guard let self else { return }
            var bytes = buffer; if let data { bytes.append(data) }
            guard bytes.count <= 8192, error == nil else { connection.cancel(); return }
            guard let request = String(data: bytes, encoding: .utf8), request.contains("\r\n\r\n") else {
                if complete { connection.cancel() } else { self.receive(connection, id: id, buffer: bytes) }; return
            }
            let first = request.components(separatedBy: "\r\n")[0].split(separator: " ")
            guard first.count == 3, first[0] == "GET", let parts = URLComponents(string: String(first[1])),
                  parts.scheme == nil, parts.host == nil,
                  parts.queryItems?.first(where: { $0.name == "token" })?.value == self.token else {
                self.respond(connection, status: "403 Forbidden", type: "text/plain", body: "Pair again from Luma Touch."); return
            }
            switch parts.path {
            case "/": self.respond(connection, type: "text/html; charset=utf-8", body: Self.page)
            case "/events":
                self.stream?.cancel(); self.lostPhone()
                self.stream = connection; self.streamID = id
                let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-store\r\nConnection: keep-alive\r\nX-Content-Type-Options: nosniff\r\n\r\n: connected\n\n"
                connection.send(content: Data(headers.utf8), completion: .contentProcessed { _ in })
            case "/ready":
                if self.stream != nil { self.ready = true; self.lastReady = Date(); if !self.enabled { self.status = "Phone ready. Press Option–Z to select phone output." } }
                self.respond(connection, type: "application/json", body: "{\"ready\":\(self.ready)}")
            case "/off": self.stop(); self.lostPhone(); self.respond(connection, type: "text/plain", body: "Stopped")
            default: self.respond(connection, status: "404 Not Found", type: "text/plain", body: "Not found")
            }
        }
    }
    }
    private func respond(_ connection: NWConnection, status: String = "200 OK", type: String, body: String) {
        let data = Data(body.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(data.count)\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + data, completion: .contentProcessed { _ in connection.cancel() })
    }
    static func addresses() -> [String] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return [] }
        defer { freeifaddrs(list) }
        var result: [String] = []; var cursor = list
        while let item = cursor {
            defer { cursor = item.pointee.ifa_next }
            guard let address = item.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  String(cString: item.pointee.ifa_name).hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let value = String(cString: host)
                if !value.hasPrefix("127.") { result.append(value) }
            }
        }
        return Array(Set(result)).sorted()
    }
    static let page = #"""
<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Luma Touch · Phone</title>
<style>body{margin:0;background:linear-gradient(145deg,#f7e5d3,#c0dae8);font:18px system-ui;color:#203645;min-height:100vh}main{max-width:520px;margin:auto;padding:34px 24px}h1{font-size:36px;letter-spacing:-1px}section{padding:24px;background:#ffffff88;border:1px solid white;border-radius:24px}button{width:100%;padding:20px;margin:8px 0;border:0;border-radius:15px;font:600 19px system-ui;background:#366fab;color:white}#stop{background:#fff;color:#203645}p{line-height:1.6}small{display:block;line-height:1.5;color:#435e6d}</style>
<main><p>LUMA TOUCH · ANDROID</p><h1>Feel every word.</h1><section><p id="status" role="status" aria-live="polite">Tap Enable, then press Option–Z on your Mac.</p><button id="enable">Enable vibration</button><button id="test">Test dot and dash</button><button id="stop">Stop & disconnect</button></section><p>Keep this page visible and your phone awake. Both devices must stay on the same Wi-Fi.</p><small>Only vibration timings arrive here. Your API keys and PDF text stay off this page. The phone controls vibration strength; browser or device settings may prevent vibration. Use Chrome on Android and test before studying.</small></main>
<script>
const token=new URLSearchParams(location.search).get('token'), status=document.getElementById('status');
let source=null, enabled=false, lastBeat=0;
const url=path=>path+'?token='+encodeURIComponent(token||'');
const cancel=()=>{if(navigator.vibrate)navigator.vibrate(0);};
function stop(){enabled=false;cancel();if(source)source.close();source=null;fetch(url('/off')).catch(()=>{});status.textContent='Stopped. Tap Enable to reconnect.';}
function arm(){
 if(!navigator.vibrate){status.textContent='Vibration is not supported here. Use Chrome on an Android phone.';return;}
 if(!navigator.vibrate([120,120,360])){status.textContent='The browser blocked vibration. Check phone settings and try again.';return;}
 if(source)source.close();enabled=true;lastBeat=Date.now();source=new EventSource(url('/events'));
 source.onopen=()=>{fetch(url('/ready')).catch(()=>{});status.textContent='Ready. Press Option–Z on your Mac, then play a line.';};
 source.onmessage=e=>{try{const data=JSON.parse(e.data);lastBeat=Date.now();if(data.pattern&&enabled&&!document.hidden){if(!Array.isArray(data.pattern)||data.pattern.length>64||data.pattern.some(n=>!Number.isInteger(n)||n<0||n>2000))return;navigator.vibrate(data.pattern);}}catch{}};
 source.onerror=()=>{stop();status.textContent='Connection lost. Reopen pairing on the Mac, then tap Enable.';};
}
document.getElementById('enable').onclick=arm;
document.getElementById('test').onclick=()=>{status.textContent=navigator.vibrate&&navigator.vibrate([180,180,540])?'Test requested: short, then long. Can you feel both?':'Vibration unavailable or blocked.';};
document.getElementById('stop').onclick=stop;
document.addEventListener('visibilitychange',()=>{if(document.hidden)stop();});
window.addEventListener('pagehide',()=>{cancel();fetch(url('/off'),{keepalive:true}).catch(()=>{});});
setInterval(()=>{if(!enabled)return;if(Date.now()-lastBeat>4000){stop();status.textContent='Connection timed out. Tap Enable to reconnect.';return;}fetch(url('/ready')).catch(()=>{});},1500);
</script></html>
"""#
}
