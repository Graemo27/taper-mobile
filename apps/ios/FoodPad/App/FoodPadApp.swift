import SwiftUI

@main
struct FoodPadApp: App {
    var body: some Scene {
        WindowGroup {
            JournalShellView()
                .preferredColorScheme(.light)
        }
    }
}
