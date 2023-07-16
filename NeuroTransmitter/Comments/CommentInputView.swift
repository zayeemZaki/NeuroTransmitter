//
//  CommentInputView.swift
//  NeuroTransmitter
//
//  Created by Zayeem Zaki on 6/24/23.
//


import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import PDFKit
import FirebaseStorage

struct CommentInputView: View {
    let documentURL: URL
    @State private var commentText: String = ""
    @Binding var isAddingComment: Bool
    @Binding var selectedAnnotation: PDFAnnotation?
    @Binding var currentPage: PDFPage?
    var saveCommentAnnotation: (PDFAnnotation, URL) -> Void
    
    var body: some View {
        VStack {
            Divider()
            if isAddingComment {
                HStack {
                    TextField("Add a comment...", text: $commentText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button(action: addComment) {
                        Image(systemName: "paperplane")
                    }
                    .padding(.leading)
                }
                .padding()
            }
        }
    }
    
    func addComment() {
        guard let currentUserEmail = Auth.auth().currentUser?.email else {
            print("User is not signed in.")
            return
        }
        
        guard let currentPage = currentPage else {
            print("Current page is not set.")
            return
        }
        
        guard let selectedAnnotation = selectedAnnotation else {
            print("No annotation is selected.")
            return
        }
        
        let annotationBounds = selectedAnnotation.bounds
        
        let comment = CommentMessage(identity: UUID().uuidString,
                                     senderEmail: currentUserEmail,
                                     senderName: "Your Name", // Replace with the actual sender's name
                                     content: commentText,
                                     timestamp: Date(),
                                     annotationBounds: annotationBounds,
                                     isEditing: false,
                                     isReplying: false,
                                     replyText: "")
        
        saveCommentAnnotation(selectedAnnotation, documentURL)
        
        // Add the comment annotation to the PDFView
        PDFViewWrapper.addAnnotationToCurrentPage(annotation: selectedAnnotation)
        
        commentText = ""
        isAddingComment = false
        
        storeComment(comment)
    }
    
    func storeComment(_ comment: CommentMessage) {
        let db = Firestore.firestore()
        
        let commentDocRef = db.collection("comments").document(documentURL.lastPathComponent).collection("comments").document(comment.identity)
        
        commentDocRef.setData(comment.toDictionary()) { error in
            if let error = error {
                print("Error adding comment: \(error.localizedDescription)")
            } else {
                print("Comment added successfully")
            }
        }
    }
}

