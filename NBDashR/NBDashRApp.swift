import SwiftUI

@main
struct NBDashRApp: App {
    @StateObject private var controller = AppController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
                .preferredColorScheme(.dark)
        }
    }
}
