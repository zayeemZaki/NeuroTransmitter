import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Firebase

struct ChatInputView: View {
    let documentURL: URL
    @State private var messageText = ""
    @Binding var commentText: String?
    @State private var suggestedNames = [String]()
    @State private var isSuggesting = false

    var body: some View {
        VStack {
            // Conditionally display the list of suggested names
            if isSuggesting && !suggestedNames.isEmpty {
                List(suggestedNames, id: \.self) { name in
                    Text(name)
                        .onTapGesture {
                            selectName(name)
                        }
                }
                .frame(maxHeight: 200) // Limit the height of the list
                .listStyle(PlainListStyle())
            }

            HStack {
                TextField("Enter your message...", text: $messageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: messageText) { newValue in
                        handleTyping(text: newValue)
                    }

                Button(action: sendMessage) {
                    Text("Send")
                }
                .disabled(messageText.isEmpty)
            }
            .padding()
        }
    }
    func handleTyping(text: String) {
        if let range = text.range(of: "@", options: .backwards), range.upperBound < text.endIndex {
            let query = String(text[range.upperBound...])
            suggestNames(startingWith: query)
            isSuggesting = true
        } else {
            isSuggesting = false
        }
    }

    func suggestNames(startingWith query: String) {
        // Placeholder for fetching names. Replace with your actual database query logic.
        // For example, query Firestore for users whose names start with 'query'.
        Firestore.firestore().collection("users")
            .whereField("Name", isGreaterThanOrEqualTo: query)
            .whereField("Name", isLessThanOrEqualTo: query + "\u{f8ff}")
            .getDocuments { (snapshot, error) in
                if let documents = snapshot?.documents {
                    self.suggestedNames = documents.map { $0["Name"] as? String ?? "" }
                }
            }
    }

    func selectName(_ name: String) {
        if let range = messageText.range(of: "@", options: .backwards) {
            let prefix = messageText[..<range.lowerBound]
            messageText = prefix + "@\(name) "
        } else {
            messageText += name + " "
        }
        isSuggesting = false
    }

    func fetchUserName(userEmail: String, completion: @escaping (String) -> Void) {
        let userRef = Firestore.firestore().collection("users").document(userEmail)
        userRef.getDocument { documentSnapshot, error in
            if let document = documentSnapshot, document.exists, let userName = document.data()?["Name"] as? String {
                completion(userName)
            } 
            else {
                print("Error fetching user name or user does not exist.")
                completion("Unknown User")
            }
        }
    }

    func sendMessage() {
        guard !messageText.isEmpty else { return }

        guard let currentUser = Auth.auth().currentUser, let senderEmail = currentUser.email else {
            print("User is not signed in.")
            return
        }

        fetchUserName(userEmail: senderEmail) { userName in
            let db = Firestore.firestore()
            let commentUUID = UUID().uuidString
            let documentName = self.documentURL.lastPathComponent // Document name

            let messageData: [String: Any] = [
                "identity": commentUUID,
                "sender_email": senderEmail,
                "content": messageText,
                "timestamp": FieldValue.serverTimestamp()
            ]

            let chatRoomID = self.documentURL.lastPathComponent
            let messagesCollection = db.collection("messages").document(chatRoomID).collection("chats")
            messagesCollection.addDocument(data: messageData) { error in
                if let error = error {
                    print("Error sending message: \(error.localizedDescription)")
                } 
                else {
//                    let notificationBody = "\(userName) mentioned you in \(documentName): \(self.messageText)"
//                    let broadcastBody = "\(userName) mentioned everyone in \(documentName): \(self.messageText)"
                    let notificationBody = "\(userName) mentioned you: \(self.messageText)"
                    let broadcastBody = "\(userName) mentioned everyone: \(self.messageText)"

                    if self.messageText.contains("@all") {
                        self.sendNotificationToAllUsers("New Message in \(documentName)", body: broadcastBody)
                    } 
                    else {
                        let mentionedNames = self.extractNames(from: self.messageText)
                        for name in mentionedNames {
                            self.sendNotificationToUser(named: name, title: "\(documentName)", body: notificationBody)
                        }
                    }

                    DispatchQueue.main.async {
                        self.messageText = ""
                    }
                }
            }
        }
    }



    func extractNames(from message: String) -> [String] {
        let words = message.split(separator: " ")
        let names = words.filter { $0.starts(with: "@") }.map { String($0.dropFirst()) }
        return names
    }

    func sendNotificationToUser(named name: String, title: String, body: String) {
        let db = Firestore.firestore()
        let userRef = db.collection("users").whereField("Name", isEqualTo: name)

        userRef.getDocuments { (snapshot, error) in
            if let error = error {
                print("Error fetching user: \(error.localizedDescription)")
                return
            }

            guard let document = snapshot?.documents.first, let deviceToken = document.data()["FCMToken"] as? String else {
                print("User or device token not found for name: \(name)")
                return
            }


            let message: [String: Any] = [
                "to": deviceToken,
                "notification": ["title": title, "body": body]
            ]
            self.sendNotification(message)
        }
    }


    
    func sendNotificationToAllUsers(_ title: String, body: String) {
        let db = Firestore.firestore()
        db.collection("users").getDocuments { (snapshot, error) in
            if let error = error {
                print("Error fetching user documents: \(error.localizedDescription)")
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("No user documents found.")
                return
            }
            
            // Extract device tokens from user documents
            let deviceTokens = documents.compactMap { $0.data()["FCMToken"] as? String }
            print()
            // Construct the notification message
            let notificationData: [String: Any] = [
                "title": title,
                "body": body
            ]
            
            // Send a notification for each FCM token
            for token in deviceTokens {
                print(token, "\n")
            }

            
            let message: [String: Any] = [
                "registration_ids": deviceTokens, // Send to multiple device tokens
                "notification": notificationData
            ]
            
            sendNotification(message)
        }
    }

    func sendNotification(_ message: [String: Any]) {
        let url = URL(string: "https://fcm.googleapis.com/fcm/send")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("key=AAAAQJmYBQY:APA91bFweLqquY0yd87pET4N5ynwnJOEbHQIFV4IAXl7sCzPo6vXXevD-YirAqnlBNquVontIxm92qPry5PjaMZwTWmoPq_1RxbqHP7onaL_jHZOXMaVz6c1Sk00MZXEIyX92KDCjaxy", forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: message, options: .prettyPrinted)
        } catch let error {
            print("Error serializing notification message: \(error.localizedDescription)")
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error sending notification: \(error.localizedDescription)")
            } else if let data = data {
                let responseString = String(data: data, encoding: .utf8) ?? "No response data"
                print("Response from FCM: \(responseString)")
            }
        }.resume()
    }
}













/*
 import SwiftUI
 import FirebaseAuth
 import FirebaseFirestore
 import Firebase

 struct ChatInputView: View {
     let documentURL: URL
     @State private var messageText = ""
     @Binding var commentText: String?
     @State private var suggestedNames = [String]()
     @State private var isSuggesting = false

     var body: some View {
         VStack {
             // Conditionally display the list of suggested names
             if isSuggesting && !suggestedNames.isEmpty {
                 List(suggestedNames, id: \.self) { name in
                     Text(name)
                         .onTapGesture {
                             selectName(name)
                         }
                 }
                 .frame(maxHeight: 200) // Limit the height of the list
                 .listStyle(PlainListStyle())
             }

             HStack {
                 TextField("Enter your message...", text: $messageText)
                     .textFieldStyle(RoundedBorderTextFieldStyle())
                     .onChange(of: messageText) { newValue in
                         handleTyping(text: newValue)
                     }

                 Button(action: sendMessage) {
                     Text("Send")
                 }
                 .disabled(messageText.isEmpty)
             }
             .padding()
         }
     }
     func handleTyping(text: String) {
         if let range = text.range(of: "@", options: .backwards), range.upperBound < text.endIndex {
             let query = String(text[range.upperBound...])
             suggestNames(startingWith: query)
             isSuggesting = true
         } else {
             isSuggesting = false
         }
     }

     func suggestNames(startingWith query: String) {
         // Placeholder for fetching names. Replace with your actual database query logic.
         // For example, query Firestore for users whose names start with 'query'.
         Firestore.firestore().collection("users")
             .whereField("Name", isGreaterThanOrEqualTo: query)
             .whereField("Name", isLessThanOrEqualTo: query + "\u{f8ff}")
             .getDocuments { (snapshot, error) in
                 if let documents = snapshot?.documents {
                     self.suggestedNames = documents.map { $0["Name"] as? String ?? "" }
                 }
             }
     }

     func selectName(_ name: String) {
         if let range = messageText.range(of: "@", options: .backwards) {
             let prefix = messageText[..<range.lowerBound]
             messageText = prefix + "@\(name) "
         } else {
             messageText += name + " "
         }
         isSuggesting = false
     }

     func fetchUserName(userEmail: String, completion: @escaping (String) -> Void) {
         let userRef = Firestore.firestore().collection("users").document(userEmail)
         userRef.getDocument { documentSnapshot, error in
             if let document = documentSnapshot, document.exists, let userName = document.data()?["Name"] as? String {
                 completion(userName)
             }
             else {
                 print("Error fetching user name or user does not exist.")
                 completion("Unknown User")
             }
         }
     }

     func sendMessage() {
         guard !messageText.isEmpty else { return }

         guard let currentUser = Auth.auth().currentUser, let senderEmail = currentUser.email else {
             print("User is not signed in.")
             return
         }

         fetchUserName(userEmail: senderEmail) { userName in
             let db = Firestore.firestore()
             let commentUUID = UUID().uuidString
             let documentName = self.documentURL.lastPathComponent // Document name

             let messageData: [String: Any] = [
                 "identity": commentUUID,
                 "sender_email": senderEmail,
                 "content": messageText,
                 "timestamp": FieldValue.serverTimestamp()
             ]

             let chatRoomID = self.documentURL.lastPathComponent
             let messagesCollection = db.collection("messages").document(chatRoomID).collection("chats")
             messagesCollection.addDocument(data: messageData) { error in
                 if let error = error {
                     print("Error sending message: \(error.localizedDescription)")
                 }
                 else {
 //                    let notificationBody = "\(userName) mentioned you in \(documentName): \(self.messageText)"
 //                    let broadcastBody = "\(userName) mentioned everyone in \(documentName): \(self.messageText)"
                     let notificationBody = "\(userName) mentioned you: \(self.messageText)"
                     let broadcastBody = "\(userName) mentioned everyone: \(self.messageText)"

                     if self.messageText.contains("@all") {
                         self.sendNotificationToAllUsers("New Message in \(documentName)", body: broadcastBody)
                     }
                     else {
                         let mentionedNames = self.extractNames(from: self.messageText)
                         for name in mentionedNames {
                             self.sendNotificationToUser(named: name, title: "\(documentName)", body: notificationBody)
                         }
                     }

                     DispatchQueue.main.async {
                         self.messageText = ""
                     }
                 }
             }
         }
     }



     func extractNames(from message: String) -> [String] {
         let words = message.split(separator: " ")
         let names = words.filter { $0.starts(with: "@") }.map { String($0.dropFirst()) }
         return names
     }

     func sendNotificationToUser(named name: String, title: String, body: String) {
         let db = Firestore.firestore()
         let userRef = db.collection("users").whereField("Name", isEqualTo: name)

         userRef.getDocuments { (snapshot, error) in
             if let error = error {
                 print("Error fetching user: \(error.localizedDescription)")
                 return
             }

             guard let document = snapshot?.documents.first, let deviceToken = document.data()["FCMToken"] as? String else {
                 print("User or device token not found for name: \(name)")
                 return
             }


             let message: [String: Any] = [
                 "to": deviceToken,
                 "notification": ["title": title, "body": body]
             ]
             self.sendNotification(message)
         }
     }


     
     func sendNotificationToAllUsers(_ title: String, body: String) {
         let db = Firestore.firestore()
         db.collection("users").getDocuments { (snapshot, error) in
             if let error = error {
                 print("Error fetching user documents: \(error.localizedDescription)")
                 return
             }
             
             guard let documents = snapshot?.documents else {
                 print("No user documents found.")
                 return
             }
             
             // Extract device tokens from user documents
             let deviceTokens = documents.compactMap { $0.data()["FCMToken"] as? String }
             print()
             // Construct the notification message
             let notificationData: [String: Any] = [
                 "title": title,
                 "body": body
             ]
             
             // Send a notification for each FCM token
             for token in deviceTokens {
                 print(token, "\n")
             }

             
             let message: [String: Any] = [
                 "registration_ids": deviceTokens, // Send to multiple device tokens
                 "notification": notificationData
             ]
             
             sendNotification(message)
         }
     }

     func sendNotification(_ message: [String: Any]) {
         let url = URL(string: "https://fcm.googleapis.com/fcm/send")!
         var request = URLRequest(url: url)
         request.httpMethod = "POST"
         request.setValue("application/json", forHTTPHeaderField: "Content-Type")
         request.setValue("key=AAAAQJmYBQY:APA91bFweLqquY0yd87pET4N5ynwnJOEbHQIFV4IAXl7sCzPo6vXXevD-YirAqnlBNquVontIxm92qPry5PjaMZwTWmoPq_1RxbqHP7onaL_jHZOXMaVz6c1Sk00MZXEIyX92KDCjaxy", forHTTPHeaderField: "Authorization")

         do {
             request.httpBody = try JSONSerialization.data(withJSONObject: message, options: .prettyPrinted)
         } catch let error {
             print("Error serializing notification message: \(error.localizedDescription)")
             return
         }

         URLSession.shared.dataTask(with: request) { data, response, error in
             if let error = error {
                 print("Error sending notification: \(error.localizedDescription)")
             } else if let data = data {
                 let responseString = String(data: data, encoding: .utf8) ?? "No response data"
                 print("Response from FCM: \(responseString)")
             }
         }.resume()
     }
 }
 */




















/*
 import SwiftUI
 import FirebaseAuth
 import FirebaseFirestore
 import Firebase

 struct ChatInputView: View {
     let documentURL: URL
     @State private var messageText = ""
     @Binding var commentText: String?
     @State private var suggestedNames = [String]()
     @State private var isSuggesting = false

     var body: some View {
         VStack {
             HStack {
                 TextField("Enter your message...", text: $messageText, onEditingChanged: { _ in }, onCommit: {})
                     .textFieldStyle(RoundedBorderTextFieldStyle())
                     .onChange(of: messageText) { newValue in
                         handleTyping(text: newValue)
                     }

                 Button(action: sendMessage) {
                     Text("Send")
                 }
                 .disabled(messageText.isEmpty)
             }
             .padding()

             if isSuggesting {
                 List(suggestedNames, id: \.self) { name in
                     Text(name).onTapGesture {
                         selectName(name)
                     }
                 }
             }
         }
     }

     func handleTyping(text: String) {
         if let range = text.range(of: "@", options: .backwards), range.upperBound < text.endIndex {
             let query = String(text[range.upperBound...])
             suggestNames(startingWith: query)
             isSuggesting = true
         } else {
             isSuggesting = false
         }
     }

     func suggestNames(startingWith query: String) {
         // Placeholder for fetching names. Replace with your actual database query logic.
         // For example, query Firestore for users whose names start with 'query'.
         Firestore.firestore().collection("users")
             .whereField("Name", isGreaterThanOrEqualTo: query)
             .whereField("Name", isLessThanOrEqualTo: query + "\u{f8ff}")
             .getDocuments { (snapshot, error) in
                 if let documents = snapshot?.documents {
                     self.suggestedNames = documents.map { $0["Name"] as? String ?? "" }
                 }
             }
     }

     func selectName(_ name: String) {
         if let range = messageText.range(of: "@", options: .backwards) {
             let prefix = messageText[..<range.lowerBound]
             messageText = prefix + "@\(name) "
         } else {
             messageText += name + " "
         }
         isSuggesting = false
     }

     func fetchUserName(userEmail: String, completion: @escaping (String) -> Void) {
         let userRef = Firestore.firestore().collection("users").document(userEmail)
         userRef.getDocument { documentSnapshot, error in
             if let document = documentSnapshot, document.exists, let userName = document.data()?["Name"] as? String {
                 completion(userName)
             }
             else {
                 print("Error fetching user name or user does not exist.")
                 completion("Unknown User")
             }
         }
     }

     func sendMessage() {
         guard !messageText.isEmpty else { return }

         guard let currentUser = Auth.auth().currentUser, let senderEmail = currentUser.email else {
             print("User is not signed in.")
             return
         }

         fetchUserName(userEmail: senderEmail) { userName in
             let db = Firestore.firestore()
             let commentUUID = UUID().uuidString
             let documentName = self.documentURL.lastPathComponent // Document name

             let messageData: [String: Any] = [
                 "identity": commentUUID,
                 "sender_email": senderEmail,
                 "content": messageText,
                 "timestamp": FieldValue.serverTimestamp()
             ]

             let chatRoomID = self.documentURL.lastPathComponent
             let messagesCollection = db.collection("messages").document(chatRoomID).collection("chats")
             messagesCollection.addDocument(data: messageData) { error in
                 if let error = error {
                     print("Error sending message: \(error.localizedDescription)")
                 }
                 else {
 //                    let notificationBody = "\(userName) mentioned you in \(documentName): \(self.messageText)"
 //                    let broadcastBody = "\(userName) mentioned everyone in \(documentName): \(self.messageText)"
                     let notificationBody = "\(userName) mentioned you: \(self.messageText)"
                     let broadcastBody = "\(userName) mentioned everyone: \(self.messageText)"

                     if self.messageText.contains("@all") {
                         self.sendNotificationToAllUsers("New Message in \(documentName)", body: broadcastBody)
                     }
                     else {
                         let mentionedNames = self.extractNames(from: self.messageText)
                         for name in mentionedNames {
                             self.sendNotificationToUser(named: name, title: "\(documentName)", body: notificationBody)
                         }
                     }

                     DispatchQueue.main.async {
                         self.messageText = ""
                     }
                 }
             }
         }
     }



     func extractNames(from message: String) -> [String] {
         let words = message.split(separator: " ")
         let names = words.filter { $0.starts(with: "@") }.map { String($0.dropFirst()) }
         return names
     }

     func sendNotificationToUser(named name: String, title: String, body: String) {
         let db = Firestore.firestore()
         let userRef = db.collection("users").whereField("Name", isEqualTo: name)

         userRef.getDocuments { (snapshot, error) in
             if let error = error {
                 print("Error fetching user: \(error.localizedDescription)")
                 return
             }

             guard let document = snapshot?.documents.first, let deviceToken = document.data()["FCMToken"] as? String else {
                 print("User or device token not found for name: \(name)")
                 return
             }


             let message: [String: Any] = [
                 "to": deviceToken,
                 "notification": ["title": title, "body": body]
             ]
             self.sendNotification(message)
         }
     }


     
     func sendNotificationToAllUsers(_ title: String, body: String) {
         let db = Firestore.firestore()
         db.collection("users").getDocuments { (snapshot, error) in
             if let error = error {
                 print("Error fetching user documents: \(error.localizedDescription)")
                 return
             }
             
             guard let documents = snapshot?.documents else {
                 print("No user documents found.")
                 return
             }
             
             // Extract device tokens from user documents
             let deviceTokens = documents.compactMap { $0.data()["FCMToken"] as? String }
             print()
             // Construct the notification message
             let notificationData: [String: Any] = [
                 "title": title,
                 "body": body
             ]
             
             // Send a notification for each FCM token
             for token in deviceTokens {
                 print(token, "\n")
             }

             
             let message: [String: Any] = [
                 "registration_ids": deviceTokens, // Send to multiple device tokens
                 "notification": notificationData
             ]
             
             sendNotification(message)
         }
     }

     func sendNotification(_ message: [String: Any]) {
         let url = URL(string: "https://fcm.googleapis.com/fcm/send")!
         var request = URLRequest(url: url)
         request.httpMethod = "POST"
         request.setValue("application/json", forHTTPHeaderField: "Content-Type")
         request.setValue("key=AAAAQJmYBQY:APA91bFweLqquY0yd87pET4N5ynwnJOEbHQIFV4IAXl7sCzPo6vXXevD-YirAqnlBNquVontIxm92qPry5PjaMZwTWmoPq_1RxbqHP7onaL_jHZOXMaVz6c1Sk00MZXEIyX92KDCjaxy", forHTTPHeaderField: "Authorization")

         do {
             request.httpBody = try JSONSerialization.data(withJSONObject: message, options: .prettyPrinted)
         } catch let error {
             print("Error serializing notification message: \(error.localizedDescription)")
             return
         }

         URLSession.shared.dataTask(with: request) { data, response, error in
             if let error = error {
                 print("Error sending notification: \(error.localizedDescription)")
             } else if let data = data {
                 let responseString = String(data: data, encoding: .utf8) ?? "No response data"
                 print("Response from FCM: \(responseString)")
             }
         }.resume()
     }
 }
 */
















/*
 import SwiftUI
 import FirebaseAuth
 import FirebaseFirestore
 import Firebase

 struct ChatInputView: View {
     let documentURL: URL
     @State private var messageText = ""
     @Binding var commentText: String?
     
     var body: some View {
         HStack {
             TextField("Enter your message...", text: $messageText)
                 .textFieldStyle(RoundedBorderTextFieldStyle())

             Button(action: sendMessage) {
                 Text("Send")
             }
             .disabled(messageText.isEmpty)
         }
         .padding()
     }

     
     func fetchUserName(userEmail: String, completion: @escaping (String) -> Void) {
         let userRef = Firestore.firestore().collection("users").document(userEmail)
         userRef.getDocument { documentSnapshot, error in
             if let document = documentSnapshot, document.exists, let userName = document.data()?["Name"] as? String {
                 completion(userName)
             }
             else {
                 print("Error fetching user name or user does not exist.")
                 completion("Unknown User")
             }
         }
     }

     func sendMessage() {
         guard !messageText.isEmpty else { return }

         guard let currentUser = Auth.auth().currentUser, let senderEmail = currentUser.email else {
             print("User is not signed in.")
             return
         }

         fetchUserName(userEmail: senderEmail) { userName in
             let db = Firestore.firestore()
             let commentUUID = UUID().uuidString
             let documentName = self.documentURL.lastPathComponent // Document name

             let messageData: [String: Any] = [
                 "identity": commentUUID,
                 "sender_email": senderEmail,
                 "content": messageText,
                 "timestamp": FieldValue.serverTimestamp()
             ]

             let chatRoomID = self.documentURL.lastPathComponent
             let messagesCollection = db.collection("messages").document(chatRoomID).collection("chats")
             messagesCollection.addDocument(data: messageData) { error in
                 if let error = error {
                     print("Error sending message: \(error.localizedDescription)")
                 }
                 else {
 //                    let notificationBody = "\(userName) mentioned you in \(documentName): \(self.messageText)"
 //                    let broadcastBody = "\(userName) mentioned everyone in \(documentName): \(self.messageText)"
                     let notificationBody = "\(userName) mentioned you: \(self.messageText)"
                     let broadcastBody = "\(userName) mentioned everyone: \(self.messageText)"

                     if self.messageText.contains("@all") {
                         self.sendNotificationToAllUsers("New Message in \(documentName)", body: broadcastBody)
                     }
                     else {
                         let mentionedNames = self.extractNames(from: self.messageText)
                         for name in mentionedNames {
                             self.sendNotificationToUser(named: name, title: "\(documentName)", body: notificationBody)
                         }
                     }

                     DispatchQueue.main.async {
                         self.messageText = ""
                     }
                 }
             }
         }
     }



     func extractNames(from message: String) -> [String] {
         let words = message.split(separator: " ")
         let names = words.filter { $0.starts(with: "@") }.map { String($0.dropFirst()) }
         return names
     }

     func sendNotificationToUser(named name: String, title: String, body: String) {
         let db = Firestore.firestore()
         let userRef = db.collection("users").whereField("Name", isEqualTo: name)

         userRef.getDocuments { (snapshot, error) in
             if let error = error {
                 print("Error fetching user: \(error.localizedDescription)")
                 return
             }

             guard let document = snapshot?.documents.first, let deviceToken = document.data()["FCMToken"] as? String else {
                 print("User or device token not found for name: \(name)")
                 return
             }


             let message: [String: Any] = [
                 "to": deviceToken,
                 "notification": ["title": title, "body": body]
             ]
             self.sendNotification(message)
         }
     }


     
     func sendNotificationToAllUsers(_ title: String, body: String) {
         let db = Firestore.firestore()
         db.collection("users").getDocuments { (snapshot, error) in
             if let error = error {
                 print("Error fetching user documents: \(error.localizedDescription)")
                 return
             }
             
             guard let documents = snapshot?.documents else {
                 print("No user documents found.")
                 return
             }
             
             // Extract device tokens from user documents
             let deviceTokens = documents.compactMap { $0.data()["FCMToken"] as? String }
             print()
             // Construct the notification message
             let notificationData: [String: Any] = [
                 "title": title,
                 "body": body
             ]
             
             // Send a notification for each FCM token
             for token in deviceTokens {
                 print(token, "\n")
             }

             
             let message: [String: Any] = [
                 "registration_ids": deviceTokens, // Send to multiple device tokens
                 "notification": notificationData
             ]
             
             sendNotification(message)
         }
     }

     func sendNotification(_ message: [String: Any]) {
         let url = URL(string: "https://fcm.googleapis.com/fcm/send")!
         var request = URLRequest(url: url)
         request.httpMethod = "POST"
         request.setValue("application/json", forHTTPHeaderField: "Content-Type")
         request.setValue("key=AAAAQJmYBQY:APA91bFweLqquY0yd87pET4N5ynwnJOEbHQIFV4IAXl7sCzPo6vXXevD-YirAqnlBNquVontIxm92qPry5PjaMZwTWmoPq_1RxbqHP7onaL_jHZOXMaVz6c1Sk00MZXEIyX92KDCjaxy", forHTTPHeaderField: "Authorization")

         do {
             request.httpBody = try JSONSerialization.data(withJSONObject: message, options: .prettyPrinted)
         } catch let error {
             print("Error serializing notification message: \(error.localizedDescription)")
             return
         }

         URLSession.shared.dataTask(with: request) { data, response, error in
             if let error = error {
                 print("Error sending notification: \(error.localizedDescription)")
             } else if let data = data {
                 let responseString = String(data: data, encoding: .utf8) ?? "No response data"
                 print("Response from FCM: \(responseString)")
             }
         }.resume()
     }
 }
 */















/*
 import SwiftUI
 import FirebaseAuth
 import FirebaseFirestore
 import Firebase

 struct ChatInputView: View {
     let documentURL: URL
     @State private var messageText = ""
     @Binding var commentText: String?
     
     var body: some View {
         HStack {
             TextField("Enter your message...", text: $messageText)
                 .textFieldStyle(RoundedBorderTextFieldStyle())

             Button(action: sendMessage) {
                 Text("Send")
             }
             .disabled(messageText.isEmpty)
         }
         .padding()
     }

     
     func fetchUserName(userEmail: String, completion: @escaping (String) -> Void) {
         let userRef = Firestore.firestore().collection("users").document(userEmail)
         userRef.getDocument { documentSnapshot, error in
             if let document = documentSnapshot, document.exists, let userName = document.data()?["Name"] as? String {
                 completion(userName)
             }
             else {
                 print("Error fetching user name or user does not exist.")
                 completion("Unknown User")
             }
         }
     }

     func sendMessage() {
         guard !messageText.isEmpty else { return }

         guard let currentUser = Auth.auth().currentUser, let senderEmail = currentUser.email else {
             print("User is not signed in.")
             return
         }

         fetchUserName(userEmail: senderEmail) { userName in
             let db = Firestore.firestore()
             let commentUUID = UUID().uuidString
             let documentName = documentURL.lastPathComponent

             let messageData: [String: Any] = [
                 "identity": commentUUID,
                 "sender_email": senderEmail,
                 "content": messageText,
                 "timestamp": FieldValue.serverTimestamp()
             ]

             let chatRoomID = documentURL.lastPathComponent
             let messagesCollection = db.collection("messages").document(chatRoomID).collection("chats")
             messagesCollection.addDocument(data: messageData) { error in
                 if let error = error {
                     print("Error sending message: \(error.localizedDescription)")
                 } else {
                     if self.messageText.contains("@all") {
                         self.sendNotificationToAllUsers("New Message", body: "\(userName) mentioned everyone: \(self.messageText)")
                     }
                     else {
                         let mentionedNames = self.extractNames(from: self.messageText)
                         for name in mentionedNames {
                             self.sendNotificationToUser(named: name, title: "New Message", body: "\(userName) mentioned you: \(self.messageText)")
                         }
                     }

                     DispatchQueue.main.async {
                         self.messageText = ""
                     }
                 }
             }
         }
     }


     func extractNames(from message: String) -> [String] {
         let words = message.split(separator: " ")
         let names = words.filter { $0.starts(with: "@") }.map { String($0.dropFirst()) }
         return names
     }

     func sendNotificationToUser(named name: String, title: String, body: String) {
         let db = Firestore.firestore()
         let userRef = db.collection("users").whereField("Name", isEqualTo: name)

         userRef.getDocuments { (snapshot, error) in
             if let error = error {
                 print("Error fetching user: \(error.localizedDescription)")
                 return
             }

             guard let document = snapshot?.documents.first, let deviceToken = document.data()["FCMToken"] as? String else {
                 print("User or device token not found for name: \(name)")
                 return
             }


             let message: [String: Any] = [
                 "to": deviceToken,
                 "notification": ["title": title, "body": body]
             ]
             self.sendNotification(message)
         }
     }


     
     func sendNotificationToAllUsers(_ title: String, body: String) {
         let db = Firestore.firestore()
         db.collection("users").getDocuments { (snapshot, error) in
             if let error = error {
                 print("Error fetching user documents: \(error.localizedDescription)")
                 return
             }
             
             guard let documents = snapshot?.documents else {
                 print("No user documents found.")
                 return
             }
             
             // Extract device tokens from user documents
             let deviceTokens = documents.compactMap { $0.data()["FCMToken"] as? String }
             print()
             // Construct the notification message
             let notificationData: [String: Any] = [
                 "title": title,
                 "body": body
             ]
             
             // Send a notification for each FCM token
             for token in deviceTokens {
                 print(token, "\n")
             }

             
             let message: [String: Any] = [
                 "registration_ids": deviceTokens, // Send to multiple device tokens
                 "notification": notificationData
             ]
             
             sendNotification(message)
         }
     }

     func sendNotification(_ message: [String: Any]) {
         let url = URL(string: "https://fcm.googleapis.com/fcm/send")!
         var request = URLRequest(url: url)
         request.httpMethod = "POST"
         request.setValue("application/json", forHTTPHeaderField: "Content-Type")
         request.setValue("key=AAAAQJmYBQY:APA91bFweLqquY0yd87pET4N5ynwnJOEbHQIFV4IAXl7sCzPo6vXXevD-YirAqnlBNquVontIxm92qPry5PjaMZwTWmoPq_1RxbqHP7onaL_jHZOXMaVz6c1Sk00MZXEIyX92KDCjaxy", forHTTPHeaderField: "Authorization")

         do {
             request.httpBody = try JSONSerialization.data(withJSONObject: message, options: .prettyPrinted)
         } catch let error {
             print("Error serializing notification message: \(error.localizedDescription)")
             return
         }

         URLSession.shared.dataTask(with: request) { data, response, error in
             if let error = error {
                 print("Error sending notification: \(error.localizedDescription)")
             } else if let data = data {
                 let responseString = String(data: data, encoding: .utf8) ?? "No response data"
                 print("Response from FCM: \(responseString)")
             }
         }.resume()
     }
 }

 */











/*
 import SwiftUI
 import FirebaseAuth
 import FirebaseFirestore
 import Firebase

 struct ChatInputView: View {
     let documentURL: URL
     @State private var messageText = ""
     @Binding var commentText: String?
     
     var body: some View {
         HStack {
             TextField("Enter your message...", text: $messageText)
                 .textFieldStyle(RoundedBorderTextFieldStyle())

             Button(action: sendMessage) {
                 Text("Send")
             }
             .disabled(messageText.isEmpty)
         }
         .padding()
     }

     
     func fetchUserName(userEmail: String, completion: @escaping (String) -> Void) {
         let userRef = Firestore.firestore().collection("users").document(userEmail)
         userRef.getDocument { documentSnapshot, error in
             if let document = documentSnapshot, document.exists, let userName = document.data()?["Name"] as? String {
                 completion(userName)
             }
             else {
                 print("Error fetching user name or user does not exist.")
                 completion("Unknown User")
             }
         }
     }


     func sendMessage() {
         guard !messageText.isEmpty else { return }

         guard let currentUser = Auth.auth().currentUser, let senderEmail = currentUser.email else {
             print("User is not signed in.")
             return
         }

         fetchUserName(userEmail: senderEmail) { userName in
             let db = Firestore.firestore()
             let commentUUID = UUID().uuidString
             let documentName = documentURL.lastPathComponent

             let messageData: [String: Any] = [
                 "identity": commentUUID,
                 "sender_email": senderEmail,
                 "content": messageText,
                 "timestamp": FieldValue.serverTimestamp()
             ]

             let chatRoomID = documentURL.lastPathComponent
             let messagesCollection = db.collection("messages").document(chatRoomID).collection("chats")
             messagesCollection.addDocument(data: messageData) { error in
                 if let error = error {
                     print("Error sending message: \(error.localizedDescription)")
                 }
                 else {
                     let mentionedNames = self.extractNames(from: self.messageText)
                     for name in mentionedNames {
                         self.sendNotificationToUser(named: name, title: "New Message", body: "\(userName) mentioned you: \(self.messageText)")
                     }

                     DispatchQueue.main.async {
                         self.messageText = ""
                     }
                 }
             }
         }
     }

     func extractNames(from message: String) -> [String] {
         let words = message.split(separator: " ")
         let names = words.filter { $0.starts(with: "@") }.map { String($0.dropFirst()) }
         return names
     }

     func sendNotificationToUser(named name: String, title: String, body: String) {
         let db = Firestore.firestore()
         let userRef = db.collection("users").whereField("Name", isEqualTo: name)

         userRef.getDocuments { (snapshot, error) in
             if let error = error {
                 print("Error fetching user: \(error.localizedDescription)")
                 return
             }

             guard let document = snapshot?.documents.first, let deviceToken = document.data()["FCMToken"] as? String else {
                 print("User or device token not found for name: \(name)")
                 return
             }


             let message: [String: Any] = [
                 "to": deviceToken,
                 "notification": ["title": title, "body": body]
             ]
             self.sendNotification(message)
         }
     }


     
     func sendNotificationToAllUsers(_ title: String, body: String) {
         let db = Firestore.firestore()
         db.collection("users").getDocuments { (snapshot, error) in
             if let error = error {
                 print("Error fetching user documents: \(error.localizedDescription)")
                 return
             }
             
             guard let documents = snapshot?.documents else {
                 print("No user documents found.")
                 return
             }
             
             // Extract device tokens from user documents
             let deviceTokens = documents.compactMap { $0.data()["FCMToken"] as? String }
             print()
             // Construct the notification message
             let notificationData: [String: Any] = [
                 "title": title,
                 "body": body
             ]
             
             // Send a notification for each FCM token
             for token in deviceTokens {
                 print(token, "\n")
             }

             
             let message: [String: Any] = [
                 "registration_ids": deviceTokens, // Send to multiple device tokens
                 "notification": notificationData
             ]
             
             sendNotification(message)
         }
     }

     func sendNotification(_ message: [String: Any]) {
         let url = URL(string: "https://fcm.googleapis.com/fcm/send")!
         var request = URLRequest(url: url)
         request.httpMethod = "POST"
         request.setValue("application/json", forHTTPHeaderField: "Content-Type")
         request.setValue("key=AAAAQJmYBQY:APA91bFweLqquY0yd87pET4N5ynwnJOEbHQIFV4IAXl7sCzPo6vXXevD-YirAqnlBNquVontIxm92qPry5PjaMZwTWmoPq_1RxbqHP7onaL_jHZOXMaVz6c1Sk00MZXEIyX92KDCjaxy", forHTTPHeaderField: "Authorization")

         do {
             request.httpBody = try JSONSerialization.data(withJSONObject: message, options: .prettyPrinted)
         } catch let error {
             print("Error serializing notification message: \(error.localizedDescription)")
             return
         }

         URLSession.shared.dataTask(with: request) { data, response, error in
             if let error = error {
                 print("Error sending notification: \(error.localizedDescription)")
             } else if let data = data {
                 let responseString = String(data: data, encoding: .utf8) ?? "No response data"
                 print("Response from FCM: \(responseString)")
             }
         }.resume()
     }
 }

 */
















/*
 import SwiftUI
 import FirebaseAuth
 import FirebaseFirestore
 import Firebase

 struct ChatInputView: View {
     let documentURL: URL
     @State private var messageText = ""
     @Binding var commentText: String?
     
     var body: some View {
         HStack {
             TextField("Enter your message...", text: $messageText)
                 .textFieldStyle(RoundedBorderTextFieldStyle())

             Button(action: sendMessage) {
                 Text("Send")
             }
             .disabled(messageText.isEmpty)
         }
         .padding()
     }
     
     func fetchUserName(userEmail: String, completion: @escaping (String) -> Void) {
         let userRef = Firestore.firestore().collection("users").document(userEmail)
         userRef.getDocument { documentSnapshot, error in
             if let document = documentSnapshot, document.exists, let userName = document.data()?["Name"] as? String {
                 completion(userName)
             } else {
                 print("Error fetching user name or user does not exist.")
                 completion("Unknown User")
             }
         }
     }


     func sendMessage() {
         guard !messageText.isEmpty else { return }

         guard let currentUser = Auth.auth().currentUser, let senderEmail = currentUser.email else {
             print("User is not signed in.")
             return
         }

         fetchUserName(userEmail: senderEmail) { userName in
             let db = Firestore.firestore()
             let commentUUID = UUID().uuidString
             let documentName = documentURL.lastPathComponent

             let messageData: [String: Any] = [
                 "identity": commentUUID,
                 "sender_email": senderEmail,
                 "content": messageText,
                 "timestamp": FieldValue.serverTimestamp()
             ]

             let chatRoomID = documentURL.lastPathComponent
             let messagesCollection = db.collection("messages").document(chatRoomID).collection("chats")
             messagesCollection.addDocument(data: messageData) { error in
                 if let error = error {
                     print("Error sending message: \(error.localizedDescription)")
                 } else {
                     let notificationBody = "\(userName): \(messageText)"
                     sendNotificationToAllUsers(documentName, body: notificationBody)
                     DispatchQueue.main.async {
                         self.messageText = ""
                     }
                 }
             }
         }
     }

     
     func sendNotificationToAllUsers(_ title: String, body: String) {
         let db = Firestore.firestore()
         db.collection("users").getDocuments { (snapshot, error) in
             if let error = error {
                 print("Error fetching user documents: \(error.localizedDescription)")
                 return
             }
             
             guard let documents = snapshot?.documents else {
                 print("No user documents found.")
                 return
             }
             
             // Extract device tokens from user documents
             let deviceTokens = documents.compactMap { $0.data()["FCMToken"] as? String }
             print()
             // Construct the notification message
             let notificationData: [String: Any] = [
                 "title": title,
                 "body": body
             ]
             
             // Send a notification for each FCM token
             for token in deviceTokens {
                 print(token, "\n")
             }

             
             let message: [String: Any] = [
                 "registration_ids": deviceTokens, // Send to multiple device tokens
                 "notification": notificationData
             ]
             
             sendNotification(message)
         }
     }

     func sendNotification(_ message: [String: Any]) {
         let url = URL(string: "https://fcm.googleapis.com/fcm/send")!
         var request = URLRequest(url: url)
         request.httpMethod = "POST"
         request.setValue("application/json", forHTTPHeaderField: "Content-Type")
         request.setValue("key=AAAAQJmYBQY:APA91bFweLqquY0yd87pET4N5ynwnJOEbHQIFV4IAXl7sCzPo6vXXevD-YirAqnlBNquVontIxm92qPry5PjaMZwTWmoPq_1RxbqHP7onaL_jHZOXMaVz6c1Sk00MZXEIyX92KDCjaxy", forHTTPHeaderField: "Authorization")

         do {
             request.httpBody = try JSONSerialization.data(withJSONObject: message, options: .prettyPrinted)
         }
         catch let error {
             print("Error serializing notification message: \(error.localizedDescription)")
             return
         }

         URLSession.shared.dataTask(with: request) { data, response, error in
             if let error = error {
                 print("Error sending notification: \(error.localizedDescription)")
             }
             else if let data = data {
                 // Print the response from FCM
                 let responseString = String(data: data, encoding: .utf8) ?? "No response data"
                 print("Response from FCM: \(responseString)")
             }
         }.resume()
     }
 }

 */
