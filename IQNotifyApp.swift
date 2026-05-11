import SwiftUI

@main
struct IQNotifyApp: App {
    @StateObject private var bleManager = BLEManager()
    
    init() {
        // Setup notification interceptor
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    NotificationInterceptor.shared.setup(bleManager: bleManager)
                }
        }
    }
}
