//
//  ChatInputView.swift
//  NeuroTransmitter
//
//  Created by Zayeem Zaki on 6/24/23.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

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



/*
 import SwiftUI
 import FirebaseAuth
 import FirebaseFirestore

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

 */
