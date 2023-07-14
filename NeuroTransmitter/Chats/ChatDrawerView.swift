import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ChatDrawerView: View {
    @Binding var chatMessages: [ChatMessage]
    let documentURL: URL
    @Binding var commentText: String?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack {
            Text("Chat Messages")
                .font(.title)
                .padding()
            
            List(chatMessages) { message in
                VStack(alignment: .leading) {
                    HStack {
                        Text("\(message.senderName):")
                            .fontWeight(.bold)
                            .foregroundColor(colorScheme == .dark ? .pink : .blue)

                        Text(formatTimestamp(message.timestamp))
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    HStack {
                        Text(message.content)
                            .font(.body) // Set the desired text style for the content
                            .padding(.leading, 5)
                    }
                }
            }
            .padding(.horizontal)
            
            Spacer()
            
            ChatInputView(documentURL: documentURL, commentText: $commentText)
        }
        .onAppear {
            fetchChatMessages()
        }
    }

    // Helper function to format the timestamp as a string
    func formatTimestamp(_ timestamp: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }


    func fetchChatMessages() {
        guard let currentUserEmail = Auth.auth().currentUser?.email else {
            print("User is not signed in.")
            return
        }
        
        let db = Firestore.firestore()
        db.collection("messages").document(documentURL.lastPathComponent).collection("chats").order(by: "timestamp", descending: false).addSnapshotListener { querySnapshot, error in
            guard let documents = querySnapshot?.documents else {
                print("Error fetching chat messages: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            var updatedChatMessages = [ChatMessage]()
            let dispatchGroup = DispatchGroup()
            
            for document in documents {
                let data = document.data()
                
                guard let senderEmail = data["sender_email"] as? String,
                      let content = data["content"] as? String,
                      let identity = data["identity"] as? String,
                      let timestamp = data["timestamp"] as? Timestamp else {
                    continue
                }
                
                dispatchGroup.enter()
                let senderName = senderEmail != currentUserEmail ? senderEmail : "You"
                
                let chatMessage = ChatMessage(identity: identity, senderEmail: senderEmail, senderName: senderName, content: content, timestamp: timestamp.dateValue())
                updatedChatMessages.append(chatMessage)
                
                let userRef = Firestore.firestore().collection("users").document(senderEmail)
                
                userRef.getDocument { document, error in
                    defer {
                        dispatchGroup.leave()
                    }
                    
                    if let error = error {
                        print("Error fetching user data: \(error.localizedDescription)")
                        return
                    }
                    
                    if let document = document, document.exists {
                        let data = document.data()
                        let senderName = data?["Name"] as? String ?? ""
                        
                        DispatchQueue.main.async {
                            if let index = updatedChatMessages.firstIndex(where: { $0.identity == identity }) {
                                var updatedMessage = updatedChatMessages[index]
                                updatedMessage.senderName = senderName
                                updatedChatMessages[index] = updatedMessage
                            }
                        }
                    }
                }
            }
            
            dispatchGroup.notify(queue: .main) {
                self.chatMessages = updatedChatMessages
            }
        }
    }
}



struct ChatMessage: Identifiable {
    let id = UUID()
    let identity: String
    let senderEmail: String
    var senderName: String
    let content: String
    let timestamp: Date
}

struct ChatThread: Identifiable {
    let id = UUID()
    let document: Document
    var chatMessages: [ChatMessage]
}












/*
 import SwiftUI
 import FirebaseAuth
 import FirebaseFirestore

 struct ChatDrawerView: View {
     @Binding var chatMessages: [ChatMessage]
     let documentURL: URL
     @Binding var commentText: String?
     @Environment(\.colorScheme) var colorScheme

     var body: some View {
         VStack {
             Text("Chat Messages")
                 .font(.title)
                 .padding()
             
             List(chatMessages) { message in
                 VStack(alignment: .leading) {
                     HStack {
                         Text("\(message.senderName):")
                             .fontWeight(.bold)
                             .foregroundColor(colorScheme == .dark ? .pink : .blue)

                         Text(formatTimestamp(message.timestamp))
                             .font(.caption)
                             .foregroundColor(.gray)
                     }
                     HStack {
                         Text(message.content)
                             .font(.body) // Set the desired text style for the content
                             .padding(.leading, 5)
                     }
                 }
             }
             .padding(.horizontal)
             
             Spacer()
             
             ChatInputView(documentURL: documentURL, commentText: $commentText)
         }
         .onAppear {
             fetchChatMessages()
         }
     }

     // Helper function to format the timestamp as a string
     func formatTimestamp(_ timestamp: Date) -> String {
         let formatter = DateFormatter()
         formatter.dateStyle = .short
         formatter.timeStyle = .short
         return formatter.string(from: timestamp)
     }


     func fetchChatMessages() {
         guard let currentUserEmail = Auth.auth().currentUser?.email else {
             print("User is not signed in.")
             return
         }
         
         let db = Firestore.firestore()
         db.collection("messages").document(documentURL.lastPathComponent).collection("chats").order(by: "timestamp", descending: false).addSnapshotListener { querySnapshot, error in
             guard let documents = querySnapshot?.documents else {
                 print("Error fetching chat messages: \(error?.localizedDescription ?? "Unknown error")")
                 return
             }
             
             var updatedChatMessages = [ChatMessage]()
             let dispatchGroup = DispatchGroup()
             
             for document in documents {
                 let data = document.data()
                 
                 guard let senderEmail = data["sender_email"] as? String,
                       let content = data["content"] as? String,
                       let identity = data["identity"] as? String,
                       let timestamp = data["timestamp"] as? Timestamp else {
                     continue
                 }
                 
                 dispatchGroup.enter()
                 let senderName = senderEmail != currentUserEmail ? senderEmail : "You"
                 
                 let chatMessage = ChatMessage(identity: identity, senderEmail: senderEmail, senderName: senderName, content: content, timestamp: timestamp.dateValue())
                 updatedChatMessages.append(chatMessage)
                 
                 let userRef = Firestore.firestore().collection("users").document(senderEmail)
                 
                 userRef.getDocument { document, error in
                     defer {
                         dispatchGroup.leave()
                     }
                     
                     if let error = error {
                         print("Error fetching user data: \(error.localizedDescription)")
                         return
                     }
                     
                     if let document = document, document.exists {
                         let data = document.data()
                         let senderName = data?["Name"] as? String ?? ""
                         
                         DispatchQueue.main.async {
                             if let index = updatedChatMessages.firstIndex(where: { $0.identity == identity }) {
                                 var updatedMessage = updatedChatMessages[index]
                                 updatedMessage.senderName = senderName
                                 updatedChatMessages[index] = updatedMessage
                             }
                         }
                     }
                 }
             }
             
             dispatchGroup.notify(queue: .main) {
                 self.chatMessages = updatedChatMessages
             }
         }
     }
 }

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
     
     func sendMessage() {
         guard !messageText.isEmpty else {
             return
         }
         
         guard let currentUserEmail = Auth.auth().currentUser?.email else {
             print("User is not signed in.")
             return
         }
         
         let db = Firestore.firestore()
         let commentUUID = UUID().uuidString
         let messageData: [String: Any] = [
             "identity": commentUUID,
             "sender_email": currentUserEmail,
             "content": messageText,
             "timestamp": Timestamp()
         ]
         
         db.collection("messages").document(documentURL.lastPathComponent).collection("chats").addDocument(data: messageData) { error in
             if let error = error {
                 print("Error sending message: \(error.localizedDescription)")
             } else {
                 messageText = ""
             }
         }
     }
 }

 struct ChatMessage: Identifiable {
     let id = UUID()
     let identity: String
     let senderEmail: String
     var senderName: String
     let content: String
     let timestamp: Date
 }

 struct ChatThread: Identifiable {
     let id = UUID()
     let document: Document
     var chatMessages: [ChatMessage]
 }
 */
