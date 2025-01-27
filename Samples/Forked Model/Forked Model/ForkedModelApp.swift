//
//  Forked_ModelApp.swift
//  Forked Model
//
//  Created by Drew McCormack on 15/11/2024.
//

import SwiftUI

@main
struct ForkedModelApp: App {
    var body: some Scene {
        @State var store = Store()
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
