import SwiftUI
import Firebase
import FirebaseFirestore
import FirebaseMessaging

struct SignUpPage: View {
    
    @State private var confirmPassword = ""
    @State private var email = ""
    @State private var errorMessage = ""
    @State private var name = ""
    @State private var password = ""
    @State private var userIsRegistered = false
    @State private var registrationSuccess = false
    @Environment(\.colorScheme) var colorScheme
    @State private var navigateToLogin = false

    func register() {
        guard password == confirmPassword else {
            errorMessage = "Passwords don't match"
            return
        }

        Auth.auth().createUser(withEmail: email, password: password) { result, error in
            if let error = error {
                errorMessage = error.localizedDescription
            } else {
                // Registration successful
                if let fcmToken = Messaging.messaging().fcmToken {
                    saveUserData(withFCMToken: fcmToken, name: name)
                }
                
                // Navigate to login page
                navigateToLogin = true
            }
        }
    }

    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.5), Color.purple.opacity(0.7)]), startPoint: .top, endPoint: .bottom)
                        .edgesIgnoringSafeArea(.all)

                    ScrollView {
                        VStack(spacing: 20) {
                            Text("Neuro Transmitter")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .padding(.bottom, 50)

                            InputField(title: "First and Last Name", value: $name, isSecure: false)
                            InputField(title: "Email Address", value: $email, isSecure: false)
                            InputField(title: "Password", value: $password, isSecure: true)
                            InputField(title: "Confirm Password", value: $confirmPassword, isSecure: true)
                            
                            if !errorMessage.isEmpty {
                                Text(errorMessage)
                                    .foregroundColor(.red)
                                    .padding()
                            }
                            
                            Button(action: register) {
                                Text("Sign Up")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity, minHeight: 50)
                                    .background(LinearGradient(gradient: Gradient(colors: [Color.green, Color.blue]), startPoint: .leading, endPoint: .trailing))
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                    .padding(.horizontal)
                                    .shadow(radius: 5)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding()
                        // Adjust the content's padding based on the screen width
                        .padding([.leading, .trailing], geometry.size.width > 600 ? (geometry.size.width / 5) : 20)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle()) // Apply stack navigation view style
    }
}




struct InputField: View {
    var title: String
    @Binding var value: String
    var isSecure: Bool
    @Environment(\.colorScheme) var colorScheme // Access the current color scheme
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.headline)
                .foregroundColor(colorScheme == .dark ? .white : .gray) // Conditional text color
                .padding(.leading, 20)

            if isSecure {
                SecureField("Enter \(title.lowercased())", text: $value)
                    .foregroundColor(.black) // Conditional text color
                    .textFieldStyle()
            } 
            else {
                TextField("Enter \(title.lowercased())", text: $value)
                    .foregroundColor(.black) // Conditional text color
                    .textFieldStyle()
            }
        }
    }
}


extension View {
    func textFieldStyle() -> some View {
        self
            .padding()
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.white.opacity(0.7))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray, lineWidth: 1)
            )
            .padding(.horizontal, 20)
    }
}

struct SignUpPage_Previews: PreviewProvider {
    static var previews: some View {
        SignUpPage()
    }
}




/*
 import SwiftUI
 import Firebase
 import FirebaseFirestore
 import FirebaseMessaging

 struct SignUpPage: View {
     
     @State private var confirmPassword = ""
     @State private var email = ""
     @State private var errorMessage = ""
     @State private var name = ""
     @State private var password = ""
     @State private var userIsRegistered = false
     @State private var registrationSuccess = false
     @Environment(\.colorScheme) var colorScheme
     @State private var navigateToLogin = false

     func register() {
         guard password == confirmPassword else {
             errorMessage = "Passwords don't match"
             return
         }

         Auth.auth().createUser(withEmail: email, password: password) { result, error in
             if let error = error {
                 errorMessage = error.localizedDescription
             } else {
                 // Registration successful
                 if let fcmToken = Messaging.messaging().fcmToken {
                     saveUserData(withFCMToken: fcmToken, name: name)
                 }
                 
                 // Navigate to login page
                 navigateToLogin = true
             }
         }
     }

     
     var body: some View {
         NavigationView {
             ZStack {
                 LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.5), Color.purple.opacity(0.7)]), startPoint: .top, endPoint: .bottom)
                     .edgesIgnoringSafeArea(.all)

                 ScrollView {
                     VStack(spacing: 20) {
                         Text("Neuro Transmitter")
                             .font(.largeTitle)
                             .fontWeight(.bold)
                             .foregroundColor(colorScheme == .dark ? .white : .black)
                             .padding(.bottom, 50)

                         InputField(title: "First and Last Name", value: $name, isSecure: false)
                         InputField(title: "Email Address", value: $email, isSecure: false)
                         InputField(title: "Password", value: $password, isSecure: true)
                         InputField(title: "Confirm Password", value: $confirmPassword, isSecure: true)
                         
                         if !errorMessage.isEmpty {
                             Text(errorMessage)
                                 .foregroundColor(.red)
                                 .padding()
                         }
                         
                         Button(action: register) {
                             Text("Sign Up")
                                 .fontWeight(.semibold)
                                 .frame(maxWidth: .infinity, minHeight: 50)
                                 .background(LinearGradient(gradient: Gradient(colors: [Color.green, Color.blue]), startPoint: .leading, endPoint: .trailing))
                                 .foregroundColor(.white)
                                 .cornerRadius(10)
                                 .padding(.horizontal)
                                 .shadow(radius: 5)
                         }
                         .buttonStyle(PlainButtonStyle())
                     }
                     .padding()
                 }
                 NavigationLink(destination: SignInView(successMessage: "Sign up successful"), isActive: $navigateToLogin) {
                     EmptyView()
                 }.hidden()

             }
             .navigationBarHidden(true)
         }
     }
     
 }

 struct InputField: View {
     var title: String
     @Binding var value: String
     var isSecure: Bool
     
     var body: some View {
         VStack(alignment: .leading) {
             Text(title)
                 .font(.headline)
                 .foregroundColor(.gray)
                 .padding(.leading, 20)

             if isSecure {
                 SecureField("Enter \(title.lowercased())", text: $value)
                     .textFieldStyle()
             } else {
                 TextField("Enter \(title.lowercased())", text: $value)
                     .textFieldStyle()
             }
         }
     }
 }

 extension View {
     func textFieldStyle() -> some View {
         self
             .padding()
             .frame(maxWidth: .infinity, minHeight: 50)
             .background(Color.white.opacity(0.7))
             .cornerRadius(10)
             .overlay(
                 RoundedRectangle(cornerRadius: 10)
                     .stroke(Color.gray, lineWidth: 1)
             )
             .padding(.horizontal, 20)
     }
 }

 struct SignUpPage_Previews: PreviewProvider {
     static var previews: some View {
         SignUpPage()
     }
 }
 
 */








/*
 import SwiftUI
 import Firebase
 import FirebaseFirestore
 import FirebaseMessaging

 struct SignUpPage: View {
     
     @State private var confirmPassword = ""
     @State private var email = ""
     @State private var errorMessage = ""
     @State private var name = ""
     @State private var password = ""
     @State private var userIsRegistered = false
     @State private var registrationSuccess = false
     @Environment(\.colorScheme) var colorScheme
     
     
     var body: some View {
         NavigationView {
             ZStack {
                 ScrollView {
                     VStack {
                         
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
                         
                         if !errorMessage.isEmpty {
                             Text(errorMessage)
                                 .foregroundColor(.red)
                                 .padding()
                         }
                         
                         NavigationLink(destination: EmptyView(), isActive: .constant(false)) {
                             Button(action: {
                                 register()
                             }) {
                                 Text("Sign Up")
                                     .foregroundColor(.white)
                                     .frame(maxWidth: 350, minHeight: 50)
                                     .background(Color(red: 0.2, green: 0.5, blue: 0.3))
                                     .cornerRadius(10)
                                     .padding()
                             }
                         }

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
     
     
     func register() {
         guard password == confirmPassword else {
             errorMessage = "Passwords don't match"
             return
         }
         
         Auth.auth().createUser(withEmail: email, password: password) { result, error in
             if let error = error {
                 errorMessage = error.localizedDescription
             }
             else {
                 // Registration successful, send verification email
               //  sendVerificationEmail()

                 if let fcmToken = Messaging.messaging().fcmToken {
                     // Pass the FCM token to saveUserData
                     saveUserData(withFCMToken: fcmToken, name: name)
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
