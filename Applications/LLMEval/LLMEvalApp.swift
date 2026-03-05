// Copyright © 2024 Apple Inc.

import SwiftUI

@main
struct LLMEvalApp: App {
    var body: some Scene {
        WindowGroup {
            CodingAgentView()
        }
        .defaultSize(width: 1100, height: 740)
    }
}
