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
    @State private var showDeleteConfirmation = false
    @Environment(\.presentationMode) var presentationMode
    
    // Search functionality state variables
    @State private var isSearching = false
    @State private var searchName = ""
    @State private var searchedProfile: UserProfile?

    struct UserProfile {
        let name: String
        let rocketID: String
        let phoneNumber: String
        let email: String
    }

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
                    
                    Button("Delete Account") {
                        showDeleteConfirmation = true
                    }
                    .foregroundColor(.red)
                    .padding()
                    .alert("Confirm Deletion", isPresented: $showDeleteConfirmation) {
                        Button("Delete", role: .destructive) {
                            deleteUserAccount()
                        }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("Are you sure you want to delete your account? This action cannot be undone.")
                    }
                    
                    // Search Section
                    Section(header: Text("Search Profiles")) {
                        HStack {
                            TextField("Search by Name", text: $searchName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            Button(action: {
                                searchProfiles()
                            }) {
                                Text("Search")
                                    .foregroundColor(.green)
                            }
                        }
                        if isSearching {
                            if let profile = searchedProfile {
                                VStack(alignment: .leading) {
                                    Text("Name: \(profile.name)").bold()
                                    Text("Rocket ID: \(profile.rocketID)")
                                    Text("Phone Number: \(profile.phoneNumber)")
                                    Text("Email ID: \(profile.email)")
                                }
                            } else {
                                Text("No profile found.")
                            }
                        }
                    }
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
    
    // MARK: - Search Profiles
    func searchProfiles() {
        guard !searchName.isEmpty else {
            isSearching = false
            return
        }
        
        let usersRef = Firestore.firestore().collection("users")
        usersRef.whereField("Name", isGreaterThanOrEqualTo: searchName)
            .whereField("Name", isLessThanOrEqualTo: searchName + "\u{f8ff}")
            .getDocuments { querySnapshot, error in
                if let error = error {
                    print("Error searching profiles: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = querySnapshot?.documents, !documents.isEmpty else {
                    self.searchedProfile = nil
                    self.isSearching = true
                    return
                }
                
                for document in documents {
                    let data = document.data()
                    let name = data["Name"] as? String ?? ""
                    let rocketID = data["RocketID"] as? String ?? ""
                    let phoneNumber = data["phoneNumber"] as? String ?? ""
                    let email = document.documentID
                    
                    if name.lowercased().contains(searchName.lowercased()) {
                        self.searchedProfile = UserProfile(name: name, rocketID: rocketID, phoneNumber: phoneNumber, email: email)
                        break
                    }
                }
                
                if self.searchedProfile == nil {
                    self.isSearching = true // No match found
                }
            }
    }
    
    func logOut() {
        do {
            try Auth.auth().signOut()
            userIsSignedOut = true
        } catch {
            print("Error signing out: \(error.localizedDescription)")
        }
    }

    
    func deleteUserAccount() {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        let userEmail = currentUser.email ?? ""
        let userRef = Firestore.firestore().collection("users").document(userEmail)
        
        userRef.delete { error in
            if let error = error {
                print("Error deleting user data: \(error.localizedDescription)")
                return
            }
            
            currentUser.delete { error in
                if let error = error {
                    print("Error deleting Firebase account: \(error.localizedDescription)")
                    return
                }
                
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
