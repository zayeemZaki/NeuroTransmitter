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
    @State var selectedCommentIndex: Int?
    @State private var isShowingRepliesSheet = false
    @Binding var showCommentDrawer: Bool
    
    var body: some View {
        if selectedCommentIndex == nil {
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
            .onAppear {
                selectedCommentIndex = nil
            }
        }
        else if let selectedCommentIndex = selectedCommentIndex {
            ReplyView(commentMessages: $commentMessages, selectedCommentIndex: selectedCommentIndex, documentURL: documentURL, commentText: $commentText, isAddingComment: $isAddingComment, selectedAnnotation: $selectedAnnotation, showCommentDrawer: $showCommentDrawer)
            
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
        
        guard  let currentUserEmail = Auth.auth().currentUser?.email else {
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




