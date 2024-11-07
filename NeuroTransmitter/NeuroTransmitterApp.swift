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
