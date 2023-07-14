//
//  ContentView.swift
//  NeuroTransmitter
//
//  Created by Zayeem Zaki on 6/13/23.
//

import SwiftUI
import Firebase


struct SignInView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var userIsLoggedIn = false
    @State private var rememberLogin = false
    @State private var isLoading = true // New state to manage loading state
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




/*
 import SwiftUI
 import Firebase


 struct ContentView: View {
     @State private var email = ""
     @State private var password = ""
     @State private var userIsLoggedIn = false
     @State private var rememberLogin = false
     @State private var isLoading = true // New state to manage loading state
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
         ContentView()
     }
 }
 */
