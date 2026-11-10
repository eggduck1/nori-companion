# Nori

Nori is a native macOS companion with an expressive robot interface, Gemini Live chat, optional voice input, spoken replies, and on-device camera analysis.

## Requirements

- macOS 14 or later
- Xcode Command Line Tools with Swift
- A Google AI Studio API key with access to `gemini-3.1-flash-live-preview`

## Build and run

From the repository root:

```bash
bash build-app.sh
open build/Nori.app
```

Open the settings button, add your Google AI Studio API key, and save. Nori stores the key in macOS Keychain. Chat text is sent directly to Google's Gemini Live API over a WebSocket; this preview model/API can change availability and pricing.

## Voice and camera

- **Talk** starts a microphone session only when selected. **Stop & send** ends capture; macOS Speech Recognition transcribes on-device, and the transcript is sent to Gemini when you send the turn.
- **Speak replies** uses macOS text-to-speech and can be toggled off.
- **Analyze scene** takes a still camera image only when selected. Apple's on-device Vision framework classifies likely objects/scenes and detects face counts. It does not identify people, save the image, or upload it. The resulting text summary is placed in the composer for you to review before sending.
- macOS requests microphone, camera, and speech recognition permissions when each feature is first used.

## Safety and privacy

Nori only opens Finder, Safari, Notes, Calendar, or System Settings after you approve an action preview. It does not run shell commands, edit files, change settings, or send messages. Persona changes affect profile text only and require approval; they never rewrite or execute application code. Nori can sound personable, but does not literally experience feelings.

Voice capture is push-to-talk, stops after 45 seconds, and is not recorded to a file. Camera analysis is on demand. **Reset all Nori data** removes saved API keys, persona and memories, undo data, and app preferences from this Mac; it leaves the app installed.

## Checks

```bash
swift run NoriCoreChecks
swift build --configuration release
```

## License

MIT. See [LICENSE](LICENSE).
