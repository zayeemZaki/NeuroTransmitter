import SwiftUI
import FirebaseAuth

class SessionManager: ObservableObject {
    @Published var isSignedIn: Bool = false
    
    init() {
        checkAuthentication()
    }
    
    func checkAuthentication() {
        if Auth.auth().currentUser != nil {
            isSignedIn = true
        } else {
            isSignedIn = false
        }
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            isSignedIn = false
        } catch {
            print("Error signing out: \(error.localizedDescription)")
        }
    }
}
