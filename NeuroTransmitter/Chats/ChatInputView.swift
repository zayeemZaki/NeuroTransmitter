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
            if isSuggesting && !suggestedNames.isEmpty {
                List(suggestedNames, id: \.self) { name in
                    Text(name)
                        .onTapGesture {
                            selectName(name)
                        }
                }
                .frame(maxHeight: 200)
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
            let documentName = self.documentURL.lastPathComponent
            
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
                } else {
                    let notificationBody = "\(userName) mentioned you: \(self.messageText)"
                    let broadcastBody = "\(userName) mentioned everyone: \(self.messageText)"
                    
                    if self.messageText.contains("@all") {
                        self.sendNotificationToAllUsers("New Message in \(documentName)", body: broadcastBody)
                    } else {
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
    
    func fetchAccessToken(completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://fcm-token-generator-277454783750.us-central1.run.app/get-access-token") else {
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error fetching access token: \(error)")
                completion(nil)
                return
            }
            
            guard let data = data else {
                print("No data received for access token")
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let token = json["access_token"] as? String {
                    completion(token)
                } else {
                    completion(nil)
                }
            } catch {
                print("Error parsing access token JSON: \(error)")
                completion(nil)
            }
        }.resume()
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
            
            fetchAccessToken { accessToken in
                guard let accessToken = accessToken else {
                    print("Failed to fetch access token")
                    return
                }
                self.sendNotification(to: deviceToken, title: title, body: body, accessToken: accessToken)
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
            
            let deviceTokens = documents.compactMap { $0.data()["FCMToken"] as? String }
            
            fetchAccessToken { accessToken in
                guard let accessToken = accessToken else {
                    print("Failed to fetch access token")
                    return
                }
                for token in deviceTokens {
                    self.sendNotification(to: token, title: title, body: body, accessToken: accessToken)
                }
            }
        }
    }
    
    func sendNotification(to token: String, title: String, body: String, accessToken: String) {
        let message: [String: Any] = [
            "message": [
                "token": token,
                "notification": [
                    "title": title,
                    "body": body
                ]
            ]
        ]
        
        sendNotification(message: message, accessToken: accessToken)
    }
    
    func sendNotification(message: [String: Any], accessToken: String) {
        let url = URL(string: "https://fcm.googleapis.com/v1/projects/neurotransmitter-b15e8/messages:send")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
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
 
