import SwiftUI
import Firebase
import FirebaseFirestore

struct SignUpPage: View {
    // MARK: - State Properties
    
    @State private var confirmPassword = ""
    @State private var email = ""
    @State private var errorMessage = ""
    @State private var name = ""
    @State private var password = ""
    @State private var phoneNumber = ""
    @State private var rocketID = ""
    @State private var userIsRegistered = false
    @Environment(\.colorScheme) var colorScheme
    
    // MARK: - View Body
    
    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack {
                        // Name
                        Text("First and Last Name")
                            .font(.headline)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                        
                        TextField("Enter your name", text: $name)
                            .padding()
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color.white)
                            .cornerRadius(10)
                            .foregroundColor(.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray, lineWidth: 1)
                            )
                            .padding(.horizontal, 20)
                        
                        // Email
                        Text("Email Address")
                            .font(.headline)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                        
                        TextField("Enter your Email Address", text: $email)
                            .padding()
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color.white)
                            .cornerRadius(10)
                            .foregroundColor(.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray, lineWidth: 1)
                            )
                            .padding(.horizontal, 20)
                        
                        // Password
                        Text("Password")
                            .font(.headline)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                        
                        SecureField("Password ...", text: $password)
                            .padding()
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color.white)
                            .cornerRadius(10)
                            .foregroundColor(.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray, lineWidth: 1)
                            )
                            .padding(.horizontal, 20)
                        
                        // Confirm Password
                        Text("Confirm Password")
                            .font(.headline)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                        
                        SecureField("Confirm Password ...", text: $confirmPassword)
                            .padding()
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color.white)
                            .cornerRadius(10)
                            .foregroundColor(.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray, lineWidth: 1)
                            )
                            .padding(.horizontal, 20)
                        
                        // Error message
                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .padding()
                        }
                        
                        // Sign Up Button
                        Button("Sign Up") {
                            register()
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: 350, minHeight: 50)
                        .background(Color(red: 0.2, green: 0.5, blue: 0.3))
                        .cornerRadius(10)
                        .padding()
                    }
                    .padding(.vertical, 10)
                    .padding(.bottom, 100) // Adjust the padding based on your needs
                }
            }
        }
        .background(
            NavigationLink(destination: SignInView(), isActive: $userIsRegistered) {
                EmptyView()
            }
            .hidden()
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    HStack {
                        Text("Neuro")
                            .bold()
                            .font(.largeTitle)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .padding(.trailing, -13)
                        
                        Text("Transmitter")
                            .italic()
                            .bold()
                            .font(.largeTitle)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                }
            }
        }
        .padding(.vertical, 10)
    }
    
    // MARK: - User Registration Functions
    
    // Register the user
    func register() {
        guard password == confirmPassword else {
            errorMessage = "Passwords don't match"
            return
        }
        
        Auth.auth().createUser(withEmail: email, password: password) { result, error in
            if let error = error {
                errorMessage = error.localizedDescription
            } else {
                // Registration successful, save additional user data
                saveUserData()
                userIsRegistered = true
            }
        }
    }
    
    // Save user data to Firestore
    func saveUserData() {
        if let userEmail = Auth.auth().currentUser?.email {
            let userData: [String: Any] = [
                "Name": name,
                "RocketID": rocketID,
                "phoneNumber": phoneNumber
            ]
            
            let userRef = Firestore.firestore().collection("users").document(userEmail)
            userRef.setData(userData) { error in
                if let error = error {
                    print("Error saving user data: \(error.localizedDescription)")
                } else {
                    print("User data saved successfully")
                }
            }
        }
    }
}

struct SignUpPage_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SignUpPage()
        }
    }
}







/*
 import SwiftUI
 import Firebase
 import FirebaseFirestore

 struct SignUpPage: View {
     // MARK: - State Properties
     
     @State private var confirmPassword = ""
     @State private var email = ""
     @State private var errorMessage = ""
     @State private var name = ""
     @State private var password = ""
     @State private var phoneNumber = ""
     @State private var rocketID = ""
     @State private var userIsRegistered = false
     @Environment(\.colorScheme) var colorScheme
     
     // MARK: - View Body
     
     var body: some View {
         NavigationView {
             ZStack {
                 ScrollView {
                     VStack {
                         // Name
                         Text("First and Last Name")
                             .font(.headline)
                             .foregroundColor(colorScheme == .dark ? .white : .black)
                             .frame(maxWidth: .infinity, alignment: .leading)
                             .padding(.horizontal, 20)
                         
                         TextField("Enter your name", text: $name)
                             .padding()
                             .frame(maxWidth: .infinity, minHeight: 50)
                             .background(Color.white)
                             .cornerRadius(10)
                             .foregroundColor(.black)
                             .overlay(
                                 RoundedRectangle(cornerRadius: 10)
                                     .stroke(Color.gray, lineWidth: 1)
                             )
                             .padding(.horizontal, 20)
                         
                         // Email
                         Text("Email Address")
                             .font(.headline)
                             .foregroundColor(colorScheme == .dark ? .white : .black)
                             .frame(maxWidth: .infinity, alignment: .leading)
                             .padding(.horizontal, 20)
                         
                         TextField("Enter your Email Address", text: $email)
                             .padding()
                             .frame(maxWidth: .infinity, minHeight: 50)
                             .background(Color.white)
                             .cornerRadius(10)
                             .foregroundColor(.black)
                             .overlay(
                                 RoundedRectangle(cornerRadius: 10)
                                     .stroke(Color.gray, lineWidth: 1)
                             )
                             .padding(.horizontal, 20)
                         
                         // Password
                         Text("Password")
                             .font(.headline)
                             .foregroundColor(colorScheme == .dark ? .white : .black)
                             .frame(maxWidth: .infinity, alignment: .leading)
                             .padding(.horizontal, 20)
                         
                         SecureField("Password ...", text: $password)
                             .padding()
                             .frame(maxWidth: .infinity, minHeight: 50)
                             .background(Color.white)
                             .cornerRadius(10)
                             .foregroundColor(.black)
                             .overlay(
                                 RoundedRectangle(cornerRadius: 10)
                                     .stroke(Color.gray, lineWidth: 1)
                             )
                             .padding(.horizontal, 20)
                         
                         // Confirm Password
                         Text("Confirm Password")
                             .font(.headline)
                             .foregroundColor(colorScheme == .dark ? .white : .black)
                             .frame(maxWidth: .infinity, alignment: .leading)
                             .padding(.horizontal, 20)
                         
                         SecureField("Confirm Password ...", text: $confirmPassword)
                             .padding()
                             .frame(maxWidth: .infinity, minHeight: 50)
                             .background(Color.white)
                             .cornerRadius(10)
                             .foregroundColor(.black)
                             .overlay(
                                 RoundedRectangle(cornerRadius: 10)
                                     .stroke(Color.gray, lineWidth: 1)
                             )
                             .padding(.horizontal, 20)
                         
                         // Error message
                         if !errorMessage.isEmpty {
                             Text(errorMessage)
                                 .foregroundColor(.red)
                                 .padding()
                         }
                         
                         // Sign Up Button
                         Button("Sign Up") {
                             register()
                         }
                         .foregroundColor(.white)
                         .frame(maxWidth: 350, minHeight: 50)
                         .background(Color(red: 0.2, green: 0.5, blue: 0.3))
                         .cornerRadius(10)
                         .padding()
                     }
                     .padding(.vertical, 10)
                     .padding(.bottom, 100) // Adjust the padding based on your needs
                 }
             }
         }
         .background(
             NavigationLink(destination: SignInView(), isActive: $userIsRegistered) {
                 EmptyView()
             }
             .hidden()
         )
         .navigationBarTitleDisplayMode(.inline)
         .toolbar {
             ToolbarItem(placement: .principal) {
                 VStack {
                     HStack {
                         Text("Neuro")
                             .bold()
                             .font(.largeTitle)
                             .foregroundColor(colorScheme == .dark ? .white : .black)
                             .padding(.trailing, -13)
                         
                         Text("Transmitter")
                             .italic()
                             .bold()
                             .font(.largeTitle)
                             .foregroundColor(colorScheme == .dark ? .white : .black)
                     }
                 }
             }
         }
         .padding(.vertical, 10)
     }
     
     // MARK: - User Registration Functions
     
     // Register the user
     func register() {
         guard password == confirmPassword else {
             errorMessage = "Passwords don't match"
             return
         }
         
         Auth.auth().createUser(withEmail: email, password: password) { result, error in
             if let error = error {
                 errorMessage = error.localizedDescription
             } else {
                 // Registration successful, save additional user data
                 saveUserData()
                 userIsRegistered = true
             }
         }
     }
     
     // Save user data to Firestore
     func saveUserData() {
         if let userEmail = Auth.auth().currentUser?.email {
             let userData: [String: Any] = [
                 "Name": name,
                 "RocketID": rocketID,
                 "phoneNumber": phoneNumber
             ]
             
             let userRef = Firestore.firestore().collection("users").document(userEmail)
             userRef.setData(userData) { error in
                 if let error = error {
                     print("Error saving user data: \(error.localizedDescription)")
                 } else {
                     print("User data saved successfully")
                 }
             }
         }
     }
 }

 struct SignUpPage_Previews: PreviewProvider {
     static var previews: some View {
         NavigationStack {
             SignUpPage()
         }
     }
 }

 */
