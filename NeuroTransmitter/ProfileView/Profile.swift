import SwiftUI
import Firebase
import FirebaseAuth
import FirebaseFirestore

struct Profile: View {
    
    @State private var currentUserEmail = ""
    @State private var editedName = ""
    @State private var editedRocketID = ""
    @State private var editedPhoneNumber = ""
    @State private var isEditing = false
    @State private var userIsSignedOut = false
    @State private var errorMessage = ""
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack {
                List {
                    Section(header: Text("User Information")) {
                        if isEditing {
                            // Editing Mode
                            HStack {
                                Text("Name: ").bold()
                                TextField("Name", text: $editedName)
                            }
                            HStack {
                                Text("Rocket ID: ").bold()
                                TextField("Rocket ID", text: $editedRocketID)
                            }
                            HStack {
                                Text("Phone Number: ").bold()
                                TextField("Phone Number", text: $editedPhoneNumber)
                            }
                        } else {
                            // Display Mode
                            HStack {
                                Text("Name: ").bold()
                                Text("\(editedName)")
                            }
                            HStack {
                                Text("Rocket ID: ").bold()
                                Text("\(editedRocketID)")
                            }
                            HStack {
                                Text("Phone Number: ").bold()
                                Text("\(editedPhoneNumber)")
                            }
                        }
                        
                        HStack {
                            Text("Email ID: ").bold()
                            Text("\(currentUserEmail)")
                        }
                    }
                    
                    // Log Out Button
                    Button("Log Out") {
                        logOut()
                    }
                    .foregroundColor(.blue)
                    .padding()
                    
                    // Delete Account Button
                    Button("Delete Account") {
                        deleteUserAccount()
                    }
                    .foregroundColor(.red)
                    .padding()
                }
                .onAppear {
                    fetchUserData()
                }
                .onDisappear {
                    if userIsSignedOut {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .navigationTitle("Welcome \(editedName)")
        .navigationBarItems(trailing: editButton)
        .background(
            NavigationLink(destination: SignInView(), isActive: $userIsSignedOut) {
                EmptyView()
            }
            .hidden()
        )
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    // Edit Button
    private var editButton: some View {
        Button(action: {
            isEditing.toggle()
            if !isEditing {
                saveUserData(name: editedName, rocketID: editedRocketID, phoneNumber: editedPhoneNumber)
            }
        }) {
            Text(isEditing ? "Save" : "Edit")
                .foregroundColor(.green)
        }
    }
    
    // MARK: - Fetch User Data
    func fetchUserData() {
        guard let currentUserEmail = Auth.auth().currentUser?.email else {
            print("User is not signed in.")
            return
        }
        
        self.currentUserEmail = currentUserEmail
        
        let userRef = Firestore.firestore().collection("users").document(currentUserEmail)
        
        userRef.getDocument { document, error in
            if let error = error {
                print("Error fetching user data: \(error.localizedDescription)")
                return
            }
            
            if let document = document, document.exists {
                let data = document.data()
                editedName = data?["Name"] as? String ?? ""
                editedRocketID = data?["RocketID"] as? String ?? ""
                editedPhoneNumber = data?["phoneNumber"] as? String ?? ""
            }
        }
    }
    
    // MARK: - Save User Data
    func saveUserData(name: String, rocketID: String, phoneNumber: String) {
        guard let userEmail = Auth.auth().currentUser?.email else {
            print("User is not signed in.")
            return
        }
        
        let userRef = Firestore.firestore().collection("users").document(userEmail)
        
        // Fetch the current values of isApproved and FCMToken
        userRef.getDocument { document, error in
            if let document = document, document.exists {
                let currentData = document.data()
                let isApproved = currentData?["isApproved"] as? Bool ?? false
                let fcmToken = currentData?["FCMToken"] as? String ?? ""
                
                let updatedUserData: [String: Any] = [
                    "Name": name,
                    "RocketID": rocketID,
                    "phoneNumber": phoneNumber,
                    "isApproved": isApproved,
                    "FCMToken": fcmToken
                ]
                
                userRef.updateData(updatedUserData) { error in
                    if let error = error {
                        print("Error updating user data: \(error.localizedDescription)")
                    } else {
                        print("User data updated successfully")
                    }
                }
            }
        }
    }
    
    // MARK: - Log Out
    func logOut() {
        do {
            try Auth.auth().signOut()
            userIsSignedOut = true
        } catch {
            print("Error signing out: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Delete User Account
    func deleteUserAccount() {
        guard let currentUser = Auth.auth().currentUser, let currentUserEmail = currentUser.email else {
            print("No authenticated user found.")
            return
        }
        
        let userRef = Firestore.firestore().collection("users").document(currentUserEmail)
        
        // Step 1: Delete the Firestore document
        userRef.delete { error in
            if let error = error {
                print("Error deleting Firestore document: \(error.localizedDescription)")
                errorMessage = "Failed to delete account data."
                return
            }
            
            print("User data deleted from Firestore.")
            
            // Step 2: Delete the Firebase Authentication account
            currentUser.delete { error in
                if let error = error {
                    print("Error deleting Firebase account: \(error.localizedDescription)")
                    errorMessage = "Failed to delete account."
                    return
                }
                
                print("Firebase account deleted successfully.")
                userIsSignedOut = true
            }
        }
    }
}

struct Profile_Previews: PreviewProvider {
    static var previews: some View {
        Profile()
    }
}
