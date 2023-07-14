import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import PDFKit
import FirebaseStorage

struct CommentDrawerView: View {
    @Binding var commentMessages: [CommentMessage]
    let documentURL: URL
    @Binding var commentText: String?
    @Binding var isAddingComment: Bool
    @State private var currentPage: PDFPage?
    @Binding var selectedAnnotation: PDFAnnotation?
    var saveCommentAnnotation: (PDFAnnotation, URL) -> Void
    @State private var Name = ""
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedCommentIndex: Int?
    @State private var isShowingRepliesSheet = false
    
    var body: some View {
        VStack {
            Text("Comments")
                .font(.title)
                .padding()
            List {
                ForEach(commentMessages.indices, id: \.self) { commentIndex in
                    let comment = commentMessages[commentIndex]
                    Button(action: {
                        selectedCommentIndex = commentIndex
                        isShowingRepliesSheet = true
                    }) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("#\(commentIndex + 1)")
                                    .foregroundColor(.pink)
                                
                                Text(comment.senderName)
                                    .fontWeight(.bold)
                                    .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                                
                                Text(formatTimestamp(comment.timestamp))
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                
                                Spacer()
                                
                                if comment.isEditing {
                                    Button(action: {
                                        sendComment(at: commentIndex)
                                    }) {
                                        Image(systemName: "paperplane.fill")
                                            .foregroundColor(.blue)
                                    }
                                }
                                else if comment.isReplying {
                                    Button(action: {
                                        sendReply(at: commentIndex)
                                    }) {
                                        Image(systemName: "paperplane")
                                            .foregroundColor(.blue)
                                    }
                                }
                                else {
                                    HStack {
                                        Button(action: {
                                            commentMessages[commentIndex].isReplying = true
                                        }) {
                                            Image(systemName: "arrowshape.turn.up.left.fill")
                                                .foregroundColor(.blue)
                                        }
                                        
                                        Button(action: {
                                            commentMessages[commentIndex].isEditing = true
                                        }) {
                                            Image(systemName: "pencil")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                            }
                            if comment.isEditing {
                                TextField("Enter new comment", text: $commentMessages[commentIndex].content, onCommit: {
                                    sendComment(at: commentIndex)
                                })
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            } else if comment.isReplying {
                                TextField("Enter reply", text: $commentMessages[commentIndex].replyText, onCommit: {
                                    sendReply(at: commentIndex)
                                })
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            } else {
                                Text(comment.content)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.trailing)
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                            }
                            HStack {
                                Spacer()
                                // Display the total number of replies
                                Text("Replies: \(comment.replies.count)")
                                    .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                                
                            }
                        }
                        .padding(.vertical, 5)
                                            }
                }
            }
            Spacer()

            CommentInputView(documentURL: documentURL, isAddingComment: $isAddingComment, selectedAnnotation: $selectedAnnotation, currentPage: $currentPage, saveCommentAnnotation: saveCommentAnnotation)
                .onAppear {
                    if let pdfView = PDFViewWrapper.pdfView {
                        currentPage = pdfView.currentPage
                    }
                }
        }
        .sheet(isPresented: $isShowingRepliesSheet, onDismiss: {
            selectedCommentIndex = nil
        }) {
            if let selectedCommentIndex = selectedCommentIndex {
                ReplyView(commentMessages: $commentMessages, selectedCommentIndex: selectedCommentIndex)
            }
        }
        .onAppear {
            selectedCommentIndex = nil

        }
    }


    // Helper function to format the timestamp as a string
    func formatTimestamp(_ timestamp: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    func sendComment(at commentIndex: Int) {
        let comment = commentMessages[commentIndex]
        updateComment(comment) { success in
            if success {
                DispatchQueue.main.async {
                    commentMessages[commentIndex].isEditing = false
                }

            }
        }
    }

    func sendReply(at commentIndex: Int) {
        let comment = commentMessages[commentIndex]

        // Retrieve the current user's email
        guard let currentUserEmail = Auth.auth().currentUser?.email else {
            print("User is not signed in.")
            return
        }

        // Create a new reply comment
        let replyComment = CommentMessage(
            identity: UUID().uuidString,
            senderEmail: currentUserEmail, // Use the current user's email as the senderEmail
            senderName: "Your Name", // Replace with the actual sender's name
            content: comment.replyText,
            timestamp: Date(),
            annotationBounds: nil,
            isEditing: false,
            isReplying: false,
            replyText: ""
        )

        // Update the commentMessages array with the new reply
        commentMessages[commentIndex].replies.append(replyComment)

        // Store the reply in Firestore
        addReply(replyComment, to: comment, at: commentIndex)
    }


    func addReply(_ replyComment: CommentMessage, to comment: CommentMessage, at commentIndex: Int) {
        guard let currentUserEmail = Auth.auth().currentUser?.email else {
            print("User is not signed in.")
            return
        }

        let db = Firestore.firestore()

        let commentDocRef = db.collection("comments").document(documentURL.lastPathComponent).collection("comments").document(comment.identity)

        // Add the reply comment to the "replies" field of the parent comment
        commentDocRef.updateData(["replies": FieldValue.arrayUnion([replyComment.toDictionary()])]) { error in
            if let error = error {
                print("Error adding reply: \(error.localizedDescription)")
            } else {
                print("Reply added successfully")
                // Clear the reply text
                DispatchQueue.main.async {
                    commentMessages[commentIndex].replyText = ""
                }
            }
        }
    }


    func updateComment(_ comment: CommentMessage, completion: @escaping (Bool) -> Void) {
        guard let currentUserEmail = Auth.auth().currentUser?.email else {
            print("User is not signed in.")
            completion(false)
            return
        }
        
        let db = Firestore.firestore()
        
        let commentDocRef = db.collection("comments").document(documentURL.lastPathComponent).collection("comments").document(comment.identity)
        
        let updatedCommentData: [String: Any] = [
            "content": comment.content
        ]
        
        commentDocRef.updateData(updatedCommentData) { error in
            if let error = error {
                print("Error updating comment: \(error.localizedDescription)")
                completion(false)
            } else {
                print("Comment updated successfully")
                completion(true)
            }
        }
        
        // Print the updated comment data for debugging
        commentDocRef.getDocument { snapshot, error in
            if let error = error {
                print("Error fetching comment data: \(error.localizedDescription)")
            } else if let data = snapshot?.data() {
                print("Updated comment data: \(data)")
            }
        }
    }
    

    
}



struct CommentMessage: Identifiable, Equatable {
    let id = UUID()
    let identity: String
    let senderEmail: String
    var senderName: String // Modified: Made it mutable for updating the sender name
    var content: String
    let timestamp: Date
    var annotationBounds: CGRect?
    var isEditing: Bool = false
    var isReplying: Bool = false
    var replyText: String = ""
    var replies: [CommentMessage] = []

    // Convert the CommentMessage struct to a dictionary for Firestore storage
    func toDictionary() -> [String: Any] {
        return [
            "identity": identity,
            "sender_email": senderEmail,
            "sender_name": senderName,
            "content": content,
            "timestamp": timestamp,
            "replies": replies.map { $0.toDictionary() }
        ]
    }
}






/*
 import SwiftUI
 import FirebaseAuth
 import FirebaseFirestore
 import PDFKit
 import FirebaseStorage

 struct CommentDrawerView: View {
     @Binding var commentMessages: [CommentMessage]
     let documentURL: URL
     @Binding var commentText: String?
     @Binding var isAddingComment: Bool
     @State private var currentPage: PDFPage?
     @Binding var selectedAnnotation: PDFAnnotation?
     var saveCommentAnnotation: (PDFAnnotation) -> Void
     @State private var Name = ""
     @Environment(\.colorScheme) var colorScheme
     @State private var selectedCommentIndex: Int?
     @State private var isShowingRepliesSheet = false
     
     var body: some View {
         VStack {
             Text("Comments")
                 .font(.title)
                 .padding()
             List {
                 ForEach(commentMessages.indices, id: \.self) { commentIndex in
                     let comment = commentMessages[commentIndex]
                     Button(action: {
                         selectedCommentIndex = commentIndex
                         isShowingRepliesSheet = true
                     }) {
                         VStack(alignment: .leading, spacing: 5) {
                             HStack {
                                 Text("#\(commentIndex + 1)")
                                     .foregroundColor(.pink)
                                 
                                 Text(comment.senderName)
                                     .fontWeight(.bold)
                                     .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                                 
                                 Text(formatTimestamp(comment.timestamp))
                                     .font(.caption)
                                     .foregroundColor(.gray)
                                 
                                 Spacer()
                                 
                                 if comment.isEditing {
                                     Button(action: {
                                         sendComment(at: commentIndex)
                                     }) {
                                         Image(systemName: "paperplane.fill")
                                             .foregroundColor(.blue)
                                     }
                                 }
                                 else if comment.isReplying {
                                     Button(action: {
                                         sendReply(at: commentIndex)
                                     }) {
                                         Image(systemName: "paperplane")
                                             .foregroundColor(.blue)
                                     }
                                 }
                                 else {
                                     HStack {
                                         Button(action: {
                                             commentMessages[commentIndex].isReplying = true
                                         }) {
                                             Image(systemName: "arrowshape.turn.up.left.fill")
                                                 .foregroundColor(.blue)
                                         }
                                         
                                         Button(action: {
                                             commentMessages[commentIndex].isEditing = true
                                         }) {
                                             Image(systemName: "pencil")
                                                 .foregroundColor(.blue)
                                         }
                                     }
                                 }
                             }
                             if comment.isEditing {
                                 TextField("Enter new comment", text: $commentMessages[commentIndex].content, onCommit: {
                                     sendComment(at: commentIndex)
                                 })
                                 .textFieldStyle(RoundedBorderTextFieldStyle())
                             } else if comment.isReplying {
                                 TextField("Enter reply", text: $commentMessages[commentIndex].replyText, onCommit: {
                                     sendReply(at: commentIndex)
                                 })
                                 .textFieldStyle(RoundedBorderTextFieldStyle())
                             } else {
                                 Text(comment.content)
                                     .fixedSize(horizontal: false, vertical: true)
                                     .padding(.trailing)
                                     .foregroundColor(colorScheme == .dark ? .white : .black)
                             }
                             HStack {
                                 Spacer()
                                 // Display the total number of replies
                                 Text("Replies: \(comment.replies.count)")
                                     .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                                 
                             }
                         }
                         .padding(.vertical, 5)
                                             }
                 }
             }
             Spacer()

             CommentInputView(documentURL: documentURL, isAddingComment: $isAddingComment, selectedAnnotation: $selectedAnnotation, currentPage: $currentPage, saveCommentAnnotation: saveCommentAnnotation)
                 .onAppear {
                     if let pdfView = PDFViewWrapper.pdfView {
                         currentPage = pdfView.currentPage
                     }
                 }
         }
         .sheet(isPresented: $isShowingRepliesSheet, onDismiss: {
             selectedCommentIndex = nil
         }) {
             if let selectedCommentIndex = selectedCommentIndex {
                 ReplyView(commentMessages: $commentMessages, selectedCommentIndex: selectedCommentIndex)
             }
         }
         .onAppear {
             selectedCommentIndex = nil
             fetchCommentMessages()

         }
     }


     // Helper function to format the timestamp as a string
     func formatTimestamp(_ timestamp: Date) -> String {
         let formatter = DateFormatter()
         formatter.dateStyle = .short
         formatter.timeStyle = .short
         return formatter.string(from: timestamp)
     }

     func sendComment(at commentIndex: Int) {
         let comment = commentMessages[commentIndex]
         updateComment(comment) { success in
             if success {
                 DispatchQueue.main.async {
                     commentMessages[commentIndex].isEditing = false
                 }

             }
         }
     }

     func sendReply(at commentIndex: Int) {
         let comment = commentMessages[commentIndex]

         // Retrieve the current user's email
         guard let currentUserEmail = Auth.auth().currentUser?.email else {
             print("User is not signed in.")
             return
         }

         // Create a new reply comment
         let replyComment = CommentMessage(
             identity: UUID().uuidString,
             senderEmail: currentUserEmail, // Use the current user's email as the senderEmail
             senderName: "Your Name", // Replace with the actual sender's name
             content: comment.replyText,
             timestamp: Date(),
             annotationBounds: nil,
             isEditing: false,
             isReplying: false,
             replyText: ""
         )

         // Update the commentMessages array with the new reply
         commentMessages[commentIndex].replies.append(replyComment)

         // Store the reply in Firestore
         addReply(replyComment, to: comment, at: commentIndex)
     }


     func addReply(_ replyComment: CommentMessage, to comment: CommentMessage, at commentIndex: Int) {
         guard let currentUserEmail = Auth.auth().currentUser?.email else {
             print("User is not signed in.")
             return
         }

         let db = Firestore.firestore()

         let commentDocRef = db.collection("comments").document(documentURL.lastPathComponent).collection("comments").document(comment.identity)

         // Add the reply comment to the "replies" field of the parent comment
         commentDocRef.updateData(["replies": FieldValue.arrayUnion([replyComment.toDictionary()])]) { error in
             if let error = error {
                 print("Error adding reply: \(error.localizedDescription)")
             } else {
                 print("Reply added successfully")
                 // Clear the reply text
                 DispatchQueue.main.async {
                     commentMessages[commentIndex].replyText = ""
                 }
             }
         }
     }


     func updateComment(_ comment: CommentMessage, completion: @escaping (Bool) -> Void) {
         guard let currentUserEmail = Auth.auth().currentUser?.email else {
             print("User is not signed in.")
             completion(false)
             return
         }
         
         let db = Firestore.firestore()
         
         let commentDocRef = db.collection("comments").document(documentURL.lastPathComponent).collection("comments").document(comment.identity)
         
         let updatedCommentData: [String: Any] = [
             "content": comment.content
         ]
         
         commentDocRef.updateData(updatedCommentData) { error in
             if let error = error {
                 print("Error updating comment: \(error.localizedDescription)")
                 completion(false)
             } else {
                 print("Comment updated successfully")
                 completion(true)
             }
         }
         
         // Print the updated comment data for debugging
         commentDocRef.getDocument { snapshot, error in
             if let error = error {
                 print("Error fetching comment data: \(error.localizedDescription)")
             } else if let data = snapshot?.data() {
                 print("Updated comment data: \(data)")
             }
         }
     }
     
     func fetchCommentMessages() {
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
     }

     
 }



 struct CommentMessage: Identifiable, Equatable {
     let id = UUID()
     let identity: String
     let senderEmail: String
     var senderName: String // Modified: Made it mutable for updating the sender name
     var content: String
     let timestamp: Date
     var annotationBounds: CGRect?
     var isEditing: Bool = false
     var isReplying: Bool = false
     var replyText: String = ""
     var replies: [CommentMessage] = []

     // Convert the CommentMessage struct to a dictionary for Firestore storage
     func toDictionary() -> [String: Any] {
         return [
             "identity": identity,
             "sender_email": senderEmail,
             "sender_name": senderName,
             "content": content,
             "timestamp": timestamp,
             "replies": replies.map { $0.toDictionary() }
         ]
     }
 }
 */
