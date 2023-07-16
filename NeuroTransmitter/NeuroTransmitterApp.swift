//
//  NeuroTransmitterApp.swift
//  NeuroTransmitter
//
//  Created by Zayeem Zaki on 6/13/23.
//

import SwiftUI
import Firebase

@main
struct NeuroTransmitterApp: App {
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        WindowGroup {
            SignInView()
        }
    }
}


class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        
        return true
    }
}
