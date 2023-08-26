//////
//////  SceneDelegate.swift
//////  NeuroTransmitter
//////
//////  Created by Zayeem on 12/19/23.
//////
////
////
////// SceneDelegate.swift
//import UIKit
//import SwiftUI
////
////class SceneDelegate: UIResponder, UIWindowSceneDelegate {
////
////    var window: UIWindow?
////
////    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
////        guard let windowScene = (scene as? UIWindowScene) else { return }
////        let contentView = SignInView()
////        window = UIWindow(windowScene: windowScene)
////        window?.rootViewController = UIHostingController(rootView: contentView)
////        window?.makeKeyAndVisible()
////        print("Hi")
////    }
////    
////    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
////        guard let url = URLContexts.first?.url else {
////            print("Scene func called but else")
////            return
////        }
////        print("Scene func called")
////        // Handle the URL, e.g., save the PDF document to the "Recent" folder
////        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
////            appDelegate.pdfDocumentURL = url
////
////            if let folderListView = (scene as? UIWindowScene)?.windows.first?.rootViewController as? FolderListView {
////                folderListView.handlePDFDocument(at: url)
////            }
////        }
////    }
////
////}
////
//
//class SceneDelegate: UIResponder, UIWindowSceneDelegate {
//    
//    var window: UIWindow?
//    
//    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
//        print("Scene willConnectTo")
//
//        guard let windowScene = (scene as? UIWindowScene) else { return }
//        let contentView = SignInView()
//        window = UIWindow(windowScene: windowScene)
//        window?.rootViewController = UIHostingController(rootView: contentView)
//        window?.makeKeyAndVisible()
//
//        // Check for user activity in connectionOptions and handle it
//        if let userActivity = connectionOptions.userActivities.first {
//            handleUserActivity(userActivity)
////        }
////    }
////
////    // Helper method to handle the user activity
////    func handleUserActivity(_ userActivity: NSUserActivity) {
////        if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
////           let url = userActivity.webpageURL {
////            // Handle the URL as needed
////            print("Handling URL: \(url)")
////            
////            if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
////                // Store the PDF document URL
////                appDelegate.pdfDocumentURL = url
////                
////                // Call the method to handle the PDF documen
////            }
////        }
////    }
////    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
////        guard let urlContext = URLContexts.first else {
////            print("Not Openning URL: ")
////
////            return
////        }
////        
////        let url = urlContext.url
////        print("Opening URL: \(url)")
////        
////        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
////            // Store the PDF document URL in your AppDelegate
////            appDelegate.pdfDocumentURL = url
////            
////            // Call the method to handle the PDF document
////            appDelegate.saveInRecentFolder(at: url)
////        }
////    }
////}
