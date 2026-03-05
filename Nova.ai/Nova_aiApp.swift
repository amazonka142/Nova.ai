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
  private func looksLikeConfiguredFirebaseOptions(_ options: FirebaseOptions) -> Bool {
    let placeholderMarkers = ["REPLACE", "YOUR_", "<"]

    func isValid(_ value: String?) -> Bool {
      guard let value else { return false }
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return false }
      return !placeholderMarkers.contains(where: { trimmed.uppercased().contains($0) })
    }

    return isValid(options.googleAppID)
      && isValid(options.gcmSenderID)
      && isValid(options.apiKey)
      && isValid(options.projectID)
  }

  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    
    // Set the App Check provider factory before configuring Firebase
    let providerFactory = NovaAppCheckProviderFactory()
    AppCheck.setAppCheckProviderFactory(providerFactory)
    
    if let configPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
       let options = FirebaseOptions(contentsOfFile: configPath),
       looksLikeConfiguredFirebaseOptions(options) {
      FirebaseApp.configure(options: options)
    } else {
      #if DEBUG
      print("Firebase is not configured. Copy GoogleService-Info.plist.example to Nova.ai/GoogleService-Info.plist to enable Firebase features.")
      #endif
    }
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
