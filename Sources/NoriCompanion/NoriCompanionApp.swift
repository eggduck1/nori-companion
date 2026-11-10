import SwiftUI

@main
struct NoriCompanionApp: App {
    @StateObject private var assistant = AssistantModel()
    @StateObject private var media = LocalMediaServices()

    var body: some Scene {
        WindowGroup {
            CompanionWindow()
                .environmentObject(assistant)
                .environmentObject(media)
                .frame(minWidth: 820, minHeight: 620)
        }
        .defaultSize(width: 1080, height: 760)
        .windowStyle(.titleBar)
    }
}
