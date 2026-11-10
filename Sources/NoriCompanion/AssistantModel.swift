import AppKit
import Combine
import Foundation
import NoriCore

struct ChatTurn: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    var action: ProposedAction?
    var proposedMemory: String?
    var selfChange: ValidatedSelfChange?
    var actionStatus: ActionStatus = .pending
    var memoryAccepted = false
    var selfChangeAccepted = false
    var selfChangeDeclined = false

    enum Role {
        case user
        case assistant
    }

    enum ActionStatus {
        case pending
        case approved
        case declined
    }
}

private struct SelfChangeUndo: Codable {
    let field: ValidatedSelfChange.Field
    let previousValue: String
    let appliedValue: String
}

@MainActor
final class AssistantModel: ObservableObject {
    @Published var turns: [ChatTurn] = []
    @Published var isSending = false
    @Published var errorMessage: String?
    @Published var profile: CompanionProfile
    @Published var hasAPIKey: Bool

    private var apiKey: String?
    private let profileKey = "NoriCompanion.profile.v1"
    private let undoProfileKey = "NoriCompanion.profile.undo.v1"
    @Published private(set) var canUndoSelfChange = false

    init() {
        apiKey = KeychainStore.read()
        hasAPIKey = apiKey != nil
        if let data = UserDefaults.standard.data(forKey: profileKey),
           let saved = try? JSONDecoder().decode(CompanionProfile.self, from: data) {
            profile = saved
        } else {
            profile = CompanionProfile()
        }
        canUndoSelfChange = UserDefaults.standard.data(forKey: undoProfileKey) != nil
    }

    func saveAPIKey(_ key: String) {
        do {
            try KeychainStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines))
            apiKey = KeychainStore.read()
            hasAPIKey = apiKey != nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeAPIKey() {
        do {
            try KeychainStore.delete()
            apiKey = nil
            hasAPIKey = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveProfile(_ next: CompanionProfile) {
        var bounded = next
        bounded.companionName = String(bounded.companionName.prefix(50))
        bounded.soul = String(bounded.soul.prefix(2000))
        bounded.identity = String(bounded.identity.prefix(2000))
        bounded.aboutUser = String(bounded.aboutUser.prefix(2000))
        bounded.memory = String(bounded.memory.suffix(2000))
        profile = bounded
        if let data = try? JSONEncoder().encode(bounded) {
            UserDefaults.standard.set(data, forKey: profileKey)
        }
    }

    func approveSelfChange(for turnID: UUID) {
        guard let index = turns.firstIndex(where: { $0.id == turnID }),
              let change = turns[index].selfChange,
              !turns[index].selfChangeAccepted else {
            return
        }
        guard currentValue(for: change.field, in: profile) == change.previousValue else {
            errorMessage = "Nori’s profile changed since this proposal. Review the current profile and ask again."
            return
        }
        let undo = SelfChangeUndo(
            field: change.field,
            previousValue: change.previousValue,
            appliedValue: change.value
        )
        guard let undoData = try? JSONEncoder().encode(undo) else {
            errorMessage = "Could not save an undo point. The profile was not changed."
            return
        }
        UserDefaults.standard.set(undoData, forKey: undoProfileKey)
        var next = profile
        set(change.value, for: change.field, in: &next)
        saveProfile(next)
        canUndoSelfChange = true
        turns[index].selfChangeAccepted = true
    }

    func declineSelfChange(for turnID: UUID) {
        guard let index = turns.firstIndex(where: { $0.id == turnID }),
              turns[index].selfChange != nil,
              !turns[index].selfChangeAccepted else {
            return
        }
        turns[index].selfChangeDeclined = true
    }

    func undoLastSelfChange() {
        guard let data = UserDefaults.standard.data(forKey: undoProfileKey),
              let undo = try? JSONDecoder().decode(SelfChangeUndo.self, from: data) else {
            errorMessage = "Nori’s previous profile could not be restored."
            return
        }
        guard currentValue(for: undo.field, in: profile) == undo.appliedValue else {
            errorMessage = "That profile field changed after approval. Review it in Nori’s mind before undoing."
            return
        }
        var restored = profile
        set(undo.previousValue, for: undo.field, in: &restored)
        saveProfile(restored)
        UserDefaults.standard.removeObject(forKey: undoProfileKey)
        canUndoSelfChange = false
    }

    private func currentValue(for field: ValidatedSelfChange.Field, in profile: CompanionProfile) -> String {
        switch field {
        case .tone: profile.tone
        case .soul: profile.soul
        case .identity: profile.identity
        }
    }

    private func set(_ value: String, for field: ValidatedSelfChange.Field, in profile: inout CompanionProfile) {
        switch field {
        case .tone: profile.tone = value
        case .soul: profile.soul = value
        case .identity: profile.identity = value
        }
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        guard let apiKey, !apiKey.isEmpty else {
            errorMessage = AssistantError.missingAPIKey.localizedDescription
            return
        }

        turns.append(ChatTurn(role: .user, content: trimmed))
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        let conversation: [(role: String, content: String)] = turns.suffix(24).map {
            ($0.role == .user ? "user" : "assistant", $0.content)
        }
        do {
            let reply = try await AssistantService.send(
                messages: conversation,
                apiKey: apiKey,
                profile: profile
            )
            turns.append(ChatTurn(
                role: .assistant,
                content: reply.answer,
                action: reply.action,
                proposedMemory: reply.proposedMemory,
                selfChange: reply.selfChange
            ))
        } catch {
            turns.removeLast()
            errorMessage = error.localizedDescription
        }
    }

    func resolveAction(for turnID: UUID, approved: Bool) {
        guard let index = turns.firstIndex(where: { $0.id == turnID }),
              let action = turns[index].action,
              turns[index].actionStatus == .pending else {
            return
        }
        guard approved else {
            turns[index].actionStatus = .declined
            return
        }
        guard let bundleID = AssistantService.allowedApps[action.target],
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            errorMessage = "\(action.target) is not available on this Mac."
            return
        }
        turns[index].actionStatus = .approved
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    self.errorMessage = "Could not open \(action.target): \(error.localizedDescription)"
                }
            }
        }
    }

    func approveMemory(for turnID: UUID) {
        guard let index = turns.firstIndex(where: { $0.id == turnID }),
              let proposed = turns[index].proposedMemory,
              !turns[index].memoryAccepted else {
            return
        }
        let addition = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !addition.isEmpty else { return }
        let nextMemory = profile.memory.isEmpty ? addition : "\(profile.memory)\n\(addition)"
        var next = profile
        next.memory = String(nextMemory.suffix(2000))
        saveProfile(next)
        turns[index].memoryAccepted = true
    }

    func startNewChat() {
        turns = []
        errorMessage = nil
    }

    func resetLocalData() {
        do {
            try KeychainStore.delete()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        for key in UserDefaults.standard.dictionaryRepresentation().keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        turns = []
        profile = CompanionProfile()
        apiKey = nil
        hasAPIKey = false
        canUndoSelfChange = false
        errorMessage = nil
    }
}
