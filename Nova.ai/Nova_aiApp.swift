//
//  Nova_aiApp.swift
//  Nova.ai
//
//  Created by Vlad on 1/24/26.
//

import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseAppCheck
import GoogleSignIn

class NovaAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
  func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
    #if targetEnvironment(simulator)
      // App Check Debug Provider for Simulator
      return AppCheckDebugProvider(app: app)
    #else
      // Use App Attest for production on physical devices
      return AppAttestProvider(app: app)
    #endif
  }
}

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    
    // Set the App Check provider factory before configuring Firebase
    let providerFactory = NovaAppCheckProviderFactory()
    AppCheck.setAppCheckProviderFactory(providerFactory)
    
    FirebaseApp.configure()
    return true
  }
}

@main
struct Nova_aiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
        .modelContainer(for: [ChatSession.self, ChatFolder.self, Project.self, ProjectFile.self])
    }
}
