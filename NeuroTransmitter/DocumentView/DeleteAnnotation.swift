//
//  DeleteAnnotation.swift
//  NeuroTransmitter
//
//  Created by Zayeem Zaki on 7/4/23.
//
/*
import FirebaseFirestore
import PDFKit


func deleteAnnotation(selectedOnDocumentAnnotation: CustomPDFAnnotation?, documentURL: URL, showDeleteButton: inout Bool) {
    guard let pdfView = PDFViewWrapper.pdfView,
          let selectedOnDocumentAnnotation = selectedOnDocumentAnnotation,
          let annotationID = selectedOnDocumentAnnotation.annotationID else {
        return
    }
    
    // Remove the annotation from the PDF view
    if let currentPage = pdfView.currentPage {
        currentPage.removeAnnotation(selectedOnDocumentAnnotation)
    }
    
    // Remove the annotation from Firestore
    let db = Firestore.firestore()
    let annotationsCollection = db.collection("onDocumentComments").document(documentURL.lastPathComponent).collection("annotations")
    
    annotationsCollection.document(annotationID).delete { error in
        if let error = error {
            // Handle the error appropriately
            print("Error deleting annotation from Firestore: \(error)")
        } else {
            // Deletion successful
            print("Annotation deleted from Firestore")
            
            // Refresh the PDF view to reflect the changes
            if let currentPage = pdfView.currentPage {
                pdfView.go(to: PDFDestination(page: currentPage, at: .zero))
            }
        }
    }
    
    let highlightAnnotationsCollection = db.collection("highlightAnnotations").document(documentURL.lastPathComponent).collection("annotations")
    
    highlightAnnotationsCollection.document(annotationID).delete { error in
        if let error = error {
            // Handle the error appropriately
            print("Error deleting annotation from Firestore: \(error)")
        } else {
            // Deletion successful
            print("Annotation deleted from Firestore")
            
            // Refresh the PDF view to reflect the changes
            if let currentPage = pdfView.currentPage {
                pdfView.go(to: PDFDestination(page: currentPage, at: .zero))
            }
        }
    }

    
    showDeleteButton = false
    //  deselectAnnotation()
}

*/
