import Foundation
@main struct Harness {
 @MainActor static func main() async throws {
  let phone = PhoneBridge()
  phone.start()
  for _ in 0..<50 { if !phone.links.isEmpty { break }; try await Task.sleep(nanoseconds: 100_000_000) }
  guard let link = phone.links.first else { print("FAILED: No LAN address"); return }
  try link.write(toFile: ".build/phone-test-link.txt", atomically: true, encoding: .utf8)
  var sent = false
  for _ in 0..<500 {
   if phone.ready && !sent {
    sent = true; _ = phone.toggle()
    try await Task.sleep(nanoseconds: 500_000_000)
    _ = phone.play([180,180,540])
    try await Task.sleep(nanoseconds: 500_000_000)
    phone.stop()
   }
   if FileManager.default.fileExists(atPath: ".build/phone-test-finished") { break }
   try await Task.sleep(nanoseconds: 100_000_000)
  }
  phone.shutdown(); print("PHONE_TRANSPORT_HARNESS_FINISHED")
 }
}
