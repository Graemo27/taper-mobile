import SwiftUI

@main
struct FoodPadApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Food Pad")
                .preferredColorScheme(.light)
                .accessibilityIdentifier("bootstrap.screen")
        }
    }
}
