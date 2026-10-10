import Foundation

@MainActor final class VisualConversationTests {
    func run() async throws {
        // Pure session-state checks: no microphone, speech permissions or audible output.
        let conversation = VisualConversation()
        expectFalse(conversation.isListening)
        expectFalse(conversation.isPreparing)
        expectFalse(conversation.isSpeaking)
        expectFalse(conversation.shareDraft())
        conversation.draft = " \n "
        expectFalse(conversation.hasDraft)
        expectFalse(conversation.shareDraft())
        conversation.usePhrase("Please type your reply.")
        expectTrue(conversation.hasDraft)
        expectEqual(conversation.draft, "Please type your reply.")
        expectTrue(conversation.shareDraft())
        expectEqual(conversation.displayedMessage, "Please type your reply.")
        expectTrue(conversation.showMessage)
        expectEqual(conversation.messages.count, 1)
        conversation.shareDraft()
        expectEqual(conversation.messages.count, 1)
        conversation.draft = "  Thank you.\n"
        conversation.shareDraft()
        expectEqual(conversation.messages.last?.text, "Thank you.")
        let original = conversation.captureGeneration
        conversation.receiveCaption("Partner reply", generation: original)
        expectEqual(conversation.captions, "Partner reply")
        conversation.stopListening()
        conversation.receiveCaption("Stale transcript", generation: original)
        expectEqual(conversation.captions, "Partner reply")
        expectFalse(conversation.isListening)
        expectFalse(conversation.isPreparing)
        expectEqual(conversation.status, "Microphone off")
        conversation.receiveCaption(String(repeating: "A", count: 15000), generation: conversation.captureGeneration)
        expectEqual(conversation.captions.count, 12000)
        for index in 0..<60 {
            conversation.draft = "Message \(index)"
            conversation.shareDraft()
        }
        expectEqual(conversation.messages.count, 50)
        expectEqual(conversation.messages.first?.text, "Message 10")
        conversation.draft = String(repeating: "B", count: 5000)
        conversation.shareDraft()
        expectEqual(conversation.displayedMessage.count, 4000)
        let beforeClear = conversation.captureGeneration
        conversation.clear()
        conversation.receiveCaption("Late after clear", generation: beforeClear)
        expectEqual(conversation.captions, "")
        expectEqual(conversation.draft, "")
        expectEqual(conversation.messages.count, 0)
        expectEqual(conversation.displayedMessage, "")
        expectFalse(conversation.showMessage)
        expectFalse(conversation.isSpeaking)
        expectTrue(Set(VisualConversation.phrases).count == VisualConversation.phrases.count)
    }
}
