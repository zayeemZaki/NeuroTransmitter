
import Foundation
import FirebaseAuth
import FirebaseFirestore
import PDFKit

func saveHighlightAnnotation(_ annotation: HighlightPDFAnnotation, documentURL: URL, pageIndex: Int) {
    guard let currentUserEmail = Auth.auth().currentUser?.email else {
        print("User is not signed in.")
        return
    }

    let db = Firestore.firestore()

    let annotationID = UUID().uuidString
    let annotationRef = db.collection("highlightAnnotations")
                           .document(documentURL.lastPathComponent)
                           .collection("annotations")
                           .document(annotationID)

    let bounds = annotation.bounds

    // Default color (white) in case the annotation color is nil or doesn't have RGB components
    var colorData: [String: CGFloat] = ["red": 1, "green": 1, "blue": 1, "alpha": 1]

    // Extract RGB components if available
    if let colorComponents = annotation.color.cgColor.components, colorComponents.count >= 3 {
        colorData["red"] = colorComponents[0]
        colorData["green"] = colorComponents[1]
        colorData["blue"] = colorComponents[2]
        colorData["alpha"] = annotation.color.cgColor.alpha ?? 1
    }

    let annotationData: [String: Any] = [
        "documentURL": documentURL.absoluteString,
        "pageIndex": pageIndex,
        "bounds": [
            "x": bounds.origin.x,
            "y": bounds.origin.y,
            "width": bounds.size.width,
            "height": bounds.size.height
        ],
        "color": colorData,
        "senderEmail": currentUserEmail,
        "annotationID": annotationID
    ]

    annotationRef.setData(annotationData) { error in
        if let error = error {
            print("Error saving highlight annotation: \(error.localizedDescription)")
        } else {
            print("Highlight annotation saved successfully")
        }
    }
}



func fetchHighlightAnnotations(documentURL: URL) {
    let db = Firestore.firestore()
    let annotationsCollection = db.collection("highlightAnnotations")
                                   .document(documentURL.lastPathComponent)
                                   .collection("annotations")

    annotationsCollection.getDocuments { querySnapshot, error in
        if let error = error {
            print("Error fetching annotations: \(error.localizedDescription)")
            return
        }

        var annotations = [HighlightPDFAnnotation]()
        print("Fetching highlight Annotations")
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
                let pageIndex = data["pageIndex"] as? Int,
                let senderEmail = data["senderEmail"] as? String else {
                    print("Error parsing annotation data.")
                    continue
                }

                let annotationBounds = CGRect(x: x, y: y, width: width, height: height)
                let annotation = HighlightPDFAnnotation(bounds: annotationBounds, forType: .highlight, withProperties: nil)

                // Set any additional properties of the annotation as needed
                annotation.annotationID = annotationID
    
                if let currentPage = pdfView.document?.page(at: pageIndex) {
                    currentPage.addAnnotation(annotation)
                } 
                else {
                    print("Invalid page index: \(pageIndex)")
                }
            }
        }
        else {
            print("PDFView is nil.")
        }
    }
}









/*
 import Foundation
 import FirebaseAuth
 import FirebaseFirestore
 import PDFKit

 func saveHighlightAnnotation(_ annotation: PDFAnnotation, documentURL: URL, pageIndex: Int) {
     guard let currentUserEmail = Auth.auth().currentUser?.email else {
         print("User is not signed in.")
         return
     }

     let db = Firestore.firestore()

     let annotationID = UUID().uuidString
     let annotationRef = db.collection("highlightAnnotations")
                            .document(documentURL.lastPathComponent)
                            .collection("annotations")
                            .document(annotationID)

     let bounds = annotation.bounds

     // Default color (white) in case the annotation color is nil or doesn't have RGB components
     var colorData: [String: CGFloat] = ["red": 1, "green": 1, "blue": 1, "alpha": 1]

     // Extract RGB components if available
     if let colorComponents = annotation.color.cgColor.components, colorComponents.count >= 3 {
         colorData["red"] = colorComponents[0]
         colorData["green"] = colorComponents[1]
         colorData["blue"] = colorComponents[2]
         colorData["alpha"] = annotation.color.cgColor.alpha ?? 1
     }

     let annotationData: [String: Any] = [
         "documentURL": documentURL.absoluteString,
         "pageIndex": pageIndex,
         "bounds": [
             "x": bounds.origin.x,
             "y": bounds.origin.y,
             "width": bounds.size.width,
             "height": bounds.size.height
         ],
         "color": colorData,
         "senderEmail": currentUserEmail,
         "annotationID": annotationID
     ]

     annotationRef.setData(annotationData) { error in
         if let error = error {
             print("Error saving highlight annotation: \(error.localizedDescription)")
         } else {
             print("Highlight annotation saved successfully")
         }
     }
 }



 func fetchHighlightAnnotations(documentURL: URL) {
     let db = Firestore.firestore()
     let annotationsCollection = db.collection("highlightAnnotations")
                                    .document(documentURL.lastPathComponent)
                                    .collection("annotations")

     annotationsCollection.getDocuments { querySnapshot, error in
         if let error = error {
             print("Error fetching annotations: \(error.localizedDescription)")
             return
         }

         var annotations = [PDFAnnotation]()
         print("Fetching highlight Annotations")
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
                 let pageIndex = data["pageIndex"] as? Int,
                 let senderEmail = data["senderEmail"] as? String else {
                     print("Error parsing annotation data.")
                     continue
                 }

                 let annotationBounds = CGRect(x: x, y: y, width: width, height: height)
                 let annotation = CustomPDFAnnotation(bounds: annotationBounds, forType: .highlight, withProperties: nil)

                 // Set any additional properties of the annotation as needed
                 annotation.annotationID = annotationID
     
                 if let currentPage = pdfView.document?.page(at: pageIndex) {
                     currentPage.addAnnotation(annotation)
                 }
                 else {
                     print("Invalid page index: \(pageIndex)")
                 }
             }
         }
         else {
             print("PDFView is nil.")
         }
     }
 }
 */



//
//
//func saveHighlightAnnotation(_ annotation: CustomPDFAnnotation, documentURL: URL, location: CGPoint) {
//    guard let currentUserEmail = Auth.auth().currentUser?.email else {
//        print("User is not signed in.")
//        return
//    }
//    
//    guard let pdfView = PDFViewWrapper.pdfView,
//          let currentPage = pdfView.currentPage,
//          let pageIndex = pdfView.document?.index(for: currentPage) else {
//        print("Failed to get current page or index.")
//        return
//    }
//    
//    
//    let db = Firestore.firestore()
//    
//    // Generate a unique ID for the free text annotation
//    let annotationID = UUID().uuidString
//    
//    let annotationRef = db.collection("highlightAnnotations").document(documentURL.lastPathComponent).collection("annotations").document(annotationID)
//    
//    
//    let bounds = annotation.bounds
//    let boundsData: [String: Any] = [
//        "x": bounds.origin.x,
//        "y": bounds.origin.y,
//        "width": bounds.size.width,
//        "height": bounds.size.height
//    ]
//    
//    let annotationData: [String: Any] = [
//        "documentURL": documentURL.absoluteString,
//        "pageIndex": pageIndex,
//        "bounds": boundsData,
//        "senderEmail": currentUserEmail,
//        "annotationID": annotationID,
//        
//    ]
//    
//    // Save the free text annotation to Firestore
//    annotationRef.setData(annotationData) { error in
//        if let error = error {
//            print("Error saving free text annotation: \(error.localizedDescription)")
//        } else {
//            print("Free text annotation saved successfully")
//        }
//    }
//}
//
//
//func fetchHighlightAnnotations(documentURL: URL) {
//    print("Fetching highlight annotations")
//    
//    guard let currentUserEmail = Auth.auth().currentUser?.email else {
//        print("User is not signed in.")
//        return
//    }
//    
//    let db = Firestore.firestore()
//    let annotationsCollection = db.collection("highlightAnnotations").document(documentURL.lastPathComponent).collection("annotations")
//    
//    annotationsCollection.getDocuments { querySnapshot, error in
//        if let error = error {
//            print("Error fetching annotations: \(error.localizedDescription)")
//            return
//        }
//        
//        guard let documents = querySnapshot?.documents else {
//            print("No annotations found.")
//            return
//        }
//        
//        if let pdfView = PDFViewWrapper.pdfView {
//            for document in documents {
//                let data = document.data()
//                
//                guard let annotationID = data["annotationID"] as? String,
//                      let bounds = data["bounds"] as? [String: CGFloat],
//                      let x = bounds["x"],
//                      let y = bounds["y"],
//                      let width = bounds["width"],
//                      let height = bounds["height"],
//                      let pageIndex = data["pageIndex"] as? Int,
//                      let senderEmail = data["senderEmail"] as? String else {
//                    print("Error parsing annotation data.")
//                    continue
//                }
//                
//                let annotationBounds = CGRect(x: x, y: y, width: width, height: height)
//                let annotation = CustomPDFAnnotation(bounds: annotationBounds, forType: .highlight, withProperties: nil)
//                
//                // Set any additional properties of the annotation as needed
//                annotation.annotationID = annotationID
//                
//                if let currentPage = pdfView.document?.page(at: pageIndex) {
//                    currentPage.addAnnotation(annotation)
//                } else {
//                    print("Invalid page index: \(pageIndex)")
//                }
//            }
//        } else {
//            print("PDFView is nil.")
//        }
//    }
//}
//

