//
//  BitrateReaderApp.swift
//  BitrateReader
//
//  Created by skeeet on 11/27/25.
//

import SwiftUI

@main
struct BitrateReaderApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            // Remove New Window command
            CommandGroup(replacing: .newItem) { }
        }
    }
}
