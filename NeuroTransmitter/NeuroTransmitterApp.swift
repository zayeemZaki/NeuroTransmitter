import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Firebase
import FirebaseMessaging
import UserNotifications
import BackgroundTasks
import PDFKit

@main
struct NeuroTransmitterApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var viewModel = ViewModel()

    var body: some Scene {
        WindowGroup {
            SignInView()
                .environmentObject(viewModel)
                .onOpenURL { url in
                    if url.pathExtension == "pdf" {
                        viewModel.handleIncomingPDF(url: url)
                    }
                }
        }
    }
    
    
}

class AppDelegate: UIResponder, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        FirebaseApp.configure()

        Messaging.messaging().delegate = self

        let center = UNUserNotificationCenter.current()
        center.delegate = self  // Set the delegate

        requestNotificationPermission(application: application)
        return true
    }

    func requestNotificationPermission(application: UIApplication) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
            // Handle the permission state
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Handle the error
        print("Failed to register: \(error)")
    }

    // MARK: - UNUserNotificationCenterDelegate Methods

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Handle the notification while the app is in the foreground
        completionHandler([.badge, .sound, .banner])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle the notification when the app is opened from a notification
        completionHandler()
    }

    // MARK: - MessagingDelegate Methods

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let newToken = fcmToken else { return }
        print("FCM registration token: \(newToken)")

        // Update token in Firestore
        updateTokenInFirestore(newToken)
    }
    
    func updateTokenInFirestore(_ token: String) {
        guard let userEmail = Auth.auth().currentUser?.email else {
            print("User not logged in. Unable to update FCM token.")
            return
        }

        let userRef = Firestore.firestore().collection("users").document(userEmail)
        userRef.updateData(["FCMToken": token]) { error in
            if let error = error {
                print("Error updating FCM token: \(error.localizedDescription)")
            } 
            else {
                print("FCM token updated successfully")
            }
        }
    }

}



















/*
 import SwiftUI
 import FirebaseAuth
 import FirebaseFirestore
 import Firebase
 import FirebaseMessaging
 import UserNotifications
 import BackgroundTasks
 import PDFKit

 @main
 struct NeuroTransmitterApp: App {
     @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
     
     var body: some Scene {
         WindowGroup {
             SignInView()
         }
     }
 }

 class AppDelegate: UIResponder, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {

     var window: UIWindow?
     var pdfDocumentURL: URL?

     func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
         print("Opening URL: \(url)")

         // Store the PDF document URL
         pdfDocumentURL = url
         print("application func called")

         // Handle the URL, e.g., save the PDF document to the "Recent" folder
         if let folderListView = window?.rootViewController as? FolderListView {
             folderListView.handlePDFDocument(at: url)
         }

         return true
     }



     func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
         FirebaseApp.configure()
         Messaging.messaging().delegate = self
         UNUserNotificationCenter.current().delegate = self
         UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
             print("Authorization granted")
         }
         print("Registering for remote notifications")

         application.registerForRemoteNotifications() // Start APNS registration

         // Register background tasks
         BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.kash.eur5.NeuroTransmitter.messageProcessingTask", using: nil) { (task) in
             // Perform message processing logic here
             // Determine users to notify
             // Initiate notification sending task if needed
             task.setTaskCompleted(success: true)
         }

         BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.kash.eur5.NeuroTransmitter.notificationSendingTask", using: nil) { (task) in
             // Send notifications to specified users
             task.setTaskCompleted(success: true)
         }

         // Check if the app is launched from a URL (PDF document)
         if let url = launchOptions?[.url] as? URL {
             print("Opening URL: \(url)")

             // Store the PDF document URL
             pdfDocumentURL = url

             // Handle the PDF document URL here
             if let folderListView = window?.rootViewController as? FolderListView {
                 folderListView.handlePDFDocument(at: url)
             }
         }

         return true
     }
     
     func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
         // Pass device token to APNS
         Messaging.messaging().apnsToken = deviceToken
         print("Device Token: \(deviceToken)")
         
         // Now we have APNS token, get FCM token
         Messaging.messaging().token { fcmToken, error in
             if let error = error {
                 print("Error fetching FCM token: \(error)")
             } else if let fcmToken = fcmToken {
                 print("Got FCM token: \(fcmToken)")
             }
         }
     }
     
     func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
         print("Failed to register for remote notifications: \(error)")
     }
     
     // Handle incoming notifications while the app is in the foreground
     func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
         // Handle the notification here, e.g., show an alert or update the UI.
         completionHandler([.alert, .sound, .badge])
     }
     
     // Handle tapping on the notification to open the app
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
         // Handle the user's interaction with the notification here.
         completionHandler()
     }
     
     func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
         if let fcmToken = fcmToken {
             print("Received FCM Token: \(fcmToken)")
         } else {
             print("Failed to receive FCM Token")
         }
     }
     

     
 }
 */




/*

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Firebase
import FirebaseMessaging
import UserNotifications
import BackgroundTasks

@main
struct NeuroTransmitterApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        WindowGroup {
            SignInView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            print("Authorization granted")
        }
        print("Registering for remote notifications")
        
        application.registerForRemoteNotifications() // Start APNS registration
        
        // Register background tasks
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.kash.eur5.NeuroTransmitter.messageProcessingTask", using: nil) { (task) in
            // Perform message processing logic here
            // Determine users to notify
            // Initiate notification sending task if needed
            task.setTaskCompleted(success: true)
        }
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.kash.eur5.NeuroTransmitter.notificationSendingTask", using: nil) { (task) in
            // Send notifications to specified users
            task.setTaskCompleted(success: true)
        }
        
        return true
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        
        // Pass device token to APNS
        Messaging.messaging().apnsToken = deviceToken
        print("Device Token: \(deviceToken)")
        
        // Now we have APNS token, get FCM token
        Messaging.messaging().token { fcmToken, error in
            if let error = error {
                print("Error fetching FCM token: \(error)")
            } else if let fcmToken = fcmToken {
                print("Got FCM token: \(fcmToken)")
            }
        }
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error)")
    }
    
    // Handle incoming notifications while the app is in the foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Handle the notification here, e.g., show an alert or update the UI.
        completionHandler([.alert, .sound, .badge])
    }
    
    // Handle tapping on the notification to open the app
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle the user's interaction with the notification here.
        completionHandler()
    }
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        if let fcmToken = fcmToken {
            print("Received FCM Token: \(fcmToken)")
        } else {
            print("Failed to receive FCM Token")
        }
    }
}

*/


/*
 import SwiftUI
 import FirebaseAuth
 import FirebaseFirestore
 import Firebase
 import FirebaseMessaging
 import UserNotifications

 @main
 struct NeuroTransmitterApp: App {
     @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
     
     var body: some Scene {
         WindowGroup {
             SignInView()
         }
     }
 }

 class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {
     func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
         
         FirebaseApp.configure()
         Messaging.messaging().delegate = self
         UNUserNotificationCenter.current().delegate = self
         UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
             print("Authorization granted")
         }
         print("Registering for remote notifications")
 //Logger.log("Registering for remote notifications")


         
         application.registerForRemoteNotifications() // Start APNS registration
         return true
     }

     func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {

         // Pass device token to APNS
         Messaging.messaging().apnsToken = deviceToken
         print("Device Token: \(deviceToken)")

         // Now we have APNS token, get FCM token
         Messaging.messaging().token { fcmToken, error in
             if let error = error {
                 print("Error fetching FCM token: \(error)")
             } else if let fcmToken = fcmToken {
                 print("Got FCM token: \(fcmToken)")

                 // Subscribe to the common topic for all users
                // self.subscribeToGlobalTopic()
             }
         }
     }
     func application(_ application: UIApplication,
                 didFailToRegisterForRemoteNotificationsWithError
                     error: Error) {
        print(error)
         print("Try again")
     }
     // Handle incoming notifications while the app is in the foreground
     func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
         // Handle the notification here, e.g., show an alert or update the UI.
         completionHandler([.alert, .sound, .badge])
     }

     // Handle tapping on the notification to open the app
     func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
         // Handle the user's interaction with the notification here.
         completionHandler()
     }

     func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
         if let fcmToken = fcmToken {
             print("Received FCM Token: \(fcmToken)")
         } else {
             print("Failed to receive FCM Token")
         }
     }
 }


 */















/*
 import SwiftUI
 import Firebase
 import FirebaseMessaging
 import UserNotifications
 import UIKit

 @main
 struct NeuroTransmitterApp: App {
     
     @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
     
     var body: some Scene {
         WindowGroup {
             SignInView()
         }
     }
 }


 class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {
     func application(_ application: UIApplication,
                      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]?) -> Bool {
         FirebaseApp.configure()
         
         
         Messaging.messaging().delegate = self
         UNUserNotificationCenter.current().delegate = self
         
         UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { success, _ in
             guard success else {
                 return
             }
             print("success in APNS registery")
             
         }
         
         application.registerForRemoteNotifications()
         
         return true
         
     }
     
     // Handle incoming notifications while the app is in the foreground
     func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
         // Handle the notification here, e.g., show an alert or update the UI.
         completionHandler([.alert, .sound, .badge])
     }
     
     // Handle tapping on the notification to open the app
     func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
         // Handle the user's interaction with the notification here.
         completionHandler()
     }
     
     func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
         if let fcmToken = fcmToken {
             print("Received FCM Token: \(fcmToken)")
         } else {
             print("Failed to receive FCM Token")

             // Check if the APNS token is available
             if let apnsToken = Messaging.messaging().apnsToken {
                 print("APNS Token is available: \(apnsToken)")

                 // Retry obtaining FCM token now that APNS token is available
                 Messaging.messaging().token { token, error in
                     if let error = error {
                         print("Error fetching FCM token: \(error.localizedDescription)")
                     } else if let token = token {
                         print("Retrieved FCM token after APNS token: \(token)")
                     }
                 }
             } else {
                 print("APNS Token is not available yet. Retry later.")
             }
         }
     }
 }




 */
