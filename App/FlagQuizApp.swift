import SwiftUI

@main
struct FlagQuizApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WorldMapView()
                .environment(model)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    switch phase {
                    case .active: model.appBecameActive()
                    case .background: model.appWentToBackground()
                    default: break
                    }
                }
        }
    }
}
