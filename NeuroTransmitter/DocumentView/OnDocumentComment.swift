//
//  OnDocumentComment.swift
//  NeuroTransmitter
//
//  Created by Zayeem Zaki on 7/3/23.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import SwiftUI


func saveOnDocumentComment(_ annotation: CustomPDFAnnotation, documentURL: URL, isBold: Bool, isItalic: Bool, fontSize: CGFloat, fontColor: Color, location: CGPoint) {
    guard let currentUserEmail = Auth.auth().currentUser?.email else {
        print("User is not signed in.")
        return
    }
    
   /* guard let pdfView = PDFViewWrapper.pdfView,
          let currentPage = pdfView.currentPage,
          let pageIndex = pdfView.document?.index(for: currentPage) else {
        print("Failed to get current page or index.")
        return
    }*/
    
    let pdfView = PDFViewWrapper.pdfView
    let currentPage = pdfView?.currentPage
    let tapLocation = pdfView?.convert(location, to: currentPage!)
    let pageIndex = PDFViewWrapper.getPageIndexForTouchedLocation(tapLocation!)
    
    let db = Firestore.firestore()
    
    // Generate a unique ID for the free text annotation
    let annotationID = UUID().uuidString
    
    // Create a document reference for the free text annotation in the desired collection
    let annotationRef = db.collection("onDocumentComments").document(documentURL.lastPathComponent).collection("annotations").document(annotationID)
    
    // Set the annotation data to be saved in Firestore
    let annotationData: [String: Any] = [
        "documentURL": documentURL.absoluteString,
        "annotationID": annotationID,
        "type": "freeText",
        "senderEmail": currentUserEmail,
        "content": annotation.contents as? String ?? "",
        "bounds": [
            "x": annotation.bounds.origin.x,
            "y": annotation.bounds.origin.y,
            "width": annotation.bounds.size.width,
            "height": annotation.bounds.size.height
        ],
        "pageNumber": pageIndex , // Add the page number (incremented by 1 since pages are 0-indexed)
        "fontColor": fontColor.description, // Save the font color as a string
        "fontSize": fontSize, // Save the font size
        "isBold": isBold, // Save whether the text is bold
        "isItalic": isItalic // Save whether the text is italic
    ]
    
    // Save the free text annotation to Firestore
    annotationRef.setData(annotationData) { error in
        if let error = error {
            print("Error saving free text annotation: \(error.localizedDescription)")
        } else {
            print("Free text annotation saved successfully")
        }
    }
}



func fetchOnDocumentComment(documentURL: URL) {
    print("Fetching on document comment")
    
    guard let currentUserEmail = Auth.auth().currentUser?.email else {
        print("User is not signed in.")
        return
    }
    
    let db = Firestore.firestore()
    let annotationsCollection = db.collection("onDocumentComments").document(documentURL.lastPathComponent).collection("annotations")
    
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
                      let isBold = data["isBold"] as? Bool,
                      let fontSize = data["fontSize"] as? Int,
                      let fontColor = data["fontColor"] as? String,
                      let isItalic = data["isItalic"] as? Bool,
                      let pageNumber = data["pageNumber"] as? Int else {
                    print("Error parsing annotation data.")
                    continue
                }
                
                let annotationBounds = CGRect(x: x, y: y, width: width, height: height)
                let annotation = CustomPDFAnnotation(bounds: annotationBounds, forType: .freeText, withProperties: nil)
                annotation.color = .white.withAlphaComponent(0.0)
                
                
                var traits = getFontSymbolicTraits(isBold: isBold, isItalic: isItalic)
                if isBold {
                    traits.insert(.traitBold)
                }
                if isItalic {
                    traits.insert(.traitItalic)
                }
                
                let resizedFontDescriptor = annotation.font?.fontDescriptor.withSymbolicTraits(traits)
                let resizedFont = UIFont(descriptor: resizedFontDescriptor ?? UIFontDescriptor(), size: CGFloat(fontSize))
                
                annotation.font = resizedFont

                let colorMap: [String: UIColor] = [
                    "red": .red,
                    "green": .green,
                    "black": .black,
                    "blue": .blue
                    // Add more color mappings as needed
                ]
                
                if let color = colorMap[fontColor] {
                    annotation.fontColor = color
                } else {
                    print("Invalid color string: \(fontColor)")
                    annotation.fontColor = .red
                }
                
                if let currentPage = pdfView.document?.page(at: pageNumber ) {
                    annotation.contents = content
                    annotation.annotationID = annotationID // Store the annotation ID
                    currentPage.addAnnotation(annotation)
                } else {
                    print("Invalid page number: \(pageNumber)")
                }
            }
        } else {
            print("PDFView is nil.")
        }
    }
}

public func getFontSymbolicTraits(isBold: Bool, isItalic: Bool) -> UIFontDescriptor.SymbolicTraits {
    var traits = UIFontDescriptor.SymbolicTraits()
    if isBold {
        traits.insert(.traitBold)
    }
    if isItalic {
        traits.insert(.traitItalic)
    }
    return traits
}



/*
 import Foundation
 import FirebaseAuth
 import FirebaseFirestore
 import SwiftUI


 func saveOnDocumentComment(_ annotation: CustomPDFAnnotation, documentURL: URL, isBold: Bool, isItalic: Bool, fontSize: CGFloat, fontColor: Color, location: CGPoint) {
     guard let currentUserEmail = Auth.auth().currentUser?.email else {
         print("User is not signed in.")
         return
     }
     
    /* guard let pdfView = PDFViewWrapper.pdfView,
           let currentPage = pdfView.currentPage,
           let pageIndex = pdfView.document?.index(for: currentPage) else {
         print("Failed to get current page or index.")
         return
     }*/
     
     let pdfView = PDFViewWrapper.pdfView
     let currentPage = pdfView?.currentPage
     let tapLocation = pdfView?.convert(location, to: currentPage!)
     let pageIndex = PDFViewWrapper.getPageIndexForTouchedLocation(tapLocation!)
     
     let db = Firestore.firestore()
     
     // Generate a unique ID for the free text annotation
     let annotationID = UUID().uuidString
     
     // Create a document reference for the free text annotation in the desired collection
     let annotationRef = db.collection("onDocumentComments").document(documentURL.lastPathComponent).collection("annotations").document(annotationID)
     
     // Set the annotation data to be saved in Firestore
     let annotationData: [String: Any] = [
         "documentURL": documentURL.absoluteString,
         "annotationID": annotationID,
         "type": "freeText",
         "senderEmail": currentUserEmail,
         "content": annotation.contents as? String ?? "",
         "bounds": [
             "x": annotation.bounds.origin.x,
             "y": annotation.bounds.origin.y,
             "width": annotation.bounds.size.width,
             "height": annotation.bounds.size.height
         ],
         "pageNumber": pageIndex , // Add the page number (incremented by 1 since pages are 0-indexed)
         "fontColor": fontColor.description, // Save the font color as a string
         "fontSize": fontSize, // Save the font size
         "isBold": isBold, // Save whether the text is bold
         "isItalic": isItalic // Save whether the text is italic
     ]
     
     // Save the free text annotation to Firestore
     annotationRef.setData(annotationData) { error in
         if let error = error {
             print("Error saving free text annotation: \(error.localizedDescription)")
         } else {
             print("Free text annotation saved successfully")
         }
     }
 }



 func fetchOnDocumentComment(documentURL: URL) {
     print("Fetching on document comment")
     
     guard let currentUserEmail = Auth.auth().currentUser?.email else {
         print("User is not signed in.")
         return
     }
     
     let db = Firestore.firestore()
     let annotationsCollection = db.collection("onDocumentComments").document(documentURL.lastPathComponent).collection("annotations")
     
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
                       let isBold = data["isBold"] as? Bool,
                       let fontSize = data["fontSize"] as? Int,
                       let fontColor = data["fontColor"] as? String,
                       let isItalic = data["isItalic"] as? Bool,
                       let pageNumber = data["pageNumber"] as? Int else {
                     print("Error parsing annotation data.")
                     continue
                 }
                 
                 let annotationBounds = CGRect(x: x, y: y, width: width, height: height)
                 let annotation = CustomPDFAnnotation(bounds: annotationBounds, forType: .freeText, withProperties: nil)
                 annotation.color = .white.withAlphaComponent(0.0)
                 
                 
                 var traits = getFontSymbolicTraits(isBold: isBold, isItalic: isItalic)
                 if isBold {
                     traits.insert(.traitBold)
                 }
                 if isItalic {
                     traits.insert(.traitItalic)
                 }
                 
                 let resizedFontDescriptor = annotation.font?.fontDescriptor.withSymbolicTraits(traits)
                 let resizedFont = UIFont(descriptor: resizedFontDescriptor ?? UIFontDescriptor(), size: CGFloat(fontSize))
                 
                 annotation.font = resizedFont

                 let colorMap: [String: UIColor] = [
                     "red": .red,
                     "green": .green,
                     "black": .black,
                     "blue": .blue
                     // Add more color mappings as needed
                 ]
                 
                 if let color = colorMap[fontColor] {
                     annotation.fontColor = color
                 } else {
                     print("Invalid color string: \(fontColor)")
                     annotation.fontColor = .red
                 }
                 
                 if let currentPage = pdfView.document?.page(at: pageNumber ) {
                     annotation.contents = content
                     annotation.annotationID = annotationID // Store the annotation ID
                     currentPage.addAnnotation(annotation)
                 } else {
                     print("Invalid page number: \(pageNumber)")
                 }
             }
         } else {
             print("PDFView is nil.")
         }
     }
 }

 public func getFontSymbolicTraits(isBold: Bool, isItalic: Bool) -> UIFontDescriptor.SymbolicTraits {
     var traits = UIFontDescriptor.SymbolicTraits()
     if isBold {
         traits.insert(.traitBold)
     }
     if isItalic {
         traits.insert(.traitItalic)
     }
     return traits
 }
 */
