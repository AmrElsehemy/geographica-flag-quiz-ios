import SwiftUI

@main
struct FlagQuizApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            WorldMapView()
                .environment(model)
        }
    }
}
