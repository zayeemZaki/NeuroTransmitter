//
//  CommentAnnotation.swift
//  NeuroTransmitter
//
//  Created by Zayeem Zaki on 7/3/23.
//

import Foundation
import FirebaseAuth
import PDFKit
import FirebaseFirestore

func saveCommentAnnotation(_ annotation: PDFAnnotation, documentURL: URL) {
    guard let currentUserEmail = Auth.auth().currentUser?.email else {
        print("User is not signed in.")
        return
    }
    
    guard let pdfView = PDFViewWrapper.pdfView else {
        print("PDFView is nil.")
        return
    }
    
    guard let currentPageIndex = pdfView.document?.index(for: pdfView.currentPage ?? PDFPage()) else {
        print("Current page index not found.")
        return
    }
    
    let pageNumber = currentPageIndex + 1 // Add 1 to convert from zero-based index to page number
    
    let db = Firestore.firestore()
    
    // Generate a unique ID for the comment annotation
    let commentAnnotationID = UUID().uuidString
    
    // Create a document reference for the comment annotation
    let commentAnnotationRef = db.collection("commentAnnotations").document(documentURL.lastPathComponent).collection("annotations")
    
    // Set the annotation data to be saved in Firestore
    let commentAnnotationData: [String: Any] = [
        "documentURL": documentURL.absoluteString,
        "annotationID": commentAnnotationID,
        "type": "comment",
        "senderEmail": currentUserEmail,
        "content": annotation.contents as? String ?? "",
        "bounds": [
            "x": annotation.bounds.origin.x,
            "y": annotation.bounds.origin.y,
            "width": annotation.bounds.size.width,
            "height": annotation.bounds.size.height
        ],
        "pageNumber": pageNumber
    ]
    
    // Save the comment annotation to Firestore
    commentAnnotationRef.addDocument(data: commentAnnotationData) { error in
        if let error = error {
            print("Error saving comment annotation: \(error.localizedDescription)")
        } else {
            print("Comment annotation saved successfully")
        }
    }
}



func fetchCommentAnnotations(documentURL: URL) {
    print("Fetching annotations")
    guard let currentUserEmail = Auth.auth().currentUser?.email else {
        print("User is not signed in.")
        return
    }
    
    let db = Firestore.firestore()
    let annotationsCollection = db.collection("commentAnnotations").document(documentURL.lastPathComponent).collection("annotations")
    
    annotationsCollection.getDocuments { querySnapshot, error in
        if let error = error {
            print("Error fetching annotations: \(error.localizedDescription)")
            return
        }
        
        guard let documents = querySnapshot?.documents else {
            print("No annotations found.")
            return
        }
        
        if let pdfView = PDFViewWrapper.pdfView {
            for document in documents {
                let data = document.data()
                
                guard let annotationID = data["annotationID"] as? String,
                      let bounds = data["bounds"] as? [String: CGFloat],
                      let x = bounds["x"],
                      let y = bounds["y"],
                      let width = bounds["width"],
                      let height = bounds["height"],
                      let content = data["content"] as? String,
                      let type = data["type"] as? String,
                      let pageNumber = data["pageNumber"] as? Int else {
                    print("Error parsing annotation data.")
                    continue
                }
                
                let annotationBounds = CGRect(x: x, y: y, width: width, height: height)
                
                var annotation: PDFAnnotation?
                
                if let currentPage = pdfView.document?.page(at: pageNumber - 1) {
                    
                    annotation = PDFAnnotation(bounds: annotationBounds, forType: .freeText, withProperties: nil)
                    annotation?.font = UIFont.boldSystemFont(ofSize: 20)
                    annotation?.color = .yellow.withAlphaComponent(0.2)
                    annotation?.fontColor = .red
                    annotation?.alignment = .center
                    
                    if let annotation = annotation {
                        annotation.contents = content
                        currentPage.addAnnotation(annotation)
                    }
                } else {
                    print("Invalid page number: \(pageNumber)")
                }
                // Refresh the PDF view to reflect the changes
                pdfView.setNeedsDisplay()
            }
        } else {
            print("PDFView is nil.")
        }


    }
    
}
