import SwiftUI
import Firebase
import LocalAuthentication
import FirebaseMessaging
import FirebaseFirestore
import PDFKit


struct SignInView: View {
    @State private var email = ""
    @State private var isLoading = true
    @State private var password = ""
    @State private var rememberLogin = false
    @State private var userIsLoggedIn = false
    @Environment(\.colorScheme) var colorScheme
    @State private var errorMessage = ""
    var successMessage: String? = nil

    var body: some View {
        Group {
            if isLoading {
                LoadingView()
                    .onAppear(perform: performInitialLoading)
            } else {
                if userIsLoggedIn {
                    NavigationView {
                        FolderListView()
                            .navigationBarTitle("", displayMode: .inline) // Optionally hide the navigation bar title
                            .navigationBarHidden(true) // Hide the navigation bar to use the full screen for content
                    }
                    .navigationViewStyle(StackNavigationViewStyle()) // Use stack style to ensure full-screen presentation on iPad
                    // The following frame modifier ensures the view can expand fully. It might be redundant
                    // depending on your NavigationView's configuration and the views it contains.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationBarBackButtonHidden(true) // Hide the back button
                    .navigationBarItems(leading: EmptyView()) // Remove any leading items

                } else {
                    signInContent
                }
            }
        }
        .edgesIgnoringSafeArea(.all) // Ensure the content extends into the safe area, such as under the notch or the screen corners.
    }


    var signInContent: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    backgroundGradient
                    VStack {
                        displayMessages
                        signInForm
                        signInButton
                        signUpLink
                    }
                    .padding(geometry.size.width > 600 ? 100 : 20) // Conditional padding
                    .frame(width: geometry.size.width)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { toolbarContent }
                }
                .frame(maxWidth: .infinity)
            }
            .navigationBarBackButtonHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle()) // Force stack navigation view style
        .onAppear(perform: authenticateIfNeeded)
    }



    // Helper Views
    var backgroundGradient: some View {
        LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.5), Color.purple.opacity(0.7)]), startPoint: .top, endPoint: .bottom)
            .edgesIgnoringSafeArea(.all)
    }

    var displayMessages: some View {
        Group {
            if let message = successMessage, !message.isEmpty {
                Text(message).foregroundColor(.green).padding()
            }
            if !errorMessage.isEmpty {
                Text(errorMessage).foregroundColor(.red).padding()
            }
        }
    }

    var signInForm: some View {
        VStack {
            
            Text("Email Address")
                .foregroundColor(colorScheme == .dark ? .white : .black) // Adjusts color based on the theme
                .padding(.bottom, 5)
                .fontWeight(.heavy)

            // Email Address
            TextField("Email Address", text: $email)
                .textFieldStyle().foregroundColor(.black)

            Text("Password")
                .foregroundColor(colorScheme == .dark ? .white : .black) // Adjusts color based on the theme
                .padding(.bottom, 5)
                .padding(.top, 5)
                .fontWeight(.heavy)

            // Password
            SecureFieldWithEyeIcon(
                text: $password,
                placeholder: "Password ...",
                color: .black,
                isSecure: true
            )
            .textFieldStyle()
            
            // Remember Login
            Toggle("Remember Login", isOn: $rememberLogin)
                .padding()
                .foregroundColor(colorScheme == .dark ? .white : .black)
        }
    }

    var signInButton: some View {
        Button(action: login) {
            Text("Login")
                .buttonStyle()
        }
    }

    var signUpLink: some View {
        VStack {
            HStack {
                Text("Don't have an account?")
                NavigationLink(destination: SignUpPage()) {
                    Text("Sign up").bold()
                }
                .buttonStyle(PlainButtonStyle())
            }
            .foregroundColor(colorScheme == .dark ? .white : .black)
        }
    }

    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack {
                HStack {
                    Text("Neuro").bold().font(.largeTitle)
                    Text("Transmitter").italic().bold().font(.largeTitle)
                }
                .foregroundColor(colorScheme == .dark ? .white : .black)
            }
        }
    }

    // Helper Functions
    func performInitialLoading() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isLoading = false
            checkAuthenticationState()
        }
    }

    func authenticateIfNeeded() {
        if !userIsLoggedIn {
            authenticateWithFaceID()
        }
    }

    func checkAuthenticationState() {
        userIsLoggedIn = UserDefaults.standard.bool(forKey: "isLoggedIn")
    }

    func login() {
        Auth.auth().signIn(withEmail: email, password: password) { authResult, error in
            if let error = error {
                errorMessage = error.localizedDescription
            } else {
                checkApprovalStatusForFaceID()
            }
        }
    }
    

     // Check user's approval status
     func checkApprovalStatusForFaceID() {
         if let userEmail = Auth.auth().currentUser?.email {
             let userRef = Firestore.firestore().collection("users").document(userEmail)
             userRef.getDocument { document, error in
                 if let document = document, document.exists {
                     let userData = document.data()
                     if let isApproved = userData?["isApproved"] as? Bool, isApproved {
                         // User is approved, allow them to proceed
                         DispatchQueue.main.async {
                             userIsLoggedIn = true
                            // handleSignInSuccess()

                         }
                     }
                     else {
                         // User is not approved yet
                         DispatchQueue.main.async {
                             errorMessage = "Your account is pending approval."
                         }
                     }
                 }
             }
         }
     }

     func authenticateWithFaceID() {
         let context = LAContext()
         var error: NSError?
         
         if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
             context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Authenticate to access the app", reply: { success, error in
                 if success {
                     // User authentication with Face ID succeeded
                     DispatchQueue.main.async {
                         if rememberLogin {
                             UserDefaults.standard.set(true, forKey: "isLoggedIn")
                         }
                         
                         // Check user's approval status before allowing access
                         checkApprovalStatusForFaceID()
                     }
                 }
                 else {
                     // Handle authentication failure or cancellation
                     print("Authentication failed: \(error?.localizedDescription ?? "Unknown error")")
                 }
             })
         }
         else {
             // Device doesn't support Face ID or there was an error
             print("Face ID not available: \(error?.localizedDescription ?? "Unknown error")")
         }
     }
 }

extension View {
    
    func buttonStyle() -> some View {
        self
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(LinearGradient(gradient: Gradient(colors: [Color.green, Color.blue]), startPoint: .leading, endPoint: .trailing))
            .cornerRadius(10)
            .padding(.horizontal)
            .shadow(radius: 5)
    }
}

