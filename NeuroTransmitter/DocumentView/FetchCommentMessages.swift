//
//  FetchCommentMessages.swift
//  NeuroTransmitter
//
//  Created by Zayeem Zaki on 7/5/23.
//
/*
import FirebaseAuth
import FirebaseFirestore

func fetchCommentMessages(documentURL: URL) {
    guard let currentUserEmail = Auth.auth().currentUser?.email else {
        print("User is not signed in.")
        return
    }
    
    let db = Firestore.firestore()
    let commentsCollection = db.collection("comments").document(documentURL.lastPathComponent).collection("comments")
    
    commentsCollection.order(by: "timestamp", descending: false).addSnapshotListener { querySnapshot, error in
        if let error = error {
            print("Error fetching comments: \(error.localizedDescription)")
            return
        }
        
        guard let documents = querySnapshot?.documents else {
            print("No comments found.")
            return
        }
        
        var fetchedCommentMessages: [CommentMessage] = [] // Create a temporary array to store fetched comments
        
        let dispatchGroup = DispatchGroup() // Create a dispatch group for handling asynchronous tasks
        
        for document in documents {
            let data = document.data()
            
            guard let identity = data["identity"] as? String,
                  let senderEmail = data["sender_email"] as? String,
                  let content = data["content"] as? String,
                  let timestamp = data["timestamp"] as? Timestamp,
                  let repliesData = data["replies"] as? [[String: Any]] else {
                continue
            }
            
            let userRef = Firestore.firestore().collection("users").document(senderEmail)
            
            dispatchGroup.enter() // Enter the dispatch group
            
            userRef.getDocument { document, error in
                if let error = error {
                    print("Error fetching user data: \(error.localizedDescription)")
                    dispatchGroup.leave() // Leave the dispatch group in case of an error
                    return
                }
                
                if let document = document, document.exists {
                    let data = document.data()
                    let senderName = data?["Name"] as? String ?? ""
                    
                    DispatchQueue.main.async {
                        if let index = fetchedCommentMessages.firstIndex(where: { $0.identity == identity }) {
                            fetchedCommentMessages[index].senderName = senderName
                        }
                    }
                }
                
                dispatchGroup.leave() // Leave the dispatch group after fetching user data
            }
            
            let senderName = senderEmail != currentUserEmail ? senderEmail : "You"
            
            var commentMessage = CommentMessage(identity: identity, senderEmail: senderEmail, senderName: senderName, content: content, timestamp: timestamp.dateValue())
            
            // Fetch and populate the replies for the comment
            let repliesDispatchGroup = DispatchGroup()
            
            for replyData in repliesData {
                guard let replyIdentity = replyData["identity"] as? String,
                      let replySenderEmail = replyData["sender_email"] as? String,
                      let replyContent = replyData["content"] as? String,
                      let replyTimestamp = replyData["timestamp"] as? Timestamp else {
                    continue
                }
                
                let replySenderName = replySenderEmail != currentUserEmail ? replySenderEmail : "You"
                
                let replyMessage = CommentMessage(identity: replyIdentity, senderEmail: replySenderEmail, senderName: replySenderName, content: replyContent, timestamp: replyTimestamp.dateValue())
                
                dispatchGroup.enter() // Enter the dispatch group for fetching the sender's name of each reply
                
                let replyUserRef = Firestore.firestore().collection("users").document(replySenderEmail)
                replyUserRef.getDocument { document, error in
                    if let error = error {
                        print("Error fetching user data for reply: \(error.localizedDescription)")
                    } else if let document = document, document.exists {
                        let data = document.data()
                        let replySenderName = data?["Name"] as? String ?? ""
                        
                        DispatchQueue.main.async {
                            if let commentIndex = fetchedCommentMessages.firstIndex(where: { $0.identity == identity }),
                               let replyIndex = fetchedCommentMessages[commentIndex].replies.firstIndex(where: { $0.identity == replyIdentity }) {
                                fetchedCommentMessages[commentIndex].replies[replyIndex].senderName = replySenderName
                            }
                        }
                    }
                    
                    dispatchGroup.leave() // Leave the dispatch group after fetching user data for reply
                }
                
                commentMessage.replies.append(replyMessage)
            }
            
            fetchedCommentMessages.append(commentMessage) // Add the comment to the temporary array
        }
        
        dispatchGroup.notify(queue: .main) {
            // All asynchronous tasks have completed
            self.commentMessages = fetchedCommentMessages // Assign the fetched comments to the main commentMessages array
        }
    }
}*/


