//
//  ContentView.swift
//  NeuroTransmitter
//
//  Created by Zayeem Zaki on 6/13/23.
//





 import SwiftUI
 import Firebase
 import LocalAuthentication

 struct SignInView: View {
     @State private var email = ""
     @State private var isLoading = true // New state to manage loading state
     @State private var password = ""
     @State private var rememberLogin = false
     @State private var userIsLoggedIn = false
     @Environment(\.colorScheme) var colorScheme
     
     var body: some View {
         Group {
             if isLoading {
                 // Show loading view with app name
                 LoadingView()
                     .onAppear {
                         // Perform loading tasks (e.g., checking authentication, fetching data)
                         // Once loading is complete, set isLoading to false to show login page
                         DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                             isLoading = false
                             checkAuthenticationState()
                         }
                     }
             }
             else {
                 if userIsLoggedIn {
                     NavigationView {
                         FolderListView()
                     }
                     .navigationBarBackButtonHidden(true) // Hide the back button
                 }
                 else {
                     content
                 }
             }
         }
     }
     
     var content: some View {
         NavigationView {
             ZStack {
                 VStack {
                     Text("Email Address")
                         .font(.headline)
                         .foregroundColor(colorScheme == .dark ? .white : .black)
                         .frame(maxWidth: .infinity, alignment: .leading)
                         .padding(.horizontal, 20)
                     
                     TextField("Email Address", text: $email)
                         .foregroundColor(.black)
                         .padding()
                         .frame(maxWidth: .infinity, minHeight: 50)
                         .background(Color.white)
                         .cornerRadius(10)
                         .overlay(
                             RoundedRectangle(cornerRadius: 10)
                                 .stroke(Color.gray, lineWidth: 1)
                         )
                         .padding(.horizontal, 20)
                         .multilineTextAlignment(.leading) // Align to the left
                     
                     Text("Password")
                         .font(.headline)
                         .foregroundColor(colorScheme == .dark ? .white : .black)
                         .frame(maxWidth: .infinity, alignment: .leading)
                         .padding(.horizontal, 20)
                     
                     HStack {
                         SecureFieldWithEyeIcon(
                             text: $password,
                             placeholder: "Password ...",
                             color: .black,
                             isSecure: true
                         )
                         .padding()
                         .frame(maxWidth: .infinity, minHeight: 50)
                         .background(Color.white)
                         .cornerRadius(10)
                         .overlay(
                             RoundedRectangle(cornerRadius: 10)
                                 .stroke(Color.gray, lineWidth: 1)
                         )
                         .padding(.horizontal, 20)
                     }
                     
                     HStack {
                         Spacer()
                         Toggle("Remember Login", isOn: $rememberLogin)
                             .padding()
                             .foregroundColor(colorScheme == .dark ? .white : .black)
                     }
                     
                     Button("Login") {
                         login()
                     }
                     .foregroundColor(.white)
                     .frame(maxWidth: .infinity, minHeight: 50)
                     .background(Color(red: 0.2, green: 0.5, blue: 0.3))
                     .cornerRadius(10)
                     .padding(.horizontal, 20)
                     
                     .toolbar {
                         ToolbarItem(placement: .bottomBar) {
                             VStack {
                                 HStack {
                                     Text("Don't have an account?")
                                     
                                     NavigationLink(destination: SignUpPage()) {
                                         Text("Sign up")
                                             .bold()
                                     }
                                     .buttonStyle(PlainButtonStyle()) // Remove the default button style
                                 }
                                 .cornerRadius(10)
                                 .foregroundColor(colorScheme == .dark ? .white : .black)
                                 
                             }
                         }
                     }
                 }
                 .onAppear {
                     checkAuthenticationState()
                     
                     if !userIsLoggedIn {
                         authenticateWithFaceID()
                     }
                 }
             }
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
         }
         .navigationBarBackButtonHidden(true) // Hide the back button
         .background(colorScheme == .dark ? Color.black : Color.white)
     }
     
     func checkAuthenticationState() {
         if UserDefaults.standard.bool(forKey: "isLoggedIn") {
             userIsLoggedIn = true
         } else {
             userIsLoggedIn = false
         }
     }
     
     func login() {
         Auth.auth().signIn(withEmail: email, password: password) { result, error in
             if let error = error {
                 print(error.localizedDescription)
             }
             else {
                 // Login successful
                 if rememberLogin {
                     // Save the login status if rememberLogin is enabled
                     UserDefaults.standard.set(true, forKey: "isLoggedIn")
                 }
                 userIsLoggedIn = true
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
                             print("Hell")
                             userIsLoggedIn = true
                         }
                     } else {
                         // Handle authentication failure or cancellation
                         print("Authentication failed: \(error?.localizedDescription ?? "Unknown error")")
                     }
                 })
             } else {
                 // Device doesn't support Face ID or there was an error
                 print("Face ID not available: \(error?.localizedDescription ?? "Unknown error")")
             }
         }

     
 }

 struct SecureFieldWithEyeIcon: View {
     @Binding var text: String
     var placeholder: String
     var color: Color
     var isSecure: Bool
     
     @State private var isTextSecure = true
     
     var body: some View {
         HStack {
             if isSecure {
                 if isTextSecure {
                     SecureField(placeholder, text: $text)
                         .foregroundColor(color)
                 }
                 else {
                     TextField(placeholder, text: $text)
                         .foregroundColor(color)
                 }
                 Button(action: {
                     isTextSecure.toggle()
                 }){
                     Image(systemName: isTextSecure ? "eye.slash.fill" : "eye.fill")
                         .foregroundColor(color)
                 }
             }
             else {
                 SecureField(placeholder, text: $text)
                     .foregroundColor(color)
             }
         }
     }
 }

 struct ContentView_Previews: PreviewProvider {
     static var previews: some View {
         SignInView()
     }
 }

 





//use this later !!!!!




/*
 import SwiftUI
 import Firebase
 import LocalAuthentication

 struct SignInView: View {
     @State private var email = ""
     @State private var isLoading = true // New state to manage loading state
     @State private var password = ""
     @State private var rememberLogin = false
     @State private var userIsLoggedIn = false
     @Environment(\.colorScheme) var colorScheme
     @State private var errorMessage = ""
     @State private var faceIDAuthenticated = false

     var body: some View {
         Group {
             if isLoading {
                 // Show loading view with app name
                 LoadingView()
                     .onAppear {
                         // Perform loading tasks (e.g., checking authentication, fetching data)
                         // Once loading is complete, set isLoading to false to show login page
                         DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                             isLoading = false
                             checkAuthenticationState()
                         }
                     }
             }
             else {
                 if userIsLoggedIn {
                     NavigationView {
                         FolderListView()
                     }
                     .navigationBarBackButtonHidden(true) // Hide the back button
                 }
                 else {
                     content
                 }
             }
         }
     }
     
     var content: some View {
         NavigationView {
             ZStack {
                 VStack {
                     Text("Email Address")
                         .font(.headline)
                         .foregroundColor(colorScheme == .dark ? .white : .black)
                         .frame(maxWidth: .infinity, alignment: .leading)
                         .padding(.horizontal, 20)
                     
                     TextField("Email Address", text: $email)
                         .foregroundColor(.black)
                         .padding()
                         .frame(maxWidth: .infinity, minHeight: 50)
                         .background(Color.white)
                         .cornerRadius(10)
                         .overlay(
                             RoundedRectangle(cornerRadius: 10)
                                 .stroke(Color.gray, lineWidth: 1)
                         )
                         .padding(.horizontal, 20)
                         .multilineTextAlignment(.leading) // Align to the left
                     
                     Text("Password")
                         .font(.headline)
                         .foregroundColor(colorScheme == .dark ? .white : .black)
                         .frame(maxWidth: .infinity, alignment: .leading)
                         .padding(.horizontal, 20)
                     
                     HStack {
                         SecureFieldWithEyeIcon(
                             text: $password,
                             placeholder: "Password ...",
                             color: .black,
                             isSecure: true
                         )
                         .padding()
                         .frame(maxWidth: .infinity, minHeight: 50)
                         .background(Color.white)
                         .cornerRadius(10)
                         .overlay(
                             RoundedRectangle(cornerRadius: 10)
                                 .stroke(Color.gray, lineWidth: 1)
                         )
                         .padding(.horizontal, 20)
                     }
                     
                     HStack {
                         Spacer()
                         Toggle("Remember Login", isOn: $rememberLogin)
                             .padding()
                             .foregroundColor(colorScheme == .dark ? .white : .black)
                     }
                     
                     Button("Login") {
                         login()
                     }
                     .foregroundColor(.white)
                     .frame(maxWidth: .infinity, minHeight: 50)
                     .background(Color(red: 0.2, green: 0.5, blue: 0.3))
                     .cornerRadius(10)
                     .padding(.horizontal, 20)
                     
                     // Display the error message
                     if !errorMessage.isEmpty {
                         Text(errorMessage)
                             .foregroundColor(.red)
                             .padding(.vertical, 5)
                     }
                     
                     // Sign Up Link
                     VStack {
                         HStack {
                             Text("Don't have an account?")
                             
                             NavigationLink(destination: SignUpPage()) {
                                 Text("Sign up")
                                     .bold()
                             }
                             .buttonStyle(PlainButtonStyle()) // Remove the default button style
                         }
                         .cornerRadius(10)
                         .foregroundColor(colorScheme == .dark ? .white : .black)
                     }
                 }
                 .onAppear {
                     checkAuthenticationState()
                     
                     if !userIsLoggedIn {
                         authenticateWithFaceID()
                     }
                 }
             }
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
         }
         .navigationBarBackButtonHidden(true) // Hide the back button
         .background(colorScheme == .dark ? Color.black : Color.white)
     }
     
     func checkAuthenticationState() {
         if UserDefaults.standard.bool(forKey: "isLoggedIn") {
             userIsLoggedIn = true
         } else {
             userIsLoggedIn = false
         }
     }
     
     func login() {
         Auth.auth().signIn(withEmail: email, password: password) { result, error in
             if let error = error {
                 print(error.localizedDescription)
             } else {
                 if let currentUser = Auth.auth().currentUser {
                     if currentUser.isEmailVerified {
                         if rememberLogin {
                             UserDefaults.standard.set(true, forKey: "isLoggedIn")
                         }
                         userIsLoggedIn = true
                     } else {
                         errorMessage = "Please verify your email before signing in."
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
                     DispatchQueue.main.async {
                         if rememberLogin {
                             UserDefaults.standard.set(true, forKey: "isLoggedIn")
                         }
                         
                         if let currentUser = Auth.auth().currentUser {
                             if currentUser.isEmailVerified {
                                 faceIDAuthenticated = true
                             } else {
                                 errorMessage = "Please verify your email before using Face ID."
                             }
                         }
                     }
                 } else {
                     print("Authentication failed: \(error?.localizedDescription ?? "Unknown error")")
                 }
             })
         } else {
             print("Face ID not available: \(error?.localizedDescription ?? "Unknown error")")
         }
     }

     
 }

 struct SecureFieldWithEyeIcon: View {
     @Binding var text: String
     var placeholder: String
     var color: Color
     var isSecure: Bool
     
     @State private var isTextSecure = true
     
     var body: some View {
         HStack {
             if isSecure {
                 if isTextSecure {
                     SecureField(placeholder, text: $text)
                         .foregroundColor(color)
                 }
                 else {
                     TextField(placeholder, text: $text)
                         .foregroundColor(color)
                 }
                 Button(action: {
                     isTextSecure.toggle()
                 }){
                     Image(systemName: isTextSecure ? "eye.slash.fill" : "eye.fill")
                         .foregroundColor(color)
                 }
             }
             else {
                 SecureField(placeholder, text: $text)
                     .foregroundColor(color)
             }
         }
     }
 }

 struct ContentView_Previews: PreviewProvider {
     static var previews: some View {
         SignInView()
     }
 }
 */











/*
 
 
 import SwiftUI
 import Firebase
 import LocalAuthentication

 struct SignInView: View {
     @State private var email = ""
     @State private var isLoading = true // New state to manage loading state
     @State private var password = ""
     @State private var rememberLogin = false
     @State private var userIsLoggedIn = false
     @Environment(\.colorScheme) var colorScheme
     
     var body: some View {
         Group {
             if isLoading {
                 // Show loading view with app name
                 LoadingView()
                     .onAppear {
                         // Perform loading tasks (e.g., checking authentication, fetching data)
                         // Once loading is complete, set isLoading to false to show login page
                         DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                             isLoading = false
                             checkAuthenticationState()
                         }
                     }
             }
             else {
                 if userIsLoggedIn {
                     NavigationView {
                         FolderListView()
                     }
                     .navigationBarBackButtonHidden(true) // Hide the back button
                 }
                 else {
                     content
                 }
             }
         }
     }
     
     var content: some View {
         NavigationView {
             ZStack {
                 VStack {
                     Text("Email Address")
                         .font(.headline)
                         .foregroundColor(colorScheme == .dark ? .white : .black)
                         .frame(maxWidth: .infinity, alignment: .leading)
                         .padding(.horizontal, 20)
                     
                     TextField("Email Address", text: $email)
                         .foregroundColor(.black)
                         .padding()
                         .frame(maxWidth: .infinity, minHeight: 50)
                         .background(Color.white)
                         .cornerRadius(10)
                         .overlay(
                             RoundedRectangle(cornerRadius: 10)
                                 .stroke(Color.gray, lineWidth: 1)
                         )
                         .padding(.horizontal, 20)
                         .multilineTextAlignment(.leading) // Align to the left
                     
                     Text("Password")
                         .font(.headline)
                         .foregroundColor(colorScheme == .dark ? .white : .black)
                         .frame(maxWidth: .infinity, alignment: .leading)
                         .padding(.horizontal, 20)
                     
                     HStack {
                         SecureFieldWithEyeIcon(
                             text: $password,
                             placeholder: "Password ...",
                             color: .black,
                             isSecure: true
                         )
                         .padding()
                         .frame(maxWidth: .infinity, minHeight: 50)
                         .background(Color.white)
                         .cornerRadius(10)
                         .overlay(
                             RoundedRectangle(cornerRadius: 10)
                                 .stroke(Color.gray, lineWidth: 1)
                         )
                         .padding(.horizontal, 20)
                     }
                     
                     HStack {
                         Spacer()
                         Toggle("Remember Login", isOn: $rememberLogin)
                             .padding()
                             .foregroundColor(colorScheme == .dark ? .white : .black)
                     }
                     
                     Button("Login") {
                         login()
                     }
                     .foregroundColor(.white)
                     .frame(maxWidth: .infinity, minHeight: 50)
                     .background(Color(red: 0.2, green: 0.5, blue: 0.3))
                     .cornerRadius(10)
                     .padding(.horizontal, 20)
                     
                     .toolbar {
                         ToolbarItem(placement: .bottomBar) {
                             VStack {
                                 HStack {
                                     Text("Don't have an account?")
                                     
                                     NavigationLink(destination: SignUpPage()) {
                                         Text("Sign up")
                                             .bold()
                                     }
                                     .buttonStyle(PlainButtonStyle()) // Remove the default button style
                                 }
                                 .cornerRadius(10)
                                 .foregroundColor(colorScheme == .dark ? .white : .black)
                                 
                             }
                         }
                     }
                 }
                 .onAppear {
                     checkAuthenticationState()
                     
 //                    if !userIsLoggedIn {
 //                        authenticateWithFaceID()
 //                    }
                 }
             }
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
         }
         .navigationBarBackButtonHidden(true) // Hide the back button
         .background(colorScheme == .dark ? Color.black : Color.white)
     }
     
     func checkAuthenticationState() {
         if UserDefaults.standard.bool(forKey: "isLoggedIn") {
             userIsLoggedIn = true
         } else {
             userIsLoggedIn = false
         }
     }
     
     func login() {
         Auth.auth().signIn(withEmail: email, password: password) { result, error in
             if let error = error {
                 print(error.localizedDescription)
             }
             else {
                 // Login successful
                 if rememberLogin {
                     // Save the login status if rememberLogin is enabled
                     UserDefaults.standard.set(true, forKey: "isLoggedIn")
                 }
                 userIsLoggedIn = true
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
                             print("Hell")
                             userIsLoggedIn = true
                         }
                     } else {
                         // Handle authentication failure or cancellation
                         print("Authentication failed: \(error?.localizedDescription ?? "Unknown error")")
                     }
                 })
             } else {
                 // Device doesn't support Face ID or there was an error
                 print("Face ID not available: \(error?.localizedDescription ?? "Unknown error")")
             }
         }

     
 }

 struct SecureFieldWithEyeIcon: View {
     @Binding var text: String
     var placeholder: String
     var color: Color
     var isSecure: Bool
     
     @State private var isTextSecure = true
     
     var body: some View {
         HStack {
             if isSecure {
                 if isTextSecure {
                     SecureField(placeholder, text: $text)
                         .foregroundColor(color)
                 }
                 else {
                     TextField(placeholder, text: $text)
                         .foregroundColor(color)
                 }
                 Button(action: {
                     isTextSecure.toggle()
                 }){
                     Image(systemName: isTextSecure ? "eye.slash.fill" : "eye.fill")
                         .foregroundColor(color)
                 }
             }
             else {
                 SecureField(placeholder, text: $text)
                     .foregroundColor(color)
             }
         }
     }
 }

 struct ContentView_Previews: PreviewProvider {
     static var previews: some View {
         SignInView()
     }
 }
 */







/*
 
 
 import SwiftUI
 import Firebase
 import LocalAuthentication

 struct SignInView: View {
     @State private var email = ""
     @State private var isLoading = true // New state to manage loading state
     @State private var password = ""
     @State private var rememberLogin = false
     @State private var userIsLoggedIn = false
     @Environment(\.colorScheme) var colorScheme
     
     var body: some View {
         Group {
             if isLoading {
                 // Show loading view with app name
                 LoadingView()
                     .onAppear {
                         // Perform loading tasks (e.g., checking authentication, fetching data)
                         // Once loading is complete, set isLoading to false to show login page
                         DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                             isLoading = false
                             checkAuthenticationState()
                         }
                     }
             }
             else {
                 if userIsLoggedIn {
                     NavigationView {
                         HomePage()
                     }
                     .navigationBarBackButtonHidden(true) // Hide the back button
                 }
                 else {
                     content
                 }
             }
         }
     }
     
     var content: some View {
         NavigationView {
             ZStack {
                 VStack {
                     Text("Email Address")
                         .font(.headline)
                         .foregroundColor(colorScheme == .dark ? .white : .black)
                         .frame(maxWidth: .infinity, alignment: .leading)
                         .padding(.horizontal, 20)
                     
                     TextField("Email Address", text: $email)
                         .foregroundColor(.black)
                         .padding()
                         .frame(maxWidth: .infinity, minHeight: 50)
                         .background(Color.white)
                         .cornerRadius(10)
                         .overlay(
                             RoundedRectangle(cornerRadius: 10)
                                 .stroke(Color.gray, lineWidth: 1)
                         )
                         .padding(.horizontal, 20)
                         .multilineTextAlignment(.leading) // Align to the left
                     
                     Text("Password")
                         .font(.headline)
                         .foregroundColor(colorScheme == .dark ? .white : .black)
                         .frame(maxWidth: .infinity, alignment: .leading)
                         .padding(.horizontal, 20)
                     
                     HStack {
                         SecureFieldWithEyeIcon(
                             text: $password,
                             placeholder: "Password ...",
                             color: .black,
                             isSecure: true
                         )
                         .padding()
                         .frame(maxWidth: .infinity, minHeight: 50)
                         .background(Color.white)
                         .cornerRadius(10)
                         .overlay(
                             RoundedRectangle(cornerRadius: 10)
                                 .stroke(Color.gray, lineWidth: 1)
                         )
                         .padding(.horizontal, 20)
                     }
                     
                     HStack {
                         Spacer()
                         Toggle("Remember Login", isOn: $rememberLogin)
                             .padding()
                             .foregroundColor(colorScheme == .dark ? .white : .black)
                     }
                     
                     Button("Login") {
                         login()
                     }
                     .foregroundColor(.white)
                     .frame(maxWidth: .infinity, minHeight: 50)
                     .background(Color(red: 0.2, green: 0.5, blue: 0.3))
                     .cornerRadius(10)
                     .padding(.horizontal, 20)
                     
                     .toolbar {
                         ToolbarItem(placement: .bottomBar) {
                             VStack {
                                 HStack {
                                     Text("Don't have an account?")
                                     
                                     NavigationLink(destination: SignUpPage()) {
                                         Text("Sign up")
                                             .bold()
                                     }
                                     .buttonStyle(PlainButtonStyle()) // Remove the default button style
                                 }
                                 .cornerRadius(10)
                                 .foregroundColor(colorScheme == .dark ? .white : .black)
                                 
                             }
                         }
                     }
                 }
                 .onAppear {
                     checkAuthenticationState()
                     
                     if !userIsLoggedIn {
                         authenticateWithFaceID()
                     }
                 }
             }
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
         }
         .navigationBarBackButtonHidden(true) // Hide the back button
         .background(colorScheme == .dark ? Color.black : Color.white)
     }
     
     func checkAuthenticationState() {
         if UserDefaults.standard.bool(forKey: "isLoggedIn") {
             userIsLoggedIn = true
         } else {
             userIsLoggedIn = false
         }
     }
     
     func login() {
         Auth.auth().signIn(withEmail: email, password: password) { result, error in
             if let error = error {
                 print(error.localizedDescription)
             }
             else {
                 // Login successful
                 if rememberLogin {
                     // Save the login status if rememberLogin is enabled
                     UserDefaults.standard.set(true, forKey: "isLoggedIn")
                 }
                 userIsLoggedIn = true
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
                             userIsLoggedIn = true
                         }
                     } else {
                         // Handle authentication failure or cancellation
                         print("Authentication failed: \(error?.localizedDescription ?? "Unknown error")")
                     }
                 })
             } else {
                 // Device doesn't support Face ID or there was an error
                 print("Face ID not available: \(error?.localizedDescription ?? "Unknown error")")
             }
         }

     
 }

 struct SecureFieldWithEyeIcon: View {
     @Binding var text: String
     var placeholder: String
     var color: Color
     var isSecure: Bool
     
     @State private var isTextSecure = true
     
     var body: some View {
         HStack {
             if isSecure {
                 if isTextSecure {
                     SecureField(placeholder, text: $text)
                         .foregroundColor(color)
                 }
                 else {
                     TextField(placeholder, text: $text)
                         .foregroundColor(color)
                 }
                 Button(action: {
                     isTextSecure.toggle()
                 }){
                     Image(systemName: isTextSecure ? "eye.slash.fill" : "eye.fill")
                         .foregroundColor(color)
                 }
             }
             else {
                 SecureField(placeholder, text: $text)
                     .foregroundColor(color)
             }
         }
     }
 }

 struct ContentView_Previews: PreviewProvider {
     static var previews: some View {
         SignInView()
     }
 }
 */





/*
 import SwiftUI
 import Firebase

 struct SignInView: View {
     @State private var email = ""
     @State private var isLoading = true // New state to manage loading state
     @State private var password = ""
     @State private var rememberLogin = false
     @State private var userIsLoggedIn = false
     @Environment(\.colorScheme) var colorScheme
     
     var body: some View {
         Group {
             if isLoading {
                 // Show loading view with app name
                 LoadingView()
                     .onAppear {
                         // Perform loading tasks (e.g., checking authentication, fetching data)
                         // Once loading is complete, set isLoading to false to show login page
                         DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                             isLoading = false
                             checkAuthenticationState()
                         }
                     }
             }
             else {
                 if userIsLoggedIn {
                     NavigationView {
                         HomePage()
                     }
                     .navigationBarBackButtonHidden(true) // Hide the back button
                 }
                 else {
                     content
                 }
             }
         }
     }
     
     var content: some View {
         NavigationView {
             ZStack {
                 VStack {
                     Text("Email Address")
                         .font(.headline)
                         .foregroundColor(colorScheme == .dark ? .white : .black)
                         .frame(maxWidth: .infinity, alignment: .leading)
                         .padding(.horizontal, 20)
                     
                     TextField("Email Address", text: $email)
                         .foregroundColor(.black)
                         .padding()
                         .frame(maxWidth: .infinity, minHeight: 50)
                         .background(Color.white)
                         .cornerRadius(10)
                         .overlay(
                             RoundedRectangle(cornerRadius: 10)
                                 .stroke(Color.gray, lineWidth: 1)
                         )
                         .padding(.horizontal, 20)
                         .multilineTextAlignment(.leading) // Align to the left
                     
                     Text("Password")
                         .font(.headline)
                         .foregroundColor(colorScheme == .dark ? .white : .black)
                         .frame(maxWidth: .infinity, alignment: .leading)
                         .padding(.horizontal, 20)
                     
                     HStack {
                         SecureFieldWithEyeIcon(
                             text: $password,
                             placeholder: "Password ...",
                             color: .black,
                             isSecure: true
                         )
                         .padding()
                         .frame(maxWidth: .infinity, minHeight: 50)
                         .background(Color.white)
                         .cornerRadius(10)
                         .overlay(
                             RoundedRectangle(cornerRadius: 10)
                                 .stroke(Color.gray, lineWidth: 1)
                         )
                         .padding(.horizontal, 20)
                     }
                     
                     HStack {
                         Spacer()
                         Toggle("Remember Login", isOn: $rememberLogin)
                             .padding()
                             .foregroundColor(colorScheme == .dark ? .white : .black)
                     }
                     
                     Button("Login") {
                         login()
                     }
                     .foregroundColor(.white)
                     .frame(maxWidth: .infinity, minHeight: 50)
                     .background(Color(red: 0.2, green: 0.5, blue: 0.3))
                     .cornerRadius(10)
                     .padding(.horizontal, 20)
                     
                     .toolbar {
                         ToolbarItem(placement: .bottomBar) {
                             VStack {
                                 HStack {
                                     Text("Don't have an account?")
                                     
                                     NavigationLink(destination: SignUpPage()) {
                                         Text("Sign up")
                                             .bold()
                                     }
                                     .buttonStyle(PlainButtonStyle()) // Remove the default button style
                                 }
                                 .cornerRadius(10)
                                 .foregroundColor(colorScheme == .dark ? .white : .black)
                                 
                             }
                         }
                     }
                 }
                 .onAppear {
                     checkAuthenticationState()
                 }
             }
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
         }
         .navigationBarBackButtonHidden(true) // Hide the back button
         .background(colorScheme == .dark ? Color.black : Color.white)
     }
     
     func checkAuthenticationState() {
         if UserDefaults.standard.bool(forKey: "isLoggedIn") {
             userIsLoggedIn = true
         } else {
             userIsLoggedIn = false
         }
     }
     
     func login() {
         Auth.auth().signIn(withEmail: email, password: password) { result, error in
             if let error = error {
                 print(error.localizedDescription)
             }
             else {
                 // Login successful
                 if rememberLogin {
                     // Save the login status if rememberLogin is enabled
                     UserDefaults.standard.set(true, forKey: "isLoggedIn")
                 }
                 userIsLoggedIn = true
             }
         }
     }
 }

 struct SecureFieldWithEyeIcon: View {
     @Binding var text: String
     var placeholder: String
     var color: Color
     var isSecure: Bool
     
     @State private var isTextSecure = true
     
     var body: some View {
         HStack {
             if isSecure {
                 if isTextSecure {
                     SecureField(placeholder, text: $text)
                         .foregroundColor(color)
                 }
                 else {
                     TextField(placeholder, text: $text)
                         .foregroundColor(color)
                 }
                 Button(action: {
                     isTextSecure.toggle()
                 }){
                     Image(systemName: isTextSecure ? "eye.slash.fill" : "eye.fill")
                         .foregroundColor(color)
                 }
             }
             else {
                 SecureField(placeholder, text: $text)
                     .foregroundColor(color)
             }
         }
     }
 }

 struct ContentView_Previews: PreviewProvider {
     static var previews: some View {
         SignInView()
     }
 }

 */
