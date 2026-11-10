import SwiftUI
import NoriCore

private enum CompanionSection: String, CaseIterable, Identifiable {
    case chat = "Chat"
    case mind = "Nori’s mind"

    var id: String { rawValue }
}

private enum PersonaSection: String, CaseIterable, Identifiable {
    case soul = "SOUL"
    case identity = "IDENTITY"
    case user = "ABOUT YOU"
    case memory = "MEMORY"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soul: "SOUL.md"
        case .identity: "IDENTITY.md"
        case .user: "USER.md"
        case .memory: "MEMORY.md"
        }
    }

    var description: String {
        switch self {
        case .soul: "The values and boundaries that shape how Nori behaves."
        case .identity: "How Nori describes themself as your digital companion."
        case .user: "Context about you that helps Nori make replies more relevant."
        case .memory: "Things you have chosen to let Nori remember."
        }
    }

    func value(in profile: CompanionProfile) -> String {
        switch self {
        case .soul: profile.soul
        case .identity: profile.identity
        case .user: profile.aboutUser
        case .memory: profile.memory
        }
    }

    func set(_ value: String, in profile: inout CompanionProfile) {
        switch self {
        case .soul: profile.soul = value
        case .identity: profile.identity = value
        case .user: profile.aboutUser = value
        case .memory: profile.memory = value
        }
    }
}

struct CompanionWindow: View {
    @EnvironmentObject private var assistant: AssistantModel
    @EnvironmentObject private var media: LocalMediaServices
    @AppStorage("NoriCompanion.speakReplies") private var speakReplies = true
    @State private var draft = ""
    @State private var showingSettings = false
    @State private var selectedSection: CompanionSection = .chat
    @State private var selectedPersonaSection: PersonaSection = .soul
    @State private var personaDrafts: [PersonaSection: String] = [:]
    @State private var personaBase: [PersonaSection: String] = [:]
    @State private var personaSavedMessage = ""
    @FocusState private var composerFocused: Bool
    @Namespace private var animation

    private let suggestions = [
        "Help me plan my day",
        "Open Safari",
        "Remember that I like concise answers",
        "Change how you speak with me",
    ]

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                Divider().overlay(Color.white.opacity(0.06))
                if selectedSection == .chat {
                    conversation
                    composer
                } else {
                    mindEditor
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.965, green: 0.957, blue: 0.99))

            companionPanel
                .frame(width: 292)
        }
        .background(Color(red: 0.965, green: 0.957, blue: 0.99))
        .preferredColorScheme(.light)
        .sheet(isPresented: $showingSettings) {
            SettingsSheet()
                .environmentObject(assistant)
        }
        .alert("Nori", isPresented: Binding(
            get: { assistant.errorMessage != nil },
            set: { if !$0 { assistant.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { assistant.errorMessage = nil }
        } message: {
            Text(assistant.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("YOUR MAC COMPANION")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(2.2)
                    .foregroundStyle(Color(red: 0.48, green: 0.39, blue: 0.78))
                Text("Hey, I’m \(assistant.profile.companionName).")
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.15, green: 0.14, blue: 0.23))
                Text("A curious mind for the things you want to get done.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Picker("Companion section", selection: $selectedSection) {
                    ForEach(CompanionSection.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 205)
                .padding(.top, 7)
            }
            Spacer()
            if !assistant.turns.isEmpty {
                Button {
                    assistant.startNewChat()
                } label: {
                    Label("New chat", systemImage: "plus")
                }
                .buttonStyle(QuietButtonStyle())
            }
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(QuietButtonStyle())
            .help("Companion settings")
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 19)
        .background(Color.white.opacity(0.92))
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 17) {
                    if assistant.turns.isEmpty {
                        welcome
                            .frame(maxWidth: 560)
                            .frame(maxWidth: .infinity, minHeight: 330)
                    }
                    ForEach(assistant.turns) { turn in
                        MessageBubble(turn: turn) { approved in
                            assistant.resolveAction(for: turn.id, approved: approved)
                        } onApproveMemory: {
                            assistant.approveMemory(for: turn.id)
                        } onApproveSelfChange: {
                            assistant.approveSelfChange(for: turn.id)
                        } onDeclineSelfChange: {
                            assistant.declineSelfChange(for: turn.id)
                        }
                        .id(turn.id)
                        .transition(.move(edge: turn.role == .user ? .trailing : .leading).combined(with: .opacity))
                    }
                    if assistant.isSending {
                        HStack(spacing: 10) {
                            RobotAvatar(size: 30, mood: .thinking)
                            Text("Thinking it through…")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            ProgressView()
                                .controlSize(.small)
                            Spacer()
                        }
                        .frame(maxWidth: 700)
                        .id("thinking")
                    }
                }
                .padding(.horizontal, 25)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: assistant.turns.count) {
                if let last = assistant.turns.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                    if last.role == .assistant && speakReplies {
                        media.speak(last.content)
                    }
                }
            }
            .onChange(of: assistant.isSending) {
                if assistant.isSending {
                    proxy.scrollTo("thinking", anchor: .bottom)
                }
            }
        }
    }

    private var mindEditor: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("A little more about us")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.16, green: 0.15, blue: 0.24))
                Text("Tune Nori’s voice and keep the details you choose to share.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 7) {
                ForEach(PersonaSection.allCases) { section in
                    Button {
                        selectedPersonaSection = section
                        personaSavedMessage = ""
                    } label: {
                        Text(section.rawValue)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(0.7)
                            .foregroundStyle(selectedPersonaSection == section
                                             ? Color(red: 0.38, green: 0.31, blue: 0.68)
                                             : Color(red: 0.46, green: 0.45, blue: 0.53))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(selectedPersonaSection == section
                                        ? Color(red: 0.91, green: 0.88, blue: 0.99)
                                        : Color.white.opacity(0.75))
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .stroke(selectedPersonaSection == section
                                            ? Color(red: 0.8, green: 0.75, blue: 0.95)
                                            : Color.black.opacity(0.055))
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Text(selectedPersonaSection.title)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.3, green: 0.29, blue: 0.37))
                    Spacer()
                    Text("SAVED ON THIS MAC")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(0.9)
                        .foregroundStyle(Color(red: 0.48, green: 0.57, blue: 0.52))
                }
                Text(selectedPersonaSection.description)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                TextEditor(text: Binding(
                    get: { personaDrafts[selectedPersonaSection] ?? selectedPersonaSection.value(in: assistant.profile) },
                    set: { personaDrafts[selectedPersonaSection] = String($0.prefix(2000)) }
                ))
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 230, maxHeight: .infinity)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.89, green: 0.87, blue: 0.92)))
                .accessibilityLabel("Edit \(selectedPersonaSection.title)")
            }
            .padding(15)
            .background(Color.white.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 15))

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(personaSavedMessage.isEmpty ? "Your edits are a profile, not executable code." : personaSavedMessage)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(personaSavedMessage.isEmpty ? .secondary : Color.green)
                    Text("Self-changes are profile text only—never executable code. One-step undo is available.")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if assistant.canUndoSelfChange {
                    Button("Undo last self-change") {
                        assistant.undoLastSelfChange()
                        refreshPersonaDrafts()
                        personaSavedMessage = "Restored the profile from before Nori’s last change."
                    }
                    .buttonStyle(QuietButtonStyle())
                }
                Button {
                    var next = assistant.profile
                    for section in PersonaSection.allCases {
                        if let value = personaDrafts[section] {
                            section.set(value, in: &next)
                        }
                    }
                    assistant.saveProfile(next)
                    refreshPersonaDrafts()
                    personaSavedMessage = "Profile saved. Nori will use it in the next reply."
                } label: {
                    Label("Save profile", systemImage: "checkmark")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 25)
        .padding(.top, 23)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: syncPersonaDrafts)
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            RobotAvatar(size: 85, mood: .curious)
                .matchedGeometryEffect(id: "nori-avatar", in: animation)
                .padding(.bottom, 4)
            Text(assistant.hasAPIKey ? "What’s on your mind?" : "Let’s get connected.")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.16, green: 0.15, blue: 0.24))
            Text(assistant.hasAPIKey
                 ? "I can help you think, plan, and open a few Mac apps—with your say-so first."
                 : "Add a Google Gemini API key in settings. It stays in your Mac’s Keychain.")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 390)

            if assistant.hasAPIKey {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            draft = suggestion
                            composerFocused = true
                        } label: {
                            HStack {
                                Text(suggestion).lineLimit(1)
                                Spacer(minLength: 4)
                                Image(systemName: "arrow.up.right")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 10)
                            .background(.white.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 11))
                            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.black.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 5)
            } else {
                Button("Set up Gemini") { showingSettings = true }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 4)
            }
        }
        .padding(22)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    if media.isListening {
                        media.stopListening()
                    } else {
                        Task {
                            await media.startListening { transcript in
                                Task { await assistant.send(transcript) }
                            }
                        }
                    }
                } label: {
                    Label(
                        media.isListening ? "Stop & send" : (media.isFinalizing ? "Finishing…" : "Talk"),
                        systemImage: media.isListening ? "stop.fill" : "mic.fill"
                    )
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(assistant.isSending || media.isFinalizing)

                Button {
                    Task {
                        do {
                            let scene = try await media.analyzeCameraScene()
                            draft = "Please respond to this camera analysis: \(scene)"
                            composerFocused = true
                            media.setStatus("Scene summary ready. Review the draft, then send it to Nori.")
                        } catch {
                            assistant.errorMessage = error.localizedDescription
                        }
                    }
                } label: {
                    Label("Analyze scene", systemImage: "camera.viewfinder")
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(media.isListening || assistant.isSending)

                Toggle("Speak replies", isOn: $speakReplies)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 10))
                    .help("Read Nori’s replies aloud on this Mac.")
                Spacer()
            }
            .font(.system(size: 10, weight: .medium))

            if !media.mediaStatus.isEmpty {
                Text(media.mediaStatus)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message \(assistant.profile.companionName)…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .disabled(!assistant.hasAPIKey || assistant.isSending)
                    .onSubmit(send)
                    .font(.system(size: 13))
                    .padding(.vertical, 8)

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 31, height: 31)
                        .background(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Color.gray.opacity(0.35)
                                    : Color(red: 0.48, green: 0.39, blue: 0.78))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || assistant.isSending)
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 0.88, green: 0.86, blue: 0.92)))
            Text("Stop & send submits on-device transcription to Nori. Camera images stay local; review the summary before sending.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 5)
        }
        .padding(.horizontal, 22)
        .padding(.top, 11)
        .padding(.bottom, 15)
        .background(Color.white.opacity(0.76))
    }

    private var companionPanel: some View {
        VStack(spacing: 16) {
            HStack {
                Text("NORI / 01")
                    .tracking(1.7)
                Spacer()
                Circle()
                    .fill(assistant.isSending ? Color.orange : (assistant.hasAPIKey ? Color.mint : Color.gray))
                    .frame(width: 6, height: 6)
                Text(assistant.isSending ? "THINKING" : (assistant.hasAPIKey ? "ONLINE" : "SETUP"))
            }
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.62))

            Spacer(minLength: 5)
            ZStack {
                Circle().stroke(Color.white.opacity(0.09), lineWidth: 1).frame(width: 226, height: 226)
                Circle().stroke(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    .frame(width: 194, height: 194)
                    .rotationEffect(.degrees(assistant.isSending ? 35 : 0))
                Circle().fill(Color.purple.opacity(0.15)).frame(width: 170, height: 170).blur(radius: 25)
                RobotAvatar(size: 184, mood: assistant.isSending ? .thinking : (assistant.turns.isEmpty ? .curious : .happy))
                Text("✳")
                    .font(.system(size: 17))
                    .foregroundStyle(Color(red: 0.96, green: 0.73, blue: 0.91))
                    .offset(x: 91, y: -70)
            }
            .frame(height: 236)
            .scaleEffect(assistant.isSending ? 1.015 : 1)
            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: assistant.isSending)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Circle().fill(Color.purple.opacity(0.85)).frame(width: 6, height: 6)
                    Text(assistant.isSending ? "Thinking it through" : "Here when you need me")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.94))
                }
                Text("I don’t have human feelings, but I can be a thoughtful companion.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1) }

            VStack(alignment: .leading, spacing: 10) {
                Label("Your Mac, your call", systemImage: "hand.raised.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Nori may suggest opening Finder, Safari, Notes, Calendar, or System Settings. Nothing opens until you approve the preview.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.63))
                    .lineSpacing(3)
                Text("NO SHELL · NO AUTORUN")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Color(red: 0.69, green: 0.85, blue: 0.77))
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.065))
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.08)))

            Spacer(minLength: 4)
            Button {
                showingSettings = true
            } label: {
                Label("Personalize Nori", systemImage: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(19)
        .background(
            RadialGradient(
                colors: [Color(red: 0.24, green: 0.21, blue: 0.37), Color(red: 0.11, green: 0.10, blue: 0.19)],
                center: .top,
                startRadius: 10,
                endRadius: 380
            )
        )
    }

    private func send() {
        let text = draft
        draft = ""
        Task { await assistant.send(text) }
    }

    private func syncPersonaDrafts() {
        for section in PersonaSection.allCases {
            let current = section.value(in: assistant.profile)
            if personaDrafts[section] == nil || personaDrafts[section] == personaBase[section] {
                personaDrafts[section] = current
            }
            personaBase[section] = current
        }
    }

    private func refreshPersonaDrafts() {
        personaDrafts = Dictionary(
            uniqueKeysWithValues: PersonaSection.allCases.map { ($0, $0.value(in: assistant.profile)) }
        )
        personaBase = personaDrafts
    }
}

private struct MessageBubble: View {
    let turn: ChatTurn
    let onResolveAction: (Bool) -> Void
    let onApproveMemory: () -> Void
    let onApproveSelfChange: () -> Void
    let onDeclineSelfChange: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if turn.role == .assistant {
                RobotAvatar(size: 29, mood: .happy)
            } else {
                Spacer(minLength: 35)
            }
            VStack(alignment: .leading, spacing: 11) {
                Text(turn.content)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.25, green: 0.24, blue: 0.32))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let action = turn.action {
                    actionCard(action)
                }
                if let memory = turn.proposedMemory {
                    memoryCard(memory)
                }
                if let change = turn.selfChange {
                    selfChangeCard(change)
                }
            }
            .padding(turn.role == .user ? 12 : 2)
            .padding(.horizontal, turn.role == .user ? 4 : 0)
            .background(turn.role == .user ? Color(red: 0.92, green: 0.89, blue: 0.99) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 13))
            if turn.role == .user {
                Spacer(minLength: 35)
            }
        }
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity, alignment: turn.role == .user ? .trailing : .leading)
    }

    private func actionCard(_ action: ProposedAction) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.up.forward.app.fill")
                    .foregroundStyle(Color(red: 0.46, green: 0.38, blue: 0.75))
                Text("Nori wants to open \(action.target)")
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(action.reason)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            if turn.actionStatus == .pending {
                HStack {
                    Button("Open \(action.target)") { onResolveAction(true) }
                        .buttonStyle(PrimaryButtonStyle())
                    Button("Not now") { onResolveAction(false) }
                        .buttonStyle(QuietButtonStyle())
                }
            } else {
                Text(turn.actionStatus == .approved ? "Approved — opening app" : "Dismissed")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color(red: 0.88, green: 0.85, blue: 0.94)))
    }

    private func memoryCard(_ memory: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Personalization suggestion", systemImage: "brain.head.profile")
                .font(.system(size: 10, weight: .semibold))
            Text("“\(memory)”")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            if turn.memoryAccepted {
                Text("Saved to Nori’s local profile")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.green)
            } else {
                Button("Remember this") { onApproveMemory() }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.98, green: 0.97, blue: 1))
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color(red: 0.89, green: 0.86, blue: 0.96)))
    }

    private func selfChangeCard(_ change: ValidatedSelfChange) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Nori proposes changing \(change.field.rawValue)", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(red: 0.42, green: 0.34, blue: 0.72))
            if !change.reason.isEmpty {
                Text(change.reason)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("CURRENT")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.9)
                    .foregroundStyle(.secondary)
                Text(change.previousValue)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                Text("PROPOSED")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.9)
                    .foregroundStyle(Color(red: 0.42, green: 0.34, blue: 0.72))
                    .padding(.top, 4)
                Text(change.value)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 0.25, green: 0.24, blue: 0.32))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(9)
            .background(Color(red: 0.97, green: 0.96, blue: 0.99))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            if turn.selfChangeAccepted {
                Label("Approved and saved · undo is available in Nori’s mind", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.green)
            } else if turn.selfChangeDeclined {
                Label("Dismissed · no change made", systemImage: "xmark.circle")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Button("Approve this change") {
                        onApproveSelfChange()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button("Decline") {
                        onDeclineSelfChange()
                    }
                    .buttonStyle(QuietButtonStyle())
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color(red: 0.82, green: 0.77, blue: 0.94)))
    }
}

private struct SettingsSheet: View {
    @EnvironmentObject private var assistant: AssistantModel
    @Environment(\.dismiss) private var dismiss
    @State private var profile: CompanionProfile
    @State private var apiKey = ""
    @State private var savedMessage: String?
    @State private var showingResetConfirmation = false

    private let toneOptions = [
        "Warm, curious, and encouraging",
        "Calm and concise",
        "Playful and upbeat",
        "Thoughtful and direct",
    ]

    init() {
        _profile = State(initialValue: CompanionProfile())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Make Nori yours")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("Preferences and memories stay on this Mac.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
            }

            GroupBox("Companion") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Name", text: $profile.companionName)
                        .textFieldStyle(.roundedBorder)
                    Picker("Style", selection: $profile.tone) {
                        ForEach(toneOptions, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.top, 5)
            }

            GroupBox("Google Gemini Live API key") {
                VStack(alignment: .leading, spacing: 8) {
                    if assistant.hasAPIKey {
                        Label("Key is stored in macOS Keychain", systemImage: "checkmark.shield.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                        Button("Remove saved key", role: .destructive) {
                            assistant.removeAPIKey()
                            apiKey = ""
                        }
                    }
                    SecureField(assistant.hasAPIKey ? "Enter a replacement key" : "Paste API key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    Text("Used with \(AssistantService.model) over Gemini Live API. The key stays in macOS Keychain and is sent only to Google.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Link("Get a Google AI Studio API key", destination: URL(string: "https://aistudio.google.com/app/apikey")!)
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.top, 5)
            }

            HStack {
                if let savedMessage {
                    Text(savedMessage).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reset all Nori data", role: .destructive) {
                    showingResetConfirmation = true
                }
                .font(.system(size: 10))
                Button("Save preferences") {
                    profile.companionName = profile.companionName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if profile.companionName.isEmpty { profile.companionName = "Nori" }
                    assistant.saveProfile(profile)
                    let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedKey.isEmpty {
                        assistant.saveAPIKey(trimmedKey)
                        apiKey = ""
                    }
                    if assistant.errorMessage == nil {
                        savedMessage = "Saved on this Mac."
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(24)
        .frame(width: 530)
        .onAppear { profile = assistant.profile }
        .alert("Reset all Nori data?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset everything", role: .destructive) {
                assistant.resetLocalData()
                profile = assistant.profile
                apiKey = ""
                savedMessage = "Nori’s local data has been reset."
            }
        } message: {
            Text("This deletes saved API keys, persona and memories, undo data, and app preferences from this Mac. The app stays installed.")
        }
    }
}

private struct RobotAvatar: View {
    enum Mood {
        case curious
        case happy
        case thinking
    }

    let size: CGFloat
    let mood: Mood

    private var eyeColor: Color {
        mood == .thinking ? Color(red: 1, green: 0.82, blue: 0.53) : Color(red: 0.55, green: 0.94, blue: 0.91)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.73, green: 0.66, blue: 0.98), Color(red: 0.39, green: 0.34, blue: 0.68)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(Circle().stroke(Color.white.opacity(0.72), lineWidth: max(size * 0.014, 1)))
                .shadow(color: Color.purple.opacity(0.2), radius: size * 0.12, y: size * 0.08)
            VStack(spacing: size * 0.1) {
                HStack(spacing: size * 0.24) {
                    eye
                    eye
                }
                RobotMouth(mood: mood)
                    .stroke(mood == .thinking ? eyeColor : Color(red: 0.98, green: 0.82, blue: 0.99),
                            style: StrokeStyle(lineWidth: max(size * 0.035, 2), lineCap: .round))
                    .frame(width: size * 0.27, height: size * 0.12)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                Rectangle().fill(Color(red: 0.81, green: 0.75, blue: 1)).frame(width: size * 0.025, height: size * 0.12)
                Circle().fill(Color(red: 0.97, green: 0.75, blue: 0.94)).frame(width: size * 0.08, height: size * 0.08)
                    .shadow(color: .pink.opacity(0.6), radius: size * 0.08)
            }
            .offset(y: -size * 0.17)
        }
        .overlay(alignment: .leading) {
            Capsule().fill(Color(red: 0.77, green: 0.71, blue: 0.99))
                .frame(width: size * 0.11, height: size * 0.27)
                .offset(x: -size * 0.03)
        }
        .overlay(alignment: .trailing) {
            Capsule().fill(Color(red: 0.77, green: 0.71, blue: 0.99))
                .frame(width: size * 0.11, height: size * 0.27)
                .offset(x: size * 0.03)
        }
        .padding(.top, size * 0.15)
    }

    private var eye: some View {
        Capsule()
            .fill(eyeColor)
            .frame(width: size * 0.12, height: size * (mood == .thinking ? 0.055 : 0.16))
            .shadow(color: eyeColor.opacity(0.7), radius: size * 0.07)
            .overlay(alignment: .topTrailing) {
                Circle().fill(.white).frame(width: size * 0.025, height: size * 0.025)
                    .offset(x: -size * 0.025, y: size * 0.018)
            }
    }

}

private struct RobotMouth: Shape {
    let mood: RobotAvatar.Mood

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if mood == .happy {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.18))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.18),
                control: CGPoint(x: rect.midX, y: rect.maxY)
            )
        } else if mood == .thinking {
            path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.2))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY - rect.height * 0.2))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.25))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY * 0.72),
                control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.1)
            )
        }
        return path
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Color(red: 0.48, green: 0.39, blue: 0.78).opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color(red: 0.43, green: 0.4, blue: 0.54))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(configuration.isPressed ? 0.65 : 0.9))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
