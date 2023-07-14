import SwiftUI
import Firebase
import FirebaseAuth
import FirebaseFirestore
//import SwiftFuzzy
import Fuse

struct Profile: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var userIsSignedOut = false
    @State private var isEditing = false
    @State private var editedName = ""
    @State private var editedRocketID = ""
    @State private var editedPhoneNumber = ""
    @State private var currentUserEmail = ""
    @State private var searchName = ""
    @State private var searchedProfile: UserProfile?
    @State private var isSearching = false
    
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
                            HStack {
                                Text("Name: ")
                                    .bold()
                                TextField("Name", text: $editedName)
                            }
                            HStack {
                                Text("Rocket ID: ")
                                    .bold()
                                TextField("Rocket ID", text: $editedRocketID)
                            }
                            HStack {
                                Text("Phone Number: ")
                                    .bold()
                                
                                TextField("Phone Number", text: $editedPhoneNumber)
                            }
                        } else {
                            HStack {
                                Text("Name: ")
                                    .bold()
                                Text("\(editedName)")
                            }
                            HStack {
                                Text("Rocket ID: ")
                                    .bold()
                                Text("\(editedRocketID)")
                                
                            }
                            HStack {
                                Text("Phone Number: ")
                                    .bold()
                                Text("\(editedPhoneNumber)")
                                
                            }
                        }
                        HStack {
                            Text("Email ID: ")
                                .bold()
                            Text("\(currentUserEmail)")
                            
                        }
                        Spacer()
                        Button("Log Out") {
                            logOut()
                        }
                        .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                        
                    }
                    
                    Section(header: Text("Search Profiles")) {
                        HStack {
                            TextField("Search by Name", text: $searchName)
                            Button(action: {
                                searchProfiles()
                            }) {
                                Text("Search")
                                    .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                            }
                        }
                        if isSearching {
                            if let profile = searchedProfile {
                                Text("Name: \(profile.name)")
                                    .bold()
                                
                                Text("Rocket ID: \(profile.rocketID)")
                                    .bold()
                                
                                Text("Phone Number: \(profile.phoneNumber)")
                                    .bold()
                                
                                Text("Email ID: \(profile.email)")
                                    .bold()
                                
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
                
             /*   Text("Developed by Zayeem")
                    .foregroundColor(.black)
                    .padding(.bottom)*/
            }
        }
        .navigationTitle("Welcome \(editedName)")
        .navigationBarItems(trailing: editButton)
        .background(
            NavigationLink(destination: ContentView(), isActive: $userIsSignedOut) {
                EmptyView()
            }
                .hidden()
        )
    }
    
    private var editButton: some View {
        Button(action: {
            isEditing.toggle()
            if !isEditing {
                saveUserData()
            }
        }) {
            Text(isEditing ? "Save" : "Edit")
                .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
        }
    }
    
    func fetchUserData() {
        guard let currentUserEmail = Auth.auth().currentUser?.email else {
            print("User is not signed in.")
            return
        }
        
        self.currentUserEmail = currentUserEmail // Update the email
        
        let userRef = Firestore.firestore().collection("users").document(currentUserEmail)
        
        userRef.getDocument { document, error in
            if let error = error {
                // Handle error
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
    
    func saveUserData() {
        guard let currentUserEmail = Auth.auth().currentUser?.email else {
            print("User is not signed in.")
            return
        }
        
        let userRef = Firestore.firestore().collection("users").document(currentUserEmail)
        
        let userData: [String: Any] = [
            "Name": editedName,
            "RocketID": editedRocketID,
            "phoneNumber": editedPhoneNumber
        ]
        
        userRef.setData(userData) { error in
            if let error = error {
                print("Error saving user data: \(error.localizedDescription)")
            } else {
                print("User data saved successfully")
            }
        }
    }
    
    func logOut() {
        do {
            print("signed out")
            try Auth.auth().signOut()
            userIsSignedOut = true
            // Handle successful sign out
        } catch {
            // Handle sign-out error
            print("Error signing out: \(error.localizedDescription)")
        }
    }
    
    func searchProfiles() {
        guard !searchName.isEmpty else {
            return
        }
        
        let usersRef = Firestore.firestore().collection("users")
        
        usersRef.getDocuments { querySnapshot, error in
            if let error = error {
                print("Error searching profiles: \(error.localizedDescription)")
                return
            }
            
            guard let documents = querySnapshot?.documents, !documents.isEmpty else {
                self.searchedProfile = nil
                self.isSearching = true
                return
            }
            
            let searchResults = documents.map { document -> (UserProfile, Int) in
                let data = document.data()
                let name = data["Name"] as? String ?? ""
                let rocketID = data["RocketID"] as? String ?? ""
                let phoneNumber = data["phoneNumber"] as? String ?? ""
                let email = document.documentID
                
                let nameDistance = self.calculateStringDistance(searchName, name)
                let rocketIDDistance = self.calculateStringDistance(searchName, rocketID)
                
                let profile = UserProfile(name: name, rocketID: rocketID, phoneNumber: phoneNumber, email: email)
                let distance = min(nameDistance, rocketIDDistance)
                
                return (profile, distance)
            }
            
            let closestMatch = searchResults.min(by: { $0.1 < $1.1 })
            self.searchedProfile = closestMatch?.0
            self.isSearching = true
        }
    }
    
    func calculateStringDistance(_ str1: String, _ str2: String) -> Int {
        let count1 = str1.count
        let count2 = str2.count
        
        if count1 == 0 { return count2 }
        if count2 == 0 { return count1 }
        
        var matrix = Array(repeating: Array(repeating: 0, count: count2 + 1), count: count1 + 1)
        
        for i in 0...count1 {
            matrix[i][0] = i
        }
        
        for j in 0...count2 {
            matrix[0][j] = j
        }
        
        for i in 1...count1 {
            for j in 1...count2 {
                let char1 = Array(str1)[i - 1]
                let char2 = Array(str2)[j - 1]
                
                if char1 == char2 {
                    matrix[i][j] = matrix[i - 1][j - 1]
                } else {
                    let deletion = matrix[i - 1][j] + 1
                    let insertion = matrix[i][j - 1] + 1
                    let substitution = matrix[i - 1][j - 1] + 1
                    
                    matrix[i][j] = min(deletion, insertion, substitution)
                }
            }
        }
        
        return matrix[count1][count2]
    }
}

struct Profile_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            Profile()
        }
    }
}








/*
 import SwiftUI
 import Firebase
 import FirebaseAuth
 import FirebaseFirestore
 //import SwiftFuzzy
 import Fuse

 struct Profile: View {
     @Environment(\.presentationMode) var presentationMode
     @State private var userIsSignedOut = false
     @State private var isEditing = false
     @State private var editedName = ""
     @State private var editedRocketID = ""
     @State private var editedPhoneNumber = ""
     @State private var currentUserEmail = ""
     @State private var searchName = ""
     @State private var searchedProfile: UserProfile?
     @State private var isSearching = false
     
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
                             HStack {
                                 Text("Name: ")
                                     .bold()
                                 TextField("Name", text: $editedName)
                             }
                             HStack {
                                 Text("Rocket ID: ")
                                     .bold()
                                 TextField("Rocket ID", text: $editedRocketID)
                             }
                             HStack {
                                 Text("Phone Number: ")
                                     .bold()
                                 
                                 TextField("Phone Number", text: $editedPhoneNumber)
                             }
                         } else {
                             HStack {
                                 Text("Name: ")
                                     .bold()
                                 Text("\(editedName)")
                             }
                             HStack {
                                 Text("Rocket ID: ")
                                     .bold()
                                 Text("\(editedRocketID)")
                                 
                             }
                             HStack {
                                 Text("Phone Number: ")
                                     .bold()
                                 Text("\(editedPhoneNumber)")
                                 
                             }
                         }
                         HStack {
                             Text("Email ID: ")
                                 .bold()
                             Text("\(currentUserEmail)")
                             
                         }
                         Spacer()
                         Button("Log Out") {
                             logOut()
                         }
                         .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                         
                     }
                     
                     Section(header: Text("Search Profiles")) {
                         HStack {
                             TextField("Search by Name", text: $searchName)
                             Button(action: {
                                 searchProfiles()
                             }) {
                                 Text("Search")
                                     .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                             }
                         }
                         if isSearching {
                             if let profile = searchedProfile {
                                 Text("Name: \(profile.name)")
                                     .bold()
                                 
                                 Text("Rocket ID: \(profile.rocketID)")
                                     .bold()
                                 
                                 Text("Phone Number: \(profile.phoneNumber)")
                                     .bold()
                                 
                                 Text("Email ID: \(profile.email)")
                                     .bold()
                                 
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
                 
                 Text("Developed by Zayeem")
                     .foregroundColor(.black)
                     .padding(.bottom)
             }
         }
         .navigationTitle("Welcome \(editedName)")
         .navigationBarItems(trailing: editButton)
         .background(
             NavigationLink(destination: ContentView(), isActive: $userIsSignedOut) {
                 EmptyView()
             }
                 .hidden()
         )
     }
     
     private var editButton: some View {
         Button(action: {
             isEditing.toggle()
             if !isEditing {
                 saveUserData()
             }
         }) {
             Text(isEditing ? "Save" : "Edit")
                 .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
         }
     }
     
     func fetchUserData() {
         guard let currentUserEmail = Auth.auth().currentUser?.email else {
             print("User is not signed in.")
             return
         }
         
         self.currentUserEmail = currentUserEmail // Update the email
         
         let userRef = Firestore.firestore().collection("users").document(currentUserEmail)
         
         userRef.getDocument { document, error in
             if let error = error {
                 // Handle error
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
     
     func saveUserData() {
         guard let currentUserEmail = Auth.auth().currentUser?.email else {
             print("User is not signed in.")
             return
         }
         
         let userRef = Firestore.firestore().collection("users").document(currentUserEmail)
         
         let userData: [String: Any] = [
             "Name": editedName,
             "RocketID": editedRocketID,
             "phoneNumber": editedPhoneNumber
         ]
         
         userRef.setData(userData) { error in
             if let error = error {
                 print("Error saving user data: \(error.localizedDescription)")
             } else {
                 print("User data saved successfully")
             }
         }
     }
     
     func logOut() {
         do {
             print("signed out")
             try Auth.auth().signOut()
             userIsSignedOut = true
             // Handle successful sign out
         } catch {
             // Handle sign-out error
             print("Error signing out: \(error.localizedDescription)")
         }
     }
     
     func searchProfiles() {
         guard !searchName.isEmpty else {
             return
         }
         
         let usersRef = Firestore.firestore().collection("users")
         
         usersRef.getDocuments { querySnapshot, error in
             if let error = error {
                 print("Error searching profiles: \(error.localizedDescription)")
                 return
             }
             
             guard let documents = querySnapshot?.documents, !documents.isEmpty else {
                 self.searchedProfile = nil
                 self.isSearching = true
                 return
             }
             
             let searchResults = documents.map { document -> (UserProfile, Int) in
                 let data = document.data()
                 let name = data["Name"] as? String ?? ""
                 let rocketID = data["RocketID"] as? String ?? ""
                 let phoneNumber = data["phoneNumber"] as? String ?? ""
                 let email = document.documentID
                 
                 let nameDistance = self.calculateStringDistance(searchName, name)
                 let rocketIDDistance = self.calculateStringDistance(searchName, rocketID)
                 
                 let profile = UserProfile(name: name, rocketID: rocketID, phoneNumber: phoneNumber, email: email)
                 let distance = min(nameDistance, rocketIDDistance)
                 
                 return (profile, distance)
             }
             
             let closestMatch = searchResults.min(by: { $0.1 < $1.1 })
             self.searchedProfile = closestMatch?.0
             self.isSearching = true
         }
     }
     
     func calculateStringDistance(_ str1: String, _ str2: String) -> Int {
         let count1 = str1.count
         let count2 = str2.count
         
         if count1 == 0 { return count2 }
         if count2 == 0 { return count1 }
         
         var matrix = Array(repeating: Array(repeating: 0, count: count2 + 1), count: count1 + 1)
         
         for i in 0...count1 {
             matrix[i][0] = i
         }
         
         for j in 0...count2 {
             matrix[0][j] = j
         }
         
         for i in 1...count1 {
             for j in 1...count2 {
                 let char1 = Array(str1)[i - 1]
                 let char2 = Array(str2)[j - 1]
                 
                 if char1 == char2 {
                     matrix[i][j] = matrix[i - 1][j - 1]
                 } else {
                     let deletion = matrix[i - 1][j] + 1
                     let insertion = matrix[i][j - 1] + 1
                     let substitution = matrix[i - 1][j - 1] + 1
                     
                     matrix[i][j] = min(deletion, insertion, substitution)
                 }
             }
         }
         
         return matrix[count1][count2]
     }
 }

 struct Profile_Previews: PreviewProvider {
     static var previews: some View {
         NavigationView {
             Profile()
         }
     }
 } */
