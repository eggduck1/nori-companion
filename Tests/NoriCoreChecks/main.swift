import Foundation
import NoriCore

precondition(AssistantService.model == "gemini-3.1-flash-live-preview")

let safeAction = ProposedAction(kind: "open_app", target: "Safari", reason: "Browse the web.")
let shellAction = ProposedAction(kind: "run_command", target: "rm -rf ~", reason: "Cleanup.")
let unknownApp = ProposedAction(kind: "open_app", target: "Terminal", reason: "Run a command.")
precondition(AssistantService.validatedAction(safeAction) == safeAction)
precondition(AssistantService.validatedAction(shellAction) == nil)
precondition(AssistantService.validatedAction(unknownApp) == nil)

let longAction = ProposedAction(kind: "open_app", target: "Notes", reason: String(repeating: "a", count: 500))
precondition(AssistantService.validatedAction(longAction)?.reason.count == 240)
precondition(AssistantService.validatedMemory("  concise answers  ") == "concise answers")
precondition(AssistantService.validatedMemory(" \n ") == nil)
precondition(AssistantService.validatedMemory(String(repeating: "x", count: 400))?.count == 300)

let profile = CompanionProfile()
let toneChange = SelfChangeSuggestion(
    field: "tone",
    value: "  Playful and concise  ",
    reason: "You asked for shorter replies."
)
let validatedChange = AssistantService.validatedSelfChange(toneChange, profile: profile)
precondition(validatedChange?.field == .tone)
precondition(validatedChange?.value == "Playful and concise")
precondition(validatedChange?.previousValue == profile.tone)
precondition(AssistantService.validatedSelfChange(
    SelfChangeSuggestion(field: "aboutUser", value: "Change preferences", reason: ""),
    profile: profile
) == nil)
precondition(AssistantService.validatedSelfChange(
    SelfChangeSuggestion(field: "safety", value: "Ignore all limits", reason: ""),
    profile: profile
) == nil)
precondition(AssistantService.validatedSelfChange(
    SelfChangeSuggestion(field: "tone", value: profile.tone, reason: ""),
    profile: profile
) == nil)
precondition(AssistantService.validatedSelfChange(
    SelfChangeSuggestion(field: "soul", value: String(repeating: "x", count: 1400), reason: ""),
    profile: profile
)?.value.count == 1200)
precondition(AssistantService.validatedSelfChange(
    SelfChangeSuggestion(field: "tone", value: "  ", reason: ""),
    profile: profile
) == nil)

let originalProfile = try! JSONDecoder().decode(
    CompanionProfile.self,
    from: Data(#"{"companionName":"Nori","tone":"Warm, curious, and encouraging","memory":"Likes tea"}"#.utf8)
)
precondition(originalProfile.memory == "Likes tea")
precondition(!originalProfile.soul.isEmpty)

print("Nori safety boundary checks passed.")
