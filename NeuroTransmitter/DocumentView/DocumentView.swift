import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import PDFKit
import UIKit
import Firebase
import AVFoundation

class CustomPDFAnnotation: PDFAnnotation {
    var annotationID: String?
    
    
}

class PopUpAnnotation: PDFAnnotation {
    var annotationID: String?
}

class HighlightPDFAnnotation: PDFAnnotation {
    var annotationID: String?
}

struct PageAnnotation {
    let annotation: PDFAnnotation
    let pageIndex: Int
}


public struct DocumentView: View {
    let documentURL: URL
    @State private var showChatDrawer = false
    @State private var showCommentDrawer = false
    @State private var commentMessages: [CommentMessage] = [] // Store comment messages
    @State private var commentText: String?
    @State private var isAddingComment = false // Track if a comment is being added
    @State private var selectedAnnotationType: PDFAnnotationSubtype? // Track the selected annotation type
    @State private var chatMessages: [ChatMessage] = [] // Store chat messages
    @State private var commentAnnotations: [CommentAnnotation] = [] // Store comment annotations
    @State private var selectedAnnotation: PDFAnnotation? // Store the selected annotation
    @State private var selectedOnDocumentAnnotation: CustomPDFAnnotation? // Store the selected annotation on the document ---
    @State private var selectedHighlightAnnotation: HighlightPDFAnnotation? // Store the selected annotation on the document
    @State private var isTyping = false // Track if the user is typing
    @State private var pdfView: PDFView? // Store the PDF view
    @State private var fontColor: Color = .black // Store the font color
    @State private var showDeleteButton: Bool = false // Track whether to show the delete button
    @State private var isBold: Bool = false // Track if the text is bold
    @State private var isItalic: Bool = false // Track if the text is italic
    @State private var fontSize: CGFloat = 16 // Store the selected font size
    let availableFontSizes: [CGFloat] = [8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32]
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedColor: UIColor = .yellow // Default color
    // Gesture-related states for highlighting annotations
    @State private var firstTouchLocation: CGPoint?
    @State private var secondTouchLocation: CGPoint?
    @State private var isHighlighting: Bool = false
    @State private var highlightAnnotations: [PDFAnnotation] = []
    @State private var lastSynthesisPosition: Int = 0 // Track last synthesis position here

    
    @State private var popUpAnnotationContent: String = ""
    @State private var selectedPopUpAnnotation: PopUpAnnotation?
    @State private var showPopUp: Bool = false // Track whether to show the delete button
    @State private var isPopUp = false // Track if the user is typing

    
    public var body: some View {
        VStack {
            PDFViewWrapper(url: documentURL, handleTapGesture: handleTapGesture, isHighlighting: $isHighlighting, selectedHighlightAnnotation: $selectedHighlightAnnotation, selectedColor: $selectedColor )
                .onTapGesture {
                    
                }
        }
        .overlay(
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        showChatDrawer.toggle()
                    }) {
                        Image(systemName: "message.fill")
                            .resizable()
                            .frame(width: 20, height: 20)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                    .padding(.trailing)
                }
            }
                .padding()
        )
        
        .navigationBarItems(
            trailing:
                HStack {
                    AnnotationToolbar(selectedAnnotationType: $selectedAnnotationType, isAddingComment: $isAddingComment, commentText: $commentText, showCommentDrawer: $showCommentDrawer, isTyping: $isTyping, fontColor: $fontColor, selectedColor: $selectedColor, showDeleteButton: $showDeleteButton, isBold: $isBold, isItalic: $isItalic, fontSize: $fontSize,                                 
                        deleteAction: {
                            self.deleteAction()
                        },
                                      availableFontSizes: availableFontSizes, isHighlighting: $isHighlighting, lastSynthesisPosition: $lastSynthesisPosition, documentURL: documentURL, isPopUp: $isPopUp)
                   // Spacer()
                }
        )
        .sheet(isPresented: $showCommentDrawer) {
            CommentDrawerView(commentMessages: $commentMessages, documentURL: documentURL, commentText: $commentText, isAddingComment: $isAddingComment, selectedAnnotation: $selectedAnnotation, saveCommentAnnotation: saveCommentAnnotation, showCommentDrawer: $showCommentDrawer)
        }
        .sheet(isPresented: $showChatDrawer) {
            ChatDrawerView(chatMessages: $chatMessages, documentURL: documentURL, commentText: $commentText)
        }
        .sheet(isPresented: $showPopUp) {
            PopUpView(popUpAnnotationContent: $popUpAnnotationContent, onClose: {
                showPopUp = false
                isPopUp = false
                popUpAnnotationContent = "" // Clear the content for next use
            }, documentURL: documentURL, selectedPopUpAnnotation: $selectedPopUpAnnotation, isPopUp: $isPopUp)
        }
        .onAppear {
            fetchOnDocumentComment(documentURL: documentURL)
            fetchCommentAnnotations(documentURL: documentURL)
            fetchHighlightAnnotations(documentURL: documentURL)
            fetchPopUpAnnotations(documentURL: documentURL)
        }
    }
    
    private func deleteAction() {
        // Assuming you can differentiate annotations based on their subtype or a custom property
        if let customAnnotation = selectedOnDocumentAnnotation {
            deleteOnDocumentAnnotation()
        }
        else if let anotherTypeOfAnnotation = selectedHighlightAnnotation{
            deleteHighlightAnnotation()
        }
        else {
            print("Unhandled annotation type")
            print(selectedAnnotation)
        }
        
    }
    
    func handleTapGesture(location: CGPoint) {
        guard let pdfView = PDFViewWrapper.pdfView,
              let currentPage = pdfView.currentPage else {
            print("PDF view or current page not available")
            return
        }

        let tapLocation = pdfView.convert(location, to: currentPage)

        if let tappedAnnotation = currentPage.annotation(at: tapLocation) {
            if let customAnnotation = tappedAnnotation as? CustomPDFAnnotation {
                selectedOnDocumentAnnotation = customAnnotation
                showDeleteButton = true
            } 
            else if let highlightAnnotation = tappedAnnotation as? HighlightPDFAnnotation {
                selectedHighlightAnnotation = highlightAnnotation
                showDeleteButton = true
            } 
            else if let popUpAnnotation = tappedAnnotation as? PopUpAnnotation {
                selectedPopUpAnnotation = popUpAnnotation
                print(selectedPopUpAnnotation?.annotationID)
                showPopUp = true
            } 
            else {
                selectedAnnotation = tappedAnnotation
                showCommentDrawer = true
            }
        } 
        else {
            showDeleteButton = false
            if isAddingComment {
                let textAnnotation = PDFAnnotation(bounds: CGRect(x: tapLocation.x, y: tapLocation.y, width: 30, height: 30), forType: .freeText, withProperties: nil)
                textAnnotation.contents = "\(commentMessages.count + 1)"
                textAnnotation.font = UIFont.boldSystemFont(ofSize: 20)
                textAnnotation.color = .yellow.withAlphaComponent(0.2)
                textAnnotation.fontColor = .red
                textAnnotation.alignment = .center
                currentPage.addAnnotation(textAnnotation)
                selectedAnnotation = textAnnotation
                showCommentDrawer = true
            } else if isTyping {
                firstTouchLocation = location
                createOnDocumentAnnotation()
            } else if isPopUp {
                firstTouchLocation = location
                createTextAnnotationAsPopup()
            }
        }
    }




    func createTextAnnotationAsPopup() {
        guard let firstTouchLocation = firstTouchLocation,
              let pdfView = PDFViewWrapper.pdfView,
              let tappedPage = pdfView.page(for: firstTouchLocation, nearest: true) else {
            print("Failed to get PDF view or page.")
            return
        }
        
        let convertedFirstLocation = pdfView.convert(firstTouchLocation, to: tappedPage)
        let bounds = CGRect(x: convertedFirstLocation.x, y: convertedFirstLocation.y, width: 30, height: 30)
        let textAnnotation = PopUpAnnotation(bounds: bounds, forType: .text, withProperties: nil)
        textAnnotation.color = .red.withAlphaComponent(0.2)
        
        let annotationID = UUID().uuidString
//        selectedOnDocumentAnnotation!.annotationID = annotationID
        textAnnotation.annotationID = annotationID // Set immediately

        tappedPage.addAnnotation(textAnnotation)
        print("Added text annotation at \(bounds)")
        selectedPopUpAnnotation = textAnnotation
        print("Selected Annotation: ", selectedPopUpAnnotation)
        

        PDFViewWrapper.pdfView?.setNeedsDisplay(bounds)
        showPopUp = true
        savePopUpAnnotation(textAnnotation, documentURL: documentURL, popUpAnnotationContent: popUpAnnotationContent)
    }
    
    func savePopUpAnnotation(_ annotation: PopUpAnnotation, documentURL: URL, popUpAnnotationContent: String) {
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
        
        guard let annotationID = annotation.annotationID else {
            print("Annotation ID is missing.")
            return
        }

        let pageNumber = currentPageIndex + 1 // Convert zero-based index to page number
        let db = Firestore.firestore()
        let popUpAnnotationRef = db.collection("popUpAnnotations")
            .document(documentURL.lastPathComponent)
            .collection("annotations")
            .document(annotationID)
        
        let popUpAnnotationData: [String: Any] = [
            "documentURL": documentURL.absoluteString,
            "annotationID": annotationID,
            "type": "text", // Explicitly specifying type as text
            "content": popUpAnnotationContent,
            "senderEmail": currentUserEmail,
            "bounds": [
                "x": annotation.bounds.origin.x,
                "y": annotation.bounds.origin.y,
                "width": annotation.bounds.size.width,
                "height": annotation.bounds.size.height
            ],
            "pageNumber": pageNumber
        ]
        
        popUpAnnotationRef.setData(popUpAnnotationData) { error in
            if let error = error {
                print("Error saving pop-up annotation: \(error.localizedDescription)")
            } else {
                print("Pop-up annotation saved successfully")
            }
        }
    }


    
    func fetchPopUpAnnotations(documentURL: URL) {
        print("Fetching pop-up annotations")
        guard let currentUserEmail = Auth.auth().currentUser?.email else {
            print("User is not signed in.")
            return
        }
        
        let db = Firestore.firestore()
        let annotationsCollection = db.collection("popUpAnnotations")
            .document(documentURL.lastPathComponent)
            .collection("annotations")
        
        annotationsCollection.getDocuments { querySnapshot, error in
            if let error = error {
                print("Error fetching pop-up annotations: \(error.localizedDescription)")
                return
            }
            
            guard let documents = querySnapshot?.documents else {
                print("No pop-up annotations found.")
                return
            }
            
            if let pdfView = PDFViewWrapper.pdfView {
                for document in documents {
                    let data = document.data()
                    guard let annotationID = data["annotationID"] as? String,
                          let bounds = data["bounds"] as? [String: CGFloat],
                          let x = bounds["x"],
                          let y = bounds["y"],
                          let popUpAnnotationContent = data["content"] as? String,
                          let width = bounds["width"],
                          let height = bounds["height"],
                          let pageNumber = data["pageNumber"] as? Int else {
                        print("Error parsing pop-up annotation data.")
                        continue
                    }
                    
                    let annotationBounds = CGRect(x: x, y: y, width: width, height: height)
                    let annotation = PopUpAnnotation(bounds: annotationBounds, forType: .text, withProperties: nil) // Specify type as .text
                    annotation.annotationID = annotationID // Ensure ID is set on the annotation object
                    annotation.color = .red.withAlphaComponent(0.2) // Set any default properties for text annotations

                    print("Processing annotation with ID: \(annotationID)") // Log the annotation ID for debugging

                    if let currentPage = pdfView.document?.page(at: pageNumber - 1) {
                        currentPage.addAnnotation(annotation)
                    } else {
                        print("Invalid page number: \(pageNumber)")
                    }
                }
                pdfView.setNeedsDisplay()
            } else {
                print("PDFView is nil.")
            }
        }
    }



    
    func deleteOnDocumentAnnotation() {
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
                
            }
        }
        
        showDeleteButton = false
    }
    
    func deleteHighlightAnnotation() {
        guard let pdfView = PDFViewWrapper.pdfView,
              let selectedHighlightAnnotation = selectedHighlightAnnotation,
              let annotationID = selectedHighlightAnnotation.annotationID else {
            return
        }
        
        // Remove the annotation from the PDF view
        if let currentPage = pdfView.currentPage {
            currentPage.removeAnnotation(selectedHighlightAnnotation)
        }
        
        // Remove the annotation from Firestore
        let db = Firestore.firestore()
        let highlightAnnotationsCollection = db.collection("highlightAnnotations").document(documentURL.lastPathComponent).collection("annotations")
        
        highlightAnnotationsCollection.document(annotationID).delete { error in
            if let error = error {
                // Handle the error appropriately
                print("Error deleting annotation from Firestore: \(error)")
            } else {
                // Deletion successful
                print("Annotation deleted from Firestore")
                
            }
        }
        
        
        
        showDeleteButton = false
    }
    
    
    
    func createOnDocumentAnnotation() {
        guard let firstTouchLocation = firstTouchLocation,
              let pdfView = PDFViewWrapper.pdfView,
              let tappedPage = pdfView.page(for: firstTouchLocation, nearest: true) else {
            return
        }
        
        
        let convertedFirstLocation = pdfView.convert(firstTouchLocation, to: tappedPage)
        
        
        
        // User tapped to create a new annotation
        let bounds = CGRect(x: convertedFirstLocation.x , y: convertedFirstLocation.y , width: 50, height: 40)
        let freeTextAnnotation = CustomPDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
        
        // Set the appearance characteristics of the free text annotation
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
        
        var traits = getFontSymbolicTraits()
        if isBold {
            traits.insert(.traitBold)
        }
        if isItalic {
            traits.insert(.traitItalic)
        }
        let updatedFontDescriptor = fontDescriptor.withSymbolicTraits(traits) ?? fontDescriptor
        
        let font = UIFont(descriptor: updatedFontDescriptor, size: fontSize)
        
        freeTextAnnotation.font = font
        freeTextAnnotation.fontColor = UIColor(fontColor)
        freeTextAnnotation.contents = "" // Set the initial text content to an empty string
        freeTextAnnotation.color = .clear
        
        // Configure the border for the annotation
//        let border = PDFBorder()
//        border.lineWidth = 3 // Set the border thickness to 1 (you can adjust this value)
//        border.style = .solid // This is for illustration; PDFBorder doesn't have a 'style' property
//        freeTextAnnotation.border = border

        // Add the annotation to the current page
        tappedPage.addAnnotation(freeTextAnnotation)
        

        
        // Create the text field positioned at the top of the screen
        let textField = UITextField(frame: CGRect(x: 0, y: 0, width: pdfView.bounds.width, height: 40))
        textField.backgroundColor = .gray
        textField.font = font
        textField.textColor = UIColor(fontColor)
        textField.placeholder = "Type here"
        textField.borderStyle = .roundedRect
        
        // Create the "Send" button
        let sendButton = UIButton(type: .system)
        sendButton.setTitle("Send", for: .normal)
        sendButton.sizeToFit()
        
        // Add a closure to execute when the button is tapped
        sendButton.addAction(UIAction { _ in
            self.sendButtonTapped()
        }, for: .touchUpInside)
        
        // Create a toolbar view to hold the button
        let toolbarView = UIToolbar(frame: CGRect(x: 0, y: 0, width: pdfView.bounds.width, height: 44))
        
        // Create a flexible space item to push the button to the right
        let flexibleSpaceItem = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        
        // Create a bar button item with the send button
        let sendBarButtonItem = UIBarButtonItem(customView: sendButton)
        
        // Add the flexible space item and the send button item to the toolbar
        toolbarView.items = [flexibleSpaceItem, sendBarButtonItem]
        
        // Set the toolbar view as the input accessory view of the text field
        textField.inputAccessoryView = toolbarView
        
        tappedPage.addAnnotation(freeTextAnnotation)
        pdfView.addSubview(textField)
        
        // Set the selectedAnnotation to the created free text annotation
        selectedOnDocumentAnnotation = freeTextAnnotation
        
        let annotationID = UUID().uuidString
//        selectedOnDocumentAnnotation!.annotationID = annotationID
        freeTextAnnotation.annotationID = annotationID // Set immediately


        
        pdfView.becomeFirstResponder()
        isTyping = false
        
    }
    
    

    
    
    func sendButtonTapped() {
        guard let pdfView = PDFViewWrapper.pdfView,
              let textField = pdfView.subviews.first(where: { $0 is UITextField }) as? UITextField,
              let selectedOnDocumentAnnotation = selectedOnDocumentAnnotation as? CustomPDFAnnotation,
              let page = pdfView.currentPage else {
            return
        }
        
        selectedOnDocumentAnnotation.contents = textField.text ?? ""
        
        let text = textField.text ?? ""
        let attributes: [NSAttributedString.Key: Any] = [.font: selectedOnDocumentAnnotation.font!]
        
        // Define a maximum width for the annotation, and calculate the height based on this width
        let maxWidth = min(page.bounds(for: .mediaBox).width * 0.8, 200) // Use a practical max width
        let textBoundingRect = text.boundingRect(with: CGSize(width: maxWidth, height: CGFloat.infinity),
                                                 options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                 attributes: attributes,
                                                 context: nil)
        
        // Adjust the size of the annotation based on the text content
        var newWidth = textBoundingRect.width + 20 // Adding padding
        var newHeight = textBoundingRect.height + 20 // Adding padding
        
        // Check against page size to ensure it doesn't exceed the page's dimensions
        let pageWidth = page.bounds(for: .mediaBox).width
        let pageHeight = page.bounds(for: .mediaBox).height
        
        if newWidth > pageWidth * 0.8 { // If the width exceeds 80% of page width, adjust it
            newWidth = pageWidth * 0.8
        }
        
        if newHeight > pageHeight * 0.8 { // If the height exceeds 80% of page height, adjust it
            newHeight = pageHeight * 0.8
        }
        
        // Apply the new bounds to the annotation
        let newBounds = CGRect(x: selectedOnDocumentAnnotation.bounds.origin.x,
                               y: selectedOnDocumentAnnotation.bounds.origin.y,
                               width: newWidth,
                               height: newHeight)
        selectedOnDocumentAnnotation.bounds = newBounds
        
        if let freeTextAnnotation = selectedOnDocumentAnnotation as? CustomPDFAnnotation {
            saveOnDocumentComment(freeTextAnnotation, documentURL: documentURL, isBold: isBold, isItalic: isItalic, fontSize: fontSize, fontColor: fontColor, location: firstTouchLocation!)
        }

        textField.resignFirstResponder()
        textField.removeFromSuperview()
        pdfView.setNeedsDisplay()
        
        self.firstTouchLocation = nil // Reset touch locations for future highlights
    }

    public func getFontSymbolicTraits() -> UIFontDescriptor.SymbolicTraits {
        var traits = UIFontDescriptor.SymbolicTraits()
        if isBold {
            traits.insert(.traitBold)
        }
        if isItalic {
            traits.insert(.traitItalic)
        }
        return traits
    }
}


extension UIColor {
    convenience init?(hexString: String) {
        var hexFormatted = hexString.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        hexFormatted = hexFormatted.replacingOccurrences(of: "#", with: "")
        
        var rgbValue: UInt64 = 0
        Scanner(string: hexFormatted).scanHexInt64(&rgbValue)
        
        var alpha, red, green, blue: CGFloat
        if hexFormatted.count == 6 {
            red = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
            green = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
            blue = CGFloat(rgbValue & 0x0000FF) / 255.0
            alpha = 1.0
        } else if hexFormatted.count == 8 {
            red = CGFloat((rgbValue & 0xFF000000) >> 24) / 255.0
            green = CGFloat((rgbValue & 0x00FF0000) >> 16) / 255.0
            blue = CGFloat((rgbValue & 0x0000FF00) >> 8) / 255.0
            alpha = CGFloat(rgbValue & 0x000000FF) / 255.0
        } else {
            return nil
        }
        
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}







struct CommentAnnotation {
    let documentURL: String
    let annotationID: String
    let type: String
    let senderEmail: String
    let content: String
    let bounds: [String: CGFloat]
    
}










/*
 import SwiftUI
 import FirebaseAuth
 import FirebaseFirestore
 import PDFKit
 import UIKit
 import Firebase
 import AVFoundation

 class CustomPDFAnnotation: PDFAnnotation {
     var annotationID: String?
     
     
 }

 class PopUpAnnotation: PDFAnnotation {
     var annotationID: String?
 }

 class HighlightPDFAnnotation: PDFAnnotation {
     var annotationID: String?
 }

 struct PageAnnotation {
     let annotation: PDFAnnotation
     let pageIndex: Int
 }


 public struct DocumentView: View {
     let documentURL: URL
     @State private var showChatDrawer = false
     @State private var showCommentDrawer = false
     @State private var commentMessages: [CommentMessage] = [] // Store comment messages
     @State private var commentText: String?
     @State private var isAddingComment = false // Track if a comment is being added
     @State private var selectedAnnotationType: PDFAnnotationSubtype? // Track the selected annotation type
     @State private var chatMessages: [ChatMessage] = [] // Store chat messages
     @State private var commentAnnotations: [CommentAnnotation] = [] // Store comment annotations
     @State private var selectedAnnotation: PDFAnnotation? // Store the selected annotation
     @State private var selectedOnDocumentAnnotation: CustomPDFAnnotation? // Store the selected annotation on the document ---
     @State private var selectedHighlightAnnotation: HighlightPDFAnnotation? // Store the selected annotation on the document
     @State private var isTyping = false // Track if the user is typing
     @State private var pdfView: PDFView? // Store the PDF view
     @State private var fontColor: Color = .black // Store the font color
     @State private var showDeleteButton: Bool = false // Track whether to show the delete button
     @State private var isBold: Bool = false // Track if the text is bold
     @State private var isItalic: Bool = false // Track if the text is italic
     @State private var fontSize: CGFloat = 16 // Store the selected font size
     let availableFontSizes: [CGFloat] = [8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32]
     @Environment(\.colorScheme) var colorScheme
     @State private var selectedColor: UIColor = .yellow // Default color
     // Gesture-related states for highlighting annotations
     @State private var firstTouchLocation: CGPoint?
     @State private var secondTouchLocation: CGPoint?
     @State private var isHighlighting: Bool = false
     @State private var highlightAnnotations: [PDFAnnotation] = []
     @State private var lastSynthesisPosition: Int = 0 // Track last synthesis position here

     
     @State private var popUpAnnotationContent: String = ""
     @State private var selectedPopUpAnnotation: PopUpAnnotation?
     @State private var showPopUp: Bool = false // Track whether to show the delete button
     @State private var isPopUp = false // Track if the user is typing

     
     public var body: some View {
         VStack {
             PDFViewWrapper(url: documentURL, handleTapGesture: handleTapGesture, isHighlighting: $isHighlighting, selectedHighlightAnnotation: $selectedHighlightAnnotation, selectedColor: $selectedColor )
                 .onTapGesture {
                     
                 }
         }
         .overlay(
             VStack {
                 Spacer()
                 HStack {
                     Spacer()
                     Button(action: {
                         showChatDrawer.toggle()
                     }) {
                         Image(systemName: "message.fill")
                             .resizable()
                             .frame(width: 20, height: 20)
                             .padding()
                             .background(Color.blue)
                             .foregroundColor(.white)
                             .clipShape(Circle())
                     }
                     .padding(.trailing)
                 }
             }
                 .padding()
         )
         
         .navigationBarItems(
             trailing:
                 HStack {
                     AnnotationToolbar(selectedAnnotationType: $selectedAnnotationType, isAddingComment: $isAddingComment, commentText: $commentText, showCommentDrawer: $showCommentDrawer, isTyping: $isTyping, fontColor: $fontColor, selectedColor: $selectedColor, showDeleteButton: $showDeleteButton, isBold: $isBold, isItalic: $isItalic, fontSize: $fontSize,
                         deleteAction: {
                             self.deleteAction()
                         },
                                       availableFontSizes: availableFontSizes, isHighlighting: $isHighlighting, lastSynthesisPosition: $lastSynthesisPosition, documentURL: documentURL, isPopUp: $isPopUp)
                    // Spacer()
                 }
         )
         .sheet(isPresented: $showCommentDrawer) {
             CommentDrawerView(commentMessages: $commentMessages, documentURL: documentURL, commentText: $commentText, isAddingComment: $isAddingComment, selectedAnnotation: $selectedAnnotation, saveCommentAnnotation: saveCommentAnnotation, showCommentDrawer: $showCommentDrawer)
         }
         .sheet(isPresented: $showChatDrawer) {
             ChatDrawerView(chatMessages: $chatMessages, documentURL: documentURL, commentText: $commentText)
         }
         .sheet(isPresented: $showPopUp) {
             PopUpView(popUpAnnotationContent: $popUpAnnotationContent, onClose: {
                 showPopUp = false
                 popUpAnnotationContent = "" // Clear the content for next use
             }, documentURL: documentURL, selectedPopUpAnnotation: $selectedPopUpAnnotation)
         }
         .onAppear {
             fetchOnDocumentComment(documentURL: documentURL)
             fetchCommentAnnotations(documentURL: documentURL)
             fetchCommentMessages(documentURL: documentURL) { fetchedCommentMessages in
                 commentMessages = fetchedCommentMessages
             }
             fetchHighlightAnnotations(documentURL: documentURL)
             fetchPopUpAnnotations(documentURL: documentURL)
         }
     }
     
     private func deleteAction() {
         // Assuming you can differentiate annotations based on their subtype or a custom property
         if let customAnnotation = selectedOnDocumentAnnotation {
             deleteOnDocumentAnnotation()
         }
         else if let anotherTypeOfAnnotation = selectedHighlightAnnotation{
             deleteHighlightAnnotation()
         }
         else {
             print("Unhandled annotation type")
             print(selectedAnnotation)
         }
         
     }
     
     func handleTapGesture(location: CGPoint) {
         guard let pdfView = PDFViewWrapper.pdfView,
               let currentPage = pdfView.currentPage else {
             print("PDF view or current page not available")
             return
         }

         let tapLocation = pdfView.convert(location, to: currentPage)

         if let tappedAnnotation = currentPage.annotation(at: tapLocation) {
             if let customAnnotation = tappedAnnotation as? CustomPDFAnnotation {
                 selectedOnDocumentAnnotation = customAnnotation
                 showDeleteButton = true
             } else if let highlightAnnotation = tappedAnnotation as? HighlightPDFAnnotation {
                 selectedHighlightAnnotation = highlightAnnotation
                 showDeleteButton = true
             } else if let popUpAnnotation = tappedAnnotation as? PopUpAnnotation {
                 selectedPopUpAnnotation = popUpAnnotation
                 print(selectedPopUpAnnotation?.annotationID)
                 showPopUp = true
             } else {
                 selectedAnnotation = tappedAnnotation
                 showCommentDrawer = true
             }
         } else {
             showDeleteButton = false
             if isAddingComment {
                 let textAnnotation = PDFAnnotation(bounds: CGRect(x: tapLocation.x, y: tapLocation.y, width: 30, height: 30), forType: .freeText, withProperties: nil)
                 textAnnotation.contents = "\(commentMessages.count + 1)"
                 textAnnotation.font = UIFont.boldSystemFont(ofSize: 20)
                 textAnnotation.color = .yellow.withAlphaComponent(0.2)
                 textAnnotation.fontColor = .red
                 textAnnotation.alignment = .center
                 currentPage.addAnnotation(textAnnotation)
                 selectedAnnotation = textAnnotation
                 showCommentDrawer = true
             } else if isTyping {
                 firstTouchLocation = location
                 createOnDocumentAnnotation()
             } else if isPopUp {
                 firstTouchLocation = location
                 createTextAnnotationAsPopup()
             }
         }
     }




     func createTextAnnotationAsPopup() {
         guard let firstTouchLocation = firstTouchLocation,
               let pdfView = PDFViewWrapper.pdfView,
               let tappedPage = pdfView.page(for: firstTouchLocation, nearest: true) else {
             print("Failed to get PDF view or page.")
             return
         }
         
         let convertedFirstLocation = pdfView.convert(firstTouchLocation, to: tappedPage)
         let bounds = CGRect(x: convertedFirstLocation.x, y: convertedFirstLocation.y, width: 30, height: 30)
         let textAnnotation = PopUpAnnotation(bounds: bounds, forType: .text, withProperties: nil)
         textAnnotation.color = .red.withAlphaComponent(0.2)
         
         let annotationID = UUID().uuidString
 //        selectedOnDocumentAnnotation!.annotationID = annotationID
         textAnnotation.annotationID = annotationID // Set immediately

         tappedPage.addAnnotation(textAnnotation)
         print("Added text annotation at \(bounds)")
         selectedPopUpAnnotation = textAnnotation
         print("Selected Annotation: ", selectedPopUpAnnotation)
         

         PDFViewWrapper.pdfView?.setNeedsDisplay(bounds)
         showPopUp = true
         savePopUpAnnotation(textAnnotation, documentURL: documentURL, popUpAnnotationContent: popUpAnnotationContent)
     }
     
     func savePopUpAnnotation(_ annotation: PopUpAnnotation, documentURL: URL, popUpAnnotationContent: String) {
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
         
         guard let annotationID = annotation.annotationID else {
             print("Annotation ID is missing.")
             return
         }

         let pageNumber = currentPageIndex + 1 // Convert zero-based index to page number
         let db = Firestore.firestore()
         let popUpAnnotationRef = db.collection("popUpAnnotations")
             .document(documentURL.lastPathComponent)
             .collection("annotations")
             .document(annotationID)
         
         let popUpAnnotationData: [String: Any] = [
             "documentURL": documentURL.absoluteString,
             "annotationID": annotationID,
             "type": "text", // Explicitly specifying type as text
             "content": popUpAnnotationContent,
             "senderEmail": currentUserEmail,
             "bounds": [
                 "x": annotation.bounds.origin.x,
                 "y": annotation.bounds.origin.y,
                 "width": annotation.bounds.size.width,
                 "height": annotation.bounds.size.height
             ],
             "pageNumber": pageNumber
         ]
         
         popUpAnnotationRef.setData(popUpAnnotationData) { error in
             if let error = error {
                 print("Error saving pop-up annotation: \(error.localizedDescription)")
             } else {
                 print("Pop-up annotation saved successfully")
             }
         }
     }


     
     func fetchPopUpAnnotations(documentURL: URL) {
         print("Fetching pop-up annotations")
         guard let currentUserEmail = Auth.auth().currentUser?.email else {
             print("User is not signed in.")
             return
         }
         
         let db = Firestore.firestore()
         let annotationsCollection = db.collection("popUpAnnotations")
             .document(documentURL.lastPathComponent)
             .collection("annotations")
         
         annotationsCollection.getDocuments { querySnapshot, error in
             if let error = error {
                 print("Error fetching pop-up annotations: \(error.localizedDescription)")
                 return
             }
             
             guard let documents = querySnapshot?.documents else {
                 print("No pop-up annotations found.")
                 return
             }
             
             if let pdfView = PDFViewWrapper.pdfView {
                 for document in documents {
                     let data = document.data()
                     guard let annotationID = data["annotationID"] as? String,
                           let bounds = data["bounds"] as? [String: CGFloat],
                           let x = bounds["x"],
                           let y = bounds["y"],
                           let popUpAnnotationContent = data["content"] as? String,
                           let width = bounds["width"],
                           let height = bounds["height"],
                           let pageNumber = data["pageNumber"] as? Int else {
                         print("Error parsing pop-up annotation data.")
                         continue
                     }
                     
                     let annotationBounds = CGRect(x: x, y: y, width: width, height: height)
                     let annotation = PopUpAnnotation(bounds: annotationBounds, forType: .text, withProperties: nil) // Specify type as .text
                     annotation.annotationID = annotationID // Ensure ID is set on the annotation object
                     annotation.color = .red.withAlphaComponent(0.2) // Set any default properties for text annotations

                     print("Processing annotation with ID: \(annotationID)") // Log the annotation ID for debugging

                     if let currentPage = pdfView.document?.page(at: pageNumber - 1) {
                         currentPage.addAnnotation(annotation)
                     } else {
                         print("Invalid page number: \(pageNumber)")
                     }
                 }
                 pdfView.setNeedsDisplay()
             } else {
                 print("PDFView is nil.")
             }
         }
     }



     
     func deleteOnDocumentAnnotation() {
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
                 
             }
         }
         
         showDeleteButton = false
     }
     
     func deleteHighlightAnnotation() {
         guard let pdfView = PDFViewWrapper.pdfView,
               let selectedHighlightAnnotation = selectedHighlightAnnotation,
               let annotationID = selectedHighlightAnnotation.annotationID else {
             return
         }
         
         // Remove the annotation from the PDF view
         if let currentPage = pdfView.currentPage {
             currentPage.removeAnnotation(selectedHighlightAnnotation)
         }
         
         // Remove the annotation from Firestore
         let db = Firestore.firestore()
         let highlightAnnotationsCollection = db.collection("highlightAnnotations").document(documentURL.lastPathComponent).collection("annotations")
         
         highlightAnnotationsCollection.document(annotationID).delete { error in
             if let error = error {
                 // Handle the error appropriately
                 print("Error deleting annotation from Firestore: \(error)")
             } else {
                 // Deletion successful
                 print("Annotation deleted from Firestore")
                 
             }
         }
         
         
         
         showDeleteButton = false
     }
     
     
     
     func createOnDocumentAnnotation() {
         guard let firstTouchLocation = firstTouchLocation,
               let pdfView = PDFViewWrapper.pdfView,
               let tappedPage = pdfView.page(for: firstTouchLocation, nearest: true) else {
             return
         }
         
         
         let convertedFirstLocation = pdfView.convert(firstTouchLocation, to: tappedPage)
         
         
         
         // User tapped to create a new annotation
         let bounds = CGRect(x: convertedFirstLocation.x , y: convertedFirstLocation.y , width: 50, height: 40)
         let freeTextAnnotation = CustomPDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
         
         // Set the appearance characteristics of the free text annotation
         let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
         
         var traits = getFontSymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         let updatedFontDescriptor = fontDescriptor.withSymbolicTraits(traits) ?? fontDescriptor
         
         let font = UIFont(descriptor: updatedFontDescriptor, size: fontSize)
         
         freeTextAnnotation.font = font
         freeTextAnnotation.fontColor = UIColor(fontColor)
         freeTextAnnotation.contents = "" // Set the initial text content to an empty string
         freeTextAnnotation.color = .clear
         
         // Configure the border for the annotation
 //        let border = PDFBorder()
 //        border.lineWidth = 3 // Set the border thickness to 1 (you can adjust this value)
 //        border.style = .solid // This is for illustration; PDFBorder doesn't have a 'style' property
 //        freeTextAnnotation.border = border

         // Add the annotation to the current page
         tappedPage.addAnnotation(freeTextAnnotation)
         

         
         // Create the text field positioned at the top of the screen
         let textField = UITextField(frame: CGRect(x: 0, y: 0, width: pdfView.bounds.width, height: 40))
         textField.backgroundColor = .gray
         textField.font = font
         textField.textColor = UIColor(fontColor)
         textField.placeholder = "Type here"
         textField.borderStyle = .roundedRect
         
         // Create the "Send" button
         let sendButton = UIButton(type: .system)
         sendButton.setTitle("Send", for: .normal)
         sendButton.sizeToFit()
         
         // Add a closure to execute when the button is tapped
         sendButton.addAction(UIAction { _ in
             self.sendButtonTapped()
         }, for: .touchUpInside)
         
         // Create a toolbar view to hold the button
         let toolbarView = UIToolbar(frame: CGRect(x: 0, y: 0, width: pdfView.bounds.width, height: 44))
         
         // Create a flexible space item to push the button to the right
         let flexibleSpaceItem = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
         
         // Create a bar button item with the send button
         let sendBarButtonItem = UIBarButtonItem(customView: sendButton)
         
         // Add the flexible space item and the send button item to the toolbar
         toolbarView.items = [flexibleSpaceItem, sendBarButtonItem]
         
         // Set the toolbar view as the input accessory view of the text field
         textField.inputAccessoryView = toolbarView
         
         tappedPage.addAnnotation(freeTextAnnotation)
         pdfView.addSubview(textField)
         
         // Set the selectedAnnotation to the created free text annotation
         selectedOnDocumentAnnotation = freeTextAnnotation
         
         let annotationID = UUID().uuidString
 //        selectedOnDocumentAnnotation!.annotationID = annotationID
         freeTextAnnotation.annotationID = annotationID // Set immediately


         
         pdfView.becomeFirstResponder()
         isTyping = false
         
     }
     
     

     
     
     func sendButtonTapped() {
         guard let pdfView = PDFViewWrapper.pdfView,
               let textField = pdfView.subviews.first(where: { $0 is UITextField }) as? UITextField,
               let selectedOnDocumentAnnotation = selectedOnDocumentAnnotation as? CustomPDFAnnotation,
               let page = pdfView.currentPage else {
             return
         }
         
         selectedOnDocumentAnnotation.contents = textField.text ?? ""
         
         let text = textField.text ?? ""
         let attributes: [NSAttributedString.Key: Any] = [.font: selectedOnDocumentAnnotation.font!]
         
         // Define a maximum width for the annotation, and calculate the height based on this width
         let maxWidth = min(page.bounds(for: .mediaBox).width * 0.8, 200) // Use a practical max width
         let textBoundingRect = text.boundingRect(with: CGSize(width: maxWidth, height: CGFloat.infinity),
                                                  options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                  attributes: attributes,
                                                  context: nil)
         
         // Adjust the size of the annotation based on the text content
         var newWidth = textBoundingRect.width + 20 // Adding padding
         var newHeight = textBoundingRect.height + 20 // Adding padding
         
         // Check against page size to ensure it doesn't exceed the page's dimensions
         let pageWidth = page.bounds(for: .mediaBox).width
         let pageHeight = page.bounds(for: .mediaBox).height
         
         if newWidth > pageWidth * 0.8 { // If the width exceeds 80% of page width, adjust it
             newWidth = pageWidth * 0.8
         }
         
         if newHeight > pageHeight * 0.8 { // If the height exceeds 80% of page height, adjust it
             newHeight = pageHeight * 0.8
         }
         
         // Apply the new bounds to the annotation
         let newBounds = CGRect(x: selectedOnDocumentAnnotation.bounds.origin.x,
                                y: selectedOnDocumentAnnotation.bounds.origin.y,
                                width: newWidth,
                                height: newHeight)
         selectedOnDocumentAnnotation.bounds = newBounds
         
         if let freeTextAnnotation = selectedOnDocumentAnnotation as? CustomPDFAnnotation {
             saveOnDocumentComment(freeTextAnnotation, documentURL: documentURL, isBold: isBold, isItalic: isItalic, fontSize: fontSize, fontColor: fontColor, location: firstTouchLocation!)
         }

         textField.resignFirstResponder()
         textField.removeFromSuperview()
         pdfView.setNeedsDisplay()
         
         self.firstTouchLocation = nil // Reset touch locations for future highlights
     }

     public func getFontSymbolicTraits() -> UIFontDescriptor.SymbolicTraits {
         var traits = UIFontDescriptor.SymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         return traits
     }
 }


 extension UIColor {
     convenience init?(hexString: String) {
         var hexFormatted = hexString.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
         hexFormatted = hexFormatted.replacingOccurrences(of: "#", with: "")
         
         var rgbValue: UInt64 = 0
         Scanner(string: hexFormatted).scanHexInt64(&rgbValue)
         
         var alpha, red, green, blue: CGFloat
         if hexFormatted.count == 6 {
             red = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
             green = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
             blue = CGFloat(rgbValue & 0x0000FF) / 255.0
             alpha = 1.0
         } else if hexFormatted.count == 8 {
             red = CGFloat((rgbValue & 0xFF000000) >> 24) / 255.0
             green = CGFloat((rgbValue & 0x00FF0000) >> 16) / 255.0
             blue = CGFloat((rgbValue & 0x0000FF00) >> 8) / 255.0
             alpha = CGFloat(rgbValue & 0x000000FF) / 255.0
         } else {
             return nil
         }
         
         self.init(red: red, green: green, blue: blue, alpha: alpha)
     }
 }







 struct CommentAnnotation {
     let documentURL: String
     let annotationID: String
     let type: String
     let senderEmail: String
     let content: String
     let bounds: [String: CGFloat]
     
 }
 */





















/*
 import SwiftUI
 import FirebaseAuth
 import FirebaseFirestore
 import PDFKit
 import UIKit
 import Firebase
 import AVFoundation

 class CustomPDFAnnotation: PDFAnnotation {
     var annotationID: String?
 }

 class HighlightPDFAnnotation: PDFAnnotation {
     var annotationID: String?
 }

 struct PageAnnotation {
     let annotation: PDFAnnotation
     let pageIndex: Int
 }


 public struct DocumentView: View {
     let documentURL: URL
     @State private var showChatDrawer = false
     @State private var showCommentDrawer = false
     @State private var commentMessages: [CommentMessage] = [] // Store comment messages
     @State private var commentText: String?
     @State private var isAddingComment = false // Track if a comment is being added
     @State private var selectedAnnotationType: PDFAnnotationSubtype? // Track the selected annotation type
     @State private var chatMessages: [ChatMessage] = [] // Store chat messages
     @State private var commentAnnotations: [CommentAnnotation] = [] // Store comment annotations
     @State private var selectedAnnotation: PDFAnnotation? // Store the selected annotation
     @State private var selectedOnDocumentAnnotation: CustomPDFAnnotation? // Store the selected annotation on the document ---
     @State private var selectedHighlightAnnotation: HighlightPDFAnnotation? // Store the selected annotation on the document
     @State private var isTyping = false // Track if the user is typing
     @State private var pdfView: PDFView? // Store the PDF view
     @State private var fontColor: Color = .black // Store the font color
     @State private var showDeleteButton: Bool = false // Track whether to show the delete button
     @State private var isBold: Bool = false // Track if the text is bold
     @State private var isItalic: Bool = false // Track if the text is italic
     @State private var fontSize: CGFloat = 16 // Store the selected font size
     let availableFontSizes: [CGFloat] = [8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32]
     @Environment(\.colorScheme) var colorScheme
     @State private var selectedColor: UIColor = .yellow // Default color
     // Gesture-related states for highlighting annotations
     @State private var firstTouchLocation: CGPoint?
     @State private var secondTouchLocation: CGPoint?
     @State private var isHighlighting: Bool = false
     @State private var highlightAnnotations: [PDFAnnotation] = []
     @State private var lastSynthesisPosition: Int = 0 // Track last synthesis position here

     public var body: some View {
         VStack {
             PDFViewWrapper(url: documentURL, handleTapGesture: handleTapGesture, isHighlighting: $isHighlighting, selectedHighlightAnnotation: $selectedHighlightAnnotation, selectedColor: $selectedColor )
                 .onTapGesture {
                     
                 }
         }
         .overlay(
             VStack {
                 Spacer()
                 HStack {
                     Spacer()
                     Button(action: {
                         showChatDrawer.toggle()
                     }) {
                         Image(systemName: "message.fill")
                             .resizable()
                             .frame(width: 20, height: 20)
                             .padding()
                             .background(Color.blue)
                             .foregroundColor(.white)
                             .clipShape(Circle())
                     }
                     .padding(.trailing)
                 }
             }
                 .padding()
         )
         
         .navigationBarItems(
             trailing:
                 HStack {
                     AnnotationToolbar(selectedAnnotationType: $selectedAnnotationType, isAddingComment: $isAddingComment, commentText: $commentText, showCommentDrawer: $showCommentDrawer, isTyping: $isTyping, fontColor: $fontColor, selectedColor: $selectedColor, showDeleteButton: $showDeleteButton, isBold: $isBold, isItalic: $isItalic, fontSize: $fontSize,
                         deleteAction: {
                             self.deleteAction()
                         },
                         availableFontSizes: availableFontSizes, isHighlighting: $isHighlighting, lastSynthesisPosition: $lastSynthesisPosition, documentURL: documentURL)
                    // Spacer()
                 }
         )
         .sheet(isPresented: $showCommentDrawer) {
             CommentDrawerView(commentMessages: $commentMessages, documentURL: documentURL, commentText: $commentText, isAddingComment: $isAddingComment, selectedAnnotation: $selectedAnnotation, saveCommentAnnotation: saveCommentAnnotation, showCommentDrawer: $showCommentDrawer)
         }
         .sheet(isPresented: $showChatDrawer) {
             ChatDrawerView(chatMessages: $chatMessages, documentURL: documentURL, commentText: $commentText)
         }
         .onAppear {
             fetchOnDocumentComment(documentURL: documentURL)
             fetchCommentAnnotations(documentURL: documentURL)
             fetchCommentMessages(documentURL: documentURL) { fetchedCommentMessages in
                 commentMessages = fetchedCommentMessages
             }
             fetchHighlightAnnotations(documentURL: documentURL)
         }
     }
     
     private func deleteAction() {
         // Assuming you can differentiate annotations based on their subtype or a custom property
         if let customAnnotation = selectedOnDocumentAnnotation {
             deleteOnDocumentAnnotation()
         }
         else if let anotherTypeOfAnnotation = selectedHighlightAnnotation{
             deleteHighlightAnnotation()
         }
         else {
             print("Unhandled annotation type")
             print(selectedAnnotation)
         }
         
     }
     
     func handleTapGesture(location: CGPoint) {
         // Ensure the PDF view is available
         guard let pdfView = PDFViewWrapper.pdfView,
               let currentPage = pdfView.currentPage else { return }

         // Convert the tap location to the coordinate system of the current page
         let tapLocation = pdfView.convert(location, to: currentPage)
         
         // Check if the tap was on an annotation
         if let tappedAnnotation = currentPage.annotation(at: tapLocation) {
             // Check if the annotation is a custom annotation
             if let customAnnotation = tappedAnnotation as? CustomPDFAnnotation{
                 selectedOnDocumentAnnotation = customAnnotation
                 showDeleteButton = true // Show the delete button if it's a custom annotation
             }
             else if let customAnnotation = tappedAnnotation as? HighlightPDFAnnotation{
                 selectedHighlightAnnotation = customAnnotation
                 showDeleteButton = true // Show the delete button if it's a custom annotation
             }
             else {
                 // If the tapped annotation is not a custom one, assume it's a regular PDF annotation
                 selectedAnnotation = tappedAnnotation
                 showCommentDrawer = true // Show the comment drawer for regular annotations
             }
         }
         else {
             // If the tap wasn't on any annotation
             showDeleteButton = false
             if isAddingComment {
                 // User is adding a comment
                 let textAnnotation = PDFAnnotation(bounds: CGRect(x: tapLocation.x, y: tapLocation.y, width: 30, height: 30), forType: .freeText, withProperties: nil)
                 textAnnotation.contents = "\(commentMessages.count + 1)"
                 textAnnotation.font = UIFont.boldSystemFont(ofSize: 20)
                 textAnnotation.color = .yellow.withAlphaComponent(0.2)
                 textAnnotation.fontColor = .red
                 textAnnotation.alignment = .center
                 
                 selectedAnnotation = textAnnotation
                 showCommentDrawer = true
             }
             else if isTyping {
                 // If the user is typing, this is for creating on-document annotations
                 if firstTouchLocation == nil {
                     firstTouchLocation = location
                     createOnDocumentAnnotation()
                 }
             }
         }
     }



     

     
     func deleteOnDocumentAnnotation() {
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
                 
             }
         }
         
         showDeleteButton = false
     }
     
     func deleteHighlightAnnotation() {
         guard let pdfView = PDFViewWrapper.pdfView,
               let selectedHighlightAnnotation = selectedHighlightAnnotation,
               let annotationID = selectedHighlightAnnotation.annotationID else {
             return
         }
         
         // Remove the annotation from the PDF view
         if let currentPage = pdfView.currentPage {
             currentPage.removeAnnotation(selectedHighlightAnnotation)
         }
         
         // Remove the annotation from Firestore
         let db = Firestore.firestore()
         let highlightAnnotationsCollection = db.collection("highlightAnnotations").document(documentURL.lastPathComponent).collection("annotations")
         
         highlightAnnotationsCollection.document(annotationID).delete { error in
             if let error = error {
                 // Handle the error appropriately
                 print("Error deleting annotation from Firestore: \(error)")
             } else {
                 // Deletion successful
                 print("Annotation deleted from Firestore")
                 
             }
         }
         
         
         
         showDeleteButton = false
     }
     
     func createOnDocumentAnnotation() {
         guard let firstTouchLocation = firstTouchLocation,
               let pdfView = PDFViewWrapper.pdfView,
               let tappedPage = pdfView.page(for: firstTouchLocation, nearest: true) else {
             return
         }
         
         
         let convertedFirstLocation = pdfView.convert(firstTouchLocation, to: tappedPage)
         
         
         
         // User tapped to create a new annotation
         let bounds = CGRect(x: convertedFirstLocation.x , y: convertedFirstLocation.y , width: 50, height: 40)
         let freeTextAnnotation = CustomPDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
         
         // Set the appearance characteristics of the free text annotation
         let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
         
         var traits = getFontSymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         let updatedFontDescriptor = fontDescriptor.withSymbolicTraits(traits) ?? fontDescriptor
         
         let font = UIFont(descriptor: updatedFontDescriptor, size: fontSize)
         
         freeTextAnnotation.font = font
         freeTextAnnotation.fontColor = UIColor(fontColor)
         freeTextAnnotation.contents = "" // Set the initial text content to an empty string
         freeTextAnnotation.color = .clear
         
         // Configure the border for the annotation
         let border = PDFBorder()
         border.lineWidth = 3 // Set the border thickness to 1 (you can adjust this value)
         border.style = .solid // This is for illustration; PDFBorder doesn't have a 'style' property
         freeTextAnnotation.border = border

         // Add the annotation to the current page
         tappedPage.addAnnotation(freeTextAnnotation)
         

         
         // Create the text field positioned at the top of the screen
         let textField = UITextField(frame: CGRect(x: 0, y: 0, width: pdfView.bounds.width, height: 40))
         textField.backgroundColor = .gray
         textField.font = font
         textField.textColor = UIColor(fontColor)
         textField.placeholder = "Type here"
         textField.borderStyle = .roundedRect
         
         // Create the "Send" button
         let sendButton = UIButton(type: .system)
         sendButton.setTitle("Send", for: .normal)
         sendButton.sizeToFit()
         
         // Add a closure to execute when the button is tapped
         sendButton.addAction(UIAction { _ in
             self.sendButtonTapped()
         }, for: .touchUpInside)
         
         // Create a toolbar view to hold the button
         let toolbarView = UIToolbar(frame: CGRect(x: 0, y: 0, width: pdfView.bounds.width, height: 44))
         
         // Create a flexible space item to push the button to the right
         let flexibleSpaceItem = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
         
         // Create a bar button item with the send button
         let sendBarButtonItem = UIBarButtonItem(customView: sendButton)
         
         // Add the flexible space item and the send button item to the toolbar
         toolbarView.items = [flexibleSpaceItem, sendBarButtonItem]
         
         // Set the toolbar view as the input accessory view of the text field
         textField.inputAccessoryView = toolbarView
         
         tappedPage.addAnnotation(freeTextAnnotation)
         pdfView.addSubview(textField)
         
         // Set the selectedAnnotation to the created free text annotation
         selectedOnDocumentAnnotation = freeTextAnnotation
         
         let annotationID = UUID().uuidString
         selectedOnDocumentAnnotation!.annotationID = annotationID
         
         pdfView.becomeFirstResponder()
         isTyping = false
         
     }
     
     

     
     
     func sendButtonTapped() {
         guard let pdfView = PDFViewWrapper.pdfView,
               let textField = pdfView.subviews.first(where: { $0 is UITextField }) as? UITextField,
               let selectedOnDocumentAnnotation = selectedOnDocumentAnnotation as? CustomPDFAnnotation,
               let page = pdfView.currentPage else {
             return
         }
         
         selectedOnDocumentAnnotation.contents = textField.text ?? ""
         
         let text = textField.text ?? ""
         let attributes: [NSAttributedString.Key: Any] = [.font: selectedOnDocumentAnnotation.font!]
         
         // Define a maximum width for the annotation, and calculate the height based on this width
         let maxWidth = min(page.bounds(for: .mediaBox).width * 0.8, 200) // Use a practical max width
         let textBoundingRect = text.boundingRect(with: CGSize(width: maxWidth, height: CGFloat.infinity),
                                                  options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                  attributes: attributes,
                                                  context: nil)
         
         // Adjust the size of the annotation based on the text content
         var newWidth = textBoundingRect.width + 20 // Adding padding
         var newHeight = textBoundingRect.height + 20 // Adding padding
         
         // Check against page size to ensure it doesn't exceed the page's dimensions
         let pageWidth = page.bounds(for: .mediaBox).width
         let pageHeight = page.bounds(for: .mediaBox).height
         
         if newWidth > pageWidth * 0.8 { // If the width exceeds 80% of page width, adjust it
             newWidth = pageWidth * 0.8
         }
         
         if newHeight > pageHeight * 0.8 { // If the height exceeds 80% of page height, adjust it
             newHeight = pageHeight * 0.8
         }
         
         // Apply the new bounds to the annotation
         let newBounds = CGRect(x: selectedOnDocumentAnnotation.bounds.origin.x,
                                y: selectedOnDocumentAnnotation.bounds.origin.y,
                                width: newWidth,
                                height: newHeight)
         selectedOnDocumentAnnotation.bounds = newBounds
         
         textField.resignFirstResponder()
         textField.removeFromSuperview()
         pdfView.setNeedsDisplay()
         
         self.firstTouchLocation = nil // Reset touch locations for future highlights
     }

     public func getFontSymbolicTraits() -> UIFontDescriptor.SymbolicTraits {
         var traits = UIFontDescriptor.SymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         return traits
     }
 }


 extension UIColor {
     convenience init?(hexString: String) {
         var hexFormatted = hexString.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
         hexFormatted = hexFormatted.replacingOccurrences(of: "#", with: "")
         
         var rgbValue: UInt64 = 0
         Scanner(string: hexFormatted).scanHexInt64(&rgbValue)
         
         var alpha, red, green, blue: CGFloat
         if hexFormatted.count == 6 {
             red = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
             green = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
             blue = CGFloat(rgbValue & 0x0000FF) / 255.0
             alpha = 1.0
         } else if hexFormatted.count == 8 {
             red = CGFloat((rgbValue & 0xFF000000) >> 24) / 255.0
             green = CGFloat((rgbValue & 0x00FF0000) >> 16) / 255.0
             blue = CGFloat((rgbValue & 0x0000FF00) >> 8) / 255.0
             alpha = CGFloat(rgbValue & 0x000000FF) / 255.0
         } else {
             return nil
         }
         
         self.init(red: red, green: green, blue: blue, alpha: alpha)
     }
 }







 struct CommentAnnotation {
     let documentURL: String
     let annotationID: String
     let type: String
     let senderEmail: String
     let content: String
     let bounds: [String: CGFloat]
     
 }

 */

















/*
 import SwiftUI
 import FirebaseAuth
 import FirebaseFirestore
 import PDFKit
 import UIKit
 import Firebase
 import AVFoundation

 class CustomPDFAnnotation: PDFAnnotation {
     var annotationID: String?
 }

 struct PageAnnotation {
     let annotation: PDFAnnotation
     let pageIndex: Int
 }


 public struct DocumentView: View {
     let documentURL: URL
     @State private var showChatDrawer = false
     @State private var showCommentDrawer = false
     @State private var commentMessages: [CommentMessage] = [] // Store comment messages
     @State private var commentText: String?
     @State private var isAddingComment = false // Track if a comment is being added
     @State private var selectedAnnotationType: PDFAnnotationSubtype? // Track the selected annotation type
     @State private var chatMessages: [ChatMessage] = [] // Store chat messages
     @State private var commentAnnotations: [CommentAnnotation] = [] // Store comment annotations
     @State private var selectedAnnotation: PDFAnnotation? // Store the selected annotation
     @State private var selectedOnDocumentAnnotation: CustomPDFAnnotation? // Store the selected annotation on the document
     @State private var isTyping = false // Track if the user is typing
     @State private var pdfView: PDFView? // Store the PDF view
     @State private var fontColor: Color = .black // Store the font color
     @State private var showDeleteButton: Bool = false // Track whether to show the delete button
     @State private var isBold: Bool = false // Track if the text is bold
     @State private var isItalic: Bool = false // Track if the text is italic
     @State private var fontSize: CGFloat = 16 // Store the selected font size
     let availableFontSizes: [CGFloat] = [8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32]
     @Environment(\.colorScheme) var colorScheme
     @State private var selectedColor: UIColor = .yellow // Default color
     // Gesture-related states for highlighting annotations
     @State private var firstTouchLocation: CGPoint?
     @State private var secondTouchLocation: CGPoint?
     @State private var isHighlighting: Bool = false
     @State private var highlightAnnotations: [PDFAnnotation] = []
     @State private var lastSynthesisPosition: Int = 0 // Track last synthesis position here

     public var body: some View {
         VStack {
             PDFViewWrapper(url: documentURL, handleTapGesture: handleTapGesture, isHighlighting: $isHighlighting, selectedOnDocumentAnnotation: $selectedOnDocumentAnnotation, selectedColor: $selectedColor )
                 .onTapGesture {
                     
                 }
         }
         .overlay(
             VStack {
                 Spacer()
                 HStack {
                     Spacer()
                     Button(action: {
                         showChatDrawer.toggle()
                     }) {
                         Image(systemName: "message.fill")
                             .resizable()
                             .frame(width: 20, height: 20)
                             .padding()
                             .background(Color.blue)
                             .foregroundColor(.white)
                             .clipShape(Circle())
                     }
                     .padding(.trailing)
                 }
             }
                 .padding()
         )
         
         .navigationBarItems(
             trailing:
                 HStack {
                     AnnotationToolbar(selectedAnnotationType: $selectedAnnotationType, isAddingComment: $isAddingComment, commentText: $commentText, showCommentDrawer: $showCommentDrawer, isTyping: $isTyping, fontColor: $fontColor, selectedColor: $selectedColor, showDeleteButton: $showDeleteButton, isBold: $isBold, isItalic: $isItalic, fontSize: $fontSize, deleteAction: deleteAnnotation, availableFontSizes: availableFontSizes, isHighlighting: $isHighlighting, lastSynthesisPosition: $lastSynthesisPosition, documentURL: documentURL)
                    // Spacer()
                 }
         )
         .sheet(isPresented: $showCommentDrawer) {
             CommentDrawerView(commentMessages: $commentMessages, documentURL: documentURL, commentText: $commentText, isAddingComment: $isAddingComment, selectedAnnotation: $selectedAnnotation, saveCommentAnnotation: saveCommentAnnotation, showCommentDrawer: $showCommentDrawer)
         }
         .sheet(isPresented: $showChatDrawer) {
             ChatDrawerView(chatMessages: $chatMessages, documentURL: documentURL, commentText: $commentText)
         }
         .onAppear {
             fetchOnDocumentComment(documentURL: documentURL)
             fetchCommentAnnotations(documentURL: documentURL)
             fetchCommentMessages(documentURL: documentURL) { fetchedCommentMessages in
                 commentMessages = fetchedCommentMessages
             }
             fetchHighlightAnnotations(documentURL: documentURL)
         }
     }
     
     func handleTapGesture(location: CGPoint) {
         // Ensure the PDF view is available
         guard let pdfView = PDFViewWrapper.pdfView,
               let currentPage = pdfView.currentPage else { return }

         // Convert the tap location to the coordinate system of the current page
         let tapLocation = pdfView.convert(location, to: currentPage)
         
         // Check if the tap was on an annotation
         if let tappedAnnotation = currentPage.annotation(at: tapLocation) {
             // Check if the annotation is a custom annotation
             if let customAnnotation = tappedAnnotation as? CustomPDFAnnotation {
                 selectedOnDocumentAnnotation = customAnnotation
                 showDeleteButton = true // Show the delete button if it's a custom annotation
             }
             else {
                 // If the tapped annotation is not a custom one, assume it's a regular PDF annotation
                 selectedAnnotation = tappedAnnotation
                 showCommentDrawer = true // Show the comment drawer for regular annotations
             }
         }
         else {
             // If the tap wasn't on any annotation
             showDeleteButton = false
             if isAddingComment {
                 // User is adding a comment
                 let textAnnotation = PDFAnnotation(bounds: CGRect(x: tapLocation.x, y: tapLocation.y, width: 30, height: 30), forType: .freeText, withProperties: nil)
                 textAnnotation.contents = "\(commentMessages.count + 1)"
                 textAnnotation.font = UIFont.boldSystemFont(ofSize: 20)
                 textAnnotation.color = .yellow.withAlphaComponent(0.2)
                 textAnnotation.fontColor = .red
                 textAnnotation.alignment = .center
                 
                 selectedAnnotation = textAnnotation
                 showCommentDrawer = true
             }
             else if isTyping {
                 // If the user is typing, this is for creating on-document annotations
                 if firstTouchLocation == nil {
                     firstTouchLocation = location
                     createOnDocumentAnnotation()
                 }
             }
         }
     }



     

     
     func deleteAnnotation() {
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
                 
             }
         }
         
         
         
         showDeleteButton = false
     }
     

     
     func createOnDocumentAnnotation() {
         guard let firstTouchLocation = firstTouchLocation,
               let pdfView = PDFViewWrapper.pdfView,
               let tappedPage = pdfView.page(for: firstTouchLocation, nearest: true) else {
             return
         }
         
         
         let convertedFirstLocation = pdfView.convert(firstTouchLocation, to: tappedPage)
         
         
         
         // User tapped to create a new annotation
         let bounds = CGRect(x: convertedFirstLocation.x , y: convertedFirstLocation.y , width: 50, height: 40)
         let freeTextAnnotation = CustomPDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
         
         // Set the appearance characteristics of the free text annotation
         let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
         
         var traits = getFontSymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         let updatedFontDescriptor = fontDescriptor.withSymbolicTraits(traits) ?? fontDescriptor
         
         let font = UIFont(descriptor: updatedFontDescriptor, size: fontSize)
         
         freeTextAnnotation.font = font
         freeTextAnnotation.fontColor = UIColor(fontColor)
         freeTextAnnotation.contents = "" // Set the initial text content to an empty string
         freeTextAnnotation.color = .clear
         
         // Configure the border for the annotation
         let border = PDFBorder()
         border.lineWidth = 3 // Set the border thickness to 1 (you can adjust this value)
         border.style = .solid // This is for illustration; PDFBorder doesn't have a 'style' property
         freeTextAnnotation.border = border

         // Add the annotation to the current page
         tappedPage.addAnnotation(freeTextAnnotation)
         

         
         // Create the text field positioned at the top of the screen
         let textField = UITextField(frame: CGRect(x: 0, y: 0, width: pdfView.bounds.width, height: 40))
         textField.backgroundColor = .gray
         textField.font = font
         textField.textColor = UIColor(fontColor)
         textField.placeholder = "Type here"
         textField.borderStyle = .roundedRect
         
         // Create the "Send" button
         let sendButton = UIButton(type: .system)
         sendButton.setTitle("Send", for: .normal)
         sendButton.sizeToFit()
         
         // Add a closure to execute when the button is tapped
         sendButton.addAction(UIAction { _ in
             self.sendButtonTapped()
         }, for: .touchUpInside)
         
         // Create a toolbar view to hold the button
         let toolbarView = UIToolbar(frame: CGRect(x: 0, y: 0, width: pdfView.bounds.width, height: 44))
         
         // Create a flexible space item to push the button to the right
         let flexibleSpaceItem = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
         
         // Create a bar button item with the send button
         let sendBarButtonItem = UIBarButtonItem(customView: sendButton)
         
         // Add the flexible space item and the send button item to the toolbar
         toolbarView.items = [flexibleSpaceItem, sendBarButtonItem]
         
         // Set the toolbar view as the input accessory view of the text field
         textField.inputAccessoryView = toolbarView
         
         tappedPage.addAnnotation(freeTextAnnotation)
         pdfView.addSubview(textField)
         
         // Set the selectedAnnotation to the created free text annotation
         selectedOnDocumentAnnotation = freeTextAnnotation
         
         let annotationID = UUID().uuidString
         selectedOnDocumentAnnotation!.annotationID = annotationID
         
         pdfView.becomeFirstResponder()
         isTyping = false
         
     }
     
     
     public func getFontSymbolicTraits() -> UIFontDescriptor.SymbolicTraits {
         var traits = UIFontDescriptor.SymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         return traits
     }
     
     
     func sendButtonTapped() {
         guard let pdfView = PDFViewWrapper.pdfView,
               let textField = pdfView.subviews.first(where: { $0 is UITextField }) as? UITextField,
               let selectedOnDocumentAnnotation = selectedOnDocumentAnnotation as? CustomPDFAnnotation else {
             return
         }
         
         selectedOnDocumentAnnotation.contents = textField.text ?? ""
         
         var traits = getFontSymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         
         let currentFontSize = selectedOnDocumentAnnotation.font?.pointSize ?? 16
         let resizedFontDescriptor = selectedOnDocumentAnnotation.font?.fontDescriptor.withSymbolicTraits(traits)
         let resizedFont = UIFont(descriptor: resizedFontDescriptor ?? UIFontDescriptor(), size: currentFontSize)
         
         selectedOnDocumentAnnotation.font = resizedFont
         
         textField.resignFirstResponder() // Hide the keyboard
         textField.removeFromSuperview() // Remove the textField from its superview
         
         if let freeTextAnnotation = selectedOnDocumentAnnotation as? CustomPDFAnnotation {
             saveOnDocumentComment(freeTextAnnotation, documentURL: documentURL, isBold: isBold, isItalic: isItalic, fontSize: fontSize, fontColor: fontColor, location: firstTouchLocation!)
         }
         isTyping = false
         showDeleteButton = false
         // Trigger a re-draw of the PDF view to reflect the updated annotation appearance
         pdfView.setNeedsDisplay()
         
         //   fetchOnDocumentComment(documentURL: documentURL)
         
         // Reset touch locations for future highlights
         self.firstTouchLocation = nil
         self.secondTouchLocation = nil

     }
 }


 extension UIColor {
     convenience init?(hexString: String) {
         var hexFormatted = hexString.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
         hexFormatted = hexFormatted.replacingOccurrences(of: "#", with: "")
         
         var rgbValue: UInt64 = 0
         Scanner(string: hexFormatted).scanHexInt64(&rgbValue)
         
         var alpha, red, green, blue: CGFloat
         if hexFormatted.count == 6 {
             red = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
             green = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
             blue = CGFloat(rgbValue & 0x0000FF) / 255.0
             alpha = 1.0
         } else if hexFormatted.count == 8 {
             red = CGFloat((rgbValue & 0xFF000000) >> 24) / 255.0
             green = CGFloat((rgbValue & 0x00FF0000) >> 16) / 255.0
             blue = CGFloat((rgbValue & 0x0000FF00) >> 8) / 255.0
             alpha = CGFloat(rgbValue & 0x000000FF) / 255.0
         } else {
             return nil
         }
         
         self.init(red: red, green: green, blue: blue, alpha: alpha)
     }
 }







 struct CommentAnnotation {
     let documentURL: String
     let annotationID: String
     let type: String
     let senderEmail: String
     let content: String
     let bounds: [String: CGFloat]
     
 }
 */








/*
 import SwiftUI
 import FirebaseAuth
 import FirebaseFirestore
 import PDFKit
 import UIKit
 import Firebase
 import AVFoundation

 class CustomPDFAnnotation: PDFAnnotation {
     var annotationID: String?
 }

 struct PageAnnotation {
     let annotation: PDFAnnotation
     let pageIndex: Int
 }


 public struct DocumentView: View {
     let documentURL: URL
     @State private var showChatDrawer = false
     @State private var showCommentDrawer = false
     @State private var commentMessages: [CommentMessage] = [] // Store comment messages
     @State private var commentText: String?
     @State private var isAddingComment = false // Track if a comment is being added
     @State private var selectedAnnotationType: PDFAnnotationSubtype? // Track the selected annotation type
     @State private var chatMessages: [ChatMessage] = [] // Store chat messages
     @State private var commentAnnotations: [CommentAnnotation] = [] // Store comment annotations
     @State private var selectedAnnotation: PDFAnnotation? // Store the selected annotation
     @State private var selectedOnDocumentAnnotation: CustomPDFAnnotation? // Store the selected annotation on the document
     @State private var isTyping = false // Track if the user is typing
     @State private var pdfView: PDFView? // Store the PDF view
     @State private var fontColor: Color = .black // Store the font color
     @State private var showDeleteButton: Bool = false // Track whether to show the delete button
     @State private var isBold: Bool = false // Track if the text is bold
     @State private var isItalic: Bool = false // Track if the text is italic
     @State private var fontSize: CGFloat = 16 // Store the selected font size
     let availableFontSizes: [CGFloat] = [8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32]
     @Environment(\.colorScheme) var colorScheme
     @State private var selectedColor: UIColor = .yellow // Default color
     // Gesture-related states for highlighting annotations
     @State private var firstTouchLocation: CGPoint?
     @State private var secondTouchLocation: CGPoint?
     @State private var isHighlighting: Bool = false
     @State private var highlightAnnotations: [PDFAnnotation] = []
     @State private var lastSynthesisPosition: Int = 0 // Track last synthesis position here

     public var body: some View {
         VStack {
             PDFViewWrapper(url: documentURL, handleTapGesture: handleTapGesture, isHighlighting: $isHighlighting, selectedOnDocumentAnnotation: $selectedOnDocumentAnnotation, selectedColor: $selectedColor )
                 .onTapGesture {
                     
                 }
         }
         .overlay(
             VStack {
                 Spacer()
                 HStack {
                     Spacer()
                     Button(action: {
                         showChatDrawer.toggle()
                     }) {
                         Image(systemName: "message.fill")
                             .resizable()
                             .frame(width: 20, height: 20)
                             .padding()
                             .background(Color.blue)
                             .foregroundColor(.white)
                             .clipShape(Circle())
                     }
                     .padding(.trailing)
                 }
             }
                 .padding()
         )
         
         .navigationBarItems(
             trailing:
                 HStack {
                     AnnotationToolbar(selectedAnnotationType: $selectedAnnotationType, isAddingComment: $isAddingComment, commentText: $commentText, showCommentDrawer: $showCommentDrawer, isTyping: $isTyping, fontColor: $fontColor, selectedColor: $selectedColor, showDeleteButton: $showDeleteButton, isBold: $isBold, isItalic: $isItalic, fontSize: $fontSize, deleteAction: deleteAnnotation, availableFontSizes: availableFontSizes, isHighlighting: $isHighlighting, lastSynthesisPosition: $lastSynthesisPosition, documentURL: documentURL)
                    // Spacer()
                 }
         )
         .sheet(isPresented: $showCommentDrawer) {
             CommentDrawerView(commentMessages: $commentMessages, documentURL: documentURL, commentText: $commentText, isAddingComment: $isAddingComment, selectedAnnotation: $selectedAnnotation, saveCommentAnnotation: saveCommentAnnotation, showCommentDrawer: $showCommentDrawer)
         }
         .sheet(isPresented: $showChatDrawer) {
             ChatDrawerView(chatMessages: $chatMessages, documentURL: documentURL, commentText: $commentText)
         }
         .onAppear {
             fetchOnDocumentComment(documentURL: documentURL)
             fetchCommentAnnotations(documentURL: documentURL)
             fetchCommentMessages(documentURL: documentURL) { fetchedCommentMessages in
                 commentMessages = fetchedCommentMessages
             }
             fetchHighlightAnnotations(documentURL: documentURL)
         }
     }
     
     func handleTapGesture(location: CGPoint) {
         // Ensure the PDF view is available
         guard let pdfView = PDFViewWrapper.pdfView,
               let currentPage = pdfView.currentPage else { return }

         // Convert the tap location to the coordinate system of the current page
         let tapLocation = pdfView.convert(location, to: currentPage)
         
         // Check if the tap was on an annotation
         if let tappedAnnotation = currentPage.annotation(at: tapLocation) {
             // Check if the annotation is a custom annotation
             if let customAnnotation = tappedAnnotation as? CustomPDFAnnotation {
                 selectedOnDocumentAnnotation = customAnnotation
                 showDeleteButton = true // Show the delete button if it's a custom annotation
             }
             else {
                 // If the tapped annotation is not a custom one, assume it's a regular PDF annotation
                 selectedAnnotation = tappedAnnotation
                 showCommentDrawer = true // Show the comment drawer for regular annotations
             }
         }
         else {
             // If the tap wasn't on any annotation
             showDeleteButton = false
             if isAddingComment {
                 // User is adding a comment
                 let textAnnotation = PDFAnnotation(bounds: CGRect(x: tapLocation.x, y: tapLocation.y, width: 30, height: 30), forType: .freeText, withProperties: nil)
                 textAnnotation.contents = "\(commentMessages.count + 1)"
                 textAnnotation.font = UIFont.boldSystemFont(ofSize: 20)
                 textAnnotation.color = .yellow.withAlphaComponent(0.2)
                 textAnnotation.fontColor = .red
                 textAnnotation.alignment = .center
                 
                 selectedAnnotation = textAnnotation
                 showCommentDrawer = true
             }
             else if isTyping {
                 // If the user is typing, this is for creating on-document annotations
                 if firstTouchLocation == nil {
                     firstTouchLocation = location
                 } else if secondTouchLocation == nil {
                     secondTouchLocation = location
                     createOnDocumentAnnotation()
                 }
             }
         }
     }



     

     
     func deleteAnnotation() {
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
                 
             }
         }
         
         
         
         showDeleteButton = false
     }
     

     
     func createOnDocumentAnnotation() {
         guard let firstTouchLocation = firstTouchLocation,
               let secondTouchLocation = secondTouchLocation,
               let pdfView = PDFViewWrapper.pdfView,
               let tappedPage = pdfView.page(for: firstTouchLocation, nearest: true) else {
             return
         }
         
         
         let convertedFirstLocation = pdfView.convert(firstTouchLocation, to: tappedPage)
         let convertedSecondLocation = pdfView.convert(secondTouchLocation, to: tappedPage)
         
         
         let width: CGFloat
         let height: CGFloat
         
         width = abs(convertedSecondLocation.x - convertedFirstLocation.x)
         height = abs(convertedFirstLocation.y - convertedSecondLocation.y)
         
         // User tapped to create a new annotation
         let bounds = CGRect(x: convertedFirstLocation.x , y: convertedSecondLocation.y , width: width, height: height)
         let freeTextAnnotation = CustomPDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
         
         // Set the appearance characteristics of the free text annotation
         let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
         
         var traits = getFontSymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         let updatedFontDescriptor = fontDescriptor.withSymbolicTraits(traits) ?? fontDescriptor
         
         let font = UIFont(descriptor: updatedFontDescriptor, size: fontSize)
         
         freeTextAnnotation.font = font
         freeTextAnnotation.fontColor = UIColor(fontColor)
         freeTextAnnotation.contents = "" // Set the initial text content to an empty string
         freeTextAnnotation.color = .black.withAlphaComponent(0.2)
         
         // Add the annotation to the current page
         tappedPage.addAnnotation(freeTextAnnotation)
         
         // Create a label for the annotation text
         let annotationLabel = UILabel(frame: bounds)
         annotationLabel.textAlignment = .center
         annotationLabel.font = font
         annotationLabel.textColor = freeTextAnnotation.fontColor
         annotationLabel.text = freeTextAnnotation.contents
         annotationLabel.backgroundColor = .clear
         pdfView.addSubview(annotationLabel)
         
         // Create the text field positioned at the top of the screen
         let textField = UITextField(frame: CGRect(x: 0, y: 0, width: pdfView.bounds.width, height: 40))
         textField.backgroundColor = .gray
         textField.font = font
         textField.textColor = UIColor(fontColor)
         textField.placeholder = "Type here"
         textField.borderStyle = .roundedRect
         
         // Create the "Send" button
         let sendButton = UIButton(type: .system)
         sendButton.setTitle("Send", for: .normal)
         sendButton.sizeToFit()
         
         // Add a closure to execute when the button is tapped
         sendButton.addAction(UIAction { _ in
             self.sendButtonTapped()
         }, for: .touchUpInside)
         
         // Create a toolbar view to hold the button
         let toolbarView = UIToolbar(frame: CGRect(x: 0, y: 0, width: pdfView.bounds.width, height: 44))
         
         // Create a flexible space item to push the button to the right
         let flexibleSpaceItem = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
         
         // Create a bar button item with the send button
         let sendBarButtonItem = UIBarButtonItem(customView: sendButton)
         
         // Add the flexible space item and the send button item to the toolbar
         toolbarView.items = [flexibleSpaceItem, sendBarButtonItem]
         
         // Set the toolbar view as the input accessory view of the text field
         textField.inputAccessoryView = toolbarView
         
         tappedPage.addAnnotation(freeTextAnnotation)
         pdfView.addSubview(annotationLabel)
         pdfView.addSubview(textField)
         
         // Set the selectedAnnotation to the created free text annotation
         selectedOnDocumentAnnotation = freeTextAnnotation
         
         let annotationID = UUID().uuidString
         selectedOnDocumentAnnotation!.annotationID = annotationID
         
         pdfView.becomeFirstResponder()
         isTyping = false
         
     }
     
     
     public func getFontSymbolicTraits() -> UIFontDescriptor.SymbolicTraits {
         var traits = UIFontDescriptor.SymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         return traits
     }
     
     
     func sendButtonTapped() {
         guard let pdfView = PDFViewWrapper.pdfView,
               let textField = pdfView.subviews.first(where: { $0 is UITextField }) as? UITextField,
               let selectedOnDocumentAnnotation = selectedOnDocumentAnnotation as? CustomPDFAnnotation else {
             return
         }
         
         selectedOnDocumentAnnotation.contents = textField.text ?? ""
         
         var traits = getFontSymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         
         let currentFontSize = selectedOnDocumentAnnotation.font?.pointSize ?? 16
         let resizedFontDescriptor = selectedOnDocumentAnnotation.font?.fontDescriptor.withSymbolicTraits(traits)
         let resizedFont = UIFont(descriptor: resizedFontDescriptor ?? UIFontDescriptor(), size: currentFontSize)
         
         selectedOnDocumentAnnotation.font = resizedFont
         
         textField.resignFirstResponder() // Hide the keyboard
         textField.removeFromSuperview() // Remove the textField from its superview
         
         if let freeTextAnnotation = selectedOnDocumentAnnotation as? CustomPDFAnnotation {
             saveOnDocumentComment(freeTextAnnotation, documentURL: documentURL, isBold: isBold, isItalic: isItalic, fontSize: fontSize, fontColor: fontColor, location: firstTouchLocation!)
         }
         isTyping = false
         showDeleteButton = false
         // Trigger a re-draw of the PDF view to reflect the updated annotation appearance
         pdfView.setNeedsDisplay()
         
         //   fetchOnDocumentComment(documentURL: documentURL)
         
         // Reset touch locations for future highlights
         self.firstTouchLocation = nil
         self.secondTouchLocation = nil

     }
 }


 extension UIColor {
     convenience init?(hexString: String) {
         var hexFormatted = hexString.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
         hexFormatted = hexFormatted.replacingOccurrences(of: "#", with: "")
         
         var rgbValue: UInt64 = 0
         Scanner(string: hexFormatted).scanHexInt64(&rgbValue)
         
         var alpha, red, green, blue: CGFloat
         if hexFormatted.count == 6 {
             red = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
             green = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
             blue = CGFloat(rgbValue & 0x0000FF) / 255.0
             alpha = 1.0
         } else if hexFormatted.count == 8 {
             red = CGFloat((rgbValue & 0xFF000000) >> 24) / 255.0
             green = CGFloat((rgbValue & 0x00FF0000) >> 16) / 255.0
             blue = CGFloat((rgbValue & 0x0000FF00) >> 8) / 255.0
             alpha = CGFloat(rgbValue & 0x000000FF) / 255.0
         } else {
             return nil
         }
         
         self.init(red: red, green: green, blue: blue, alpha: alpha)
     }
 }







 struct CommentAnnotation {
     let documentURL: String
     let annotationID: String
     let type: String
     let senderEmail: String
     let content: String
     let bounds: [String: CGFloat]
     
 }
 */
















/*
 import SwiftUI
 import FirebaseAuth
 import FirebaseFirestore
 import PDFKit
 import UIKit
 import Firebase
 import AVFoundation

 class CustomPDFAnnotation: PDFAnnotation {
     var annotationID: String?
 }

 struct PageAnnotation {
     let annotation: PDFAnnotation
     let pageIndex: Int
 }


 public struct DocumentView: View {
     let documentURL: URL
     @State private var showChatDrawer = false
     @State private var showCommentDrawer = false
     @State private var commentMessages: [CommentMessage] = [] // Store comment messages
     @State private var commentText: String?
     @State private var isAddingComment = false // Track if a comment is being added
     @State private var selectedAnnotationType: PDFAnnotationSubtype? // Track the selected annotation type
     @State private var chatMessages: [ChatMessage] = [] // Store chat messages
     @State private var commentAnnotations: [CommentAnnotation] = [] // Store comment annotations
     @State private var selectedAnnotation: PDFAnnotation? // Store the selected annotation
     @State private var selectedOnDocumentAnnotation: CustomPDFAnnotation? // Store the selected annotation on the document
     @State private var isTyping = false // Track if the user is typing
     @State private var pdfView: PDFView? // Store the PDF view
     @State private var fontColor: Color = .black // Store the font color
     @State private var showDeleteButton: Bool = false // Track whether to show the delete button
     @State private var isBold: Bool = false // Track if the text is bold
     @State private var isItalic: Bool = false // Track if the text is italic
     @State private var fontSize: CGFloat = 16 // Store the selected font size
     let availableFontSizes: [CGFloat] = [8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32]
     @Environment(\.colorScheme) var colorScheme
     
     // Gesture-related states for highlighting annotations
     @State private var firstTouchLocation: CGPoint?
     @State private var secondTouchLocation: CGPoint?
     @State private var isHighlighting: Bool = false
     @State private var highlightAnnotations: [PDFAnnotation] = []
     @State private var lastSynthesisPosition: Int = 0 // Track last synthesis position here

     public var body: some View {
         VStack {
             PDFViewWrapper(url: documentURL, handleTapGesture: handleTapGesture, isHighlighting: $isHighlighting, selectedOnDocumentAnnotation: $selectedOnDocumentAnnotation )
                 .onTapGesture {
                     
                 }
         }
         .overlay(
             VStack {
                 Spacer()
                 HStack {
                     Spacer()
                     Button(action: {
                         showChatDrawer.toggle()
                     }) {
                         Image(systemName: "message.fill")
                             .resizable()
                             .frame(width: 20, height: 20)
                             .padding()
                             .background(Color.blue)
                             .foregroundColor(.white)
                             .clipShape(Circle())
                     }
                     .padding(.trailing)
                 }
             }
                 .padding()
         )
         
         .navigationBarItems(
             trailing:
                 HStack {
                     AnnotationToolbar(selectedAnnotationType: $selectedAnnotationType, isAddingComment: $isAddingComment, commentText: $commentText, showCommentDrawer: $showCommentDrawer, isTyping: $isTyping, fontColor: $fontColor, showDeleteButton: $showDeleteButton, isBold: $isBold, isItalic: $isItalic, fontSize: $fontSize, deleteAction: deleteAnnotation, availableFontSizes: availableFontSizes, isHighlighting: $isHighlighting, documentURL: documentURL, lastSynthesisPosition: $lastSynthesisPosition)
                    // Spacer()
                 }
         )
         .sheet(isPresented: $showCommentDrawer) {
             CommentDrawerView(commentMessages: $commentMessages, documentURL: documentURL, commentText: $commentText, isAddingComment: $isAddingComment, selectedAnnotation: $selectedAnnotation, saveCommentAnnotation: saveCommentAnnotation, showCommentDrawer: $showCommentDrawer)
         }
         .sheet(isPresented: $showChatDrawer) {
             ChatDrawerView(chatMessages: $chatMessages, documentURL: documentURL, commentText: $commentText)
         }
         .onAppear {
             fetchOnDocumentComment(documentURL: documentURL)
             fetchCommentAnnotations(documentURL: documentURL)
             fetchCommentMessages(documentURL: documentURL) { fetchedCommentMessages in
                 commentMessages = fetchedCommentMessages
             }
             fetchHighlightAnnotations(documentURL: documentURL)
         }
     }
     
     func handleTapGesture(location: CGPoint) {
         // Ensure the PDF view is available
         guard let pdfView = PDFViewWrapper.pdfView,
               let currentPage = pdfView.currentPage else { return }

         // Convert the tap location to the coordinate system of the current page
         let tapLocation = pdfView.convert(location, to: currentPage)
         
         // Check if the tap was on an annotation
         if let tappedAnnotation = currentPage.annotation(at: tapLocation) {
             // Check if the annotation is a custom annotation
             if let customAnnotation = tappedAnnotation as? CustomPDFAnnotation {
                 selectedOnDocumentAnnotation = customAnnotation
                 showDeleteButton = true // Show the delete button if it's a custom annotation
             } else {
                 // If the tapped annotation is not a custom one, assume it's a regular PDF annotation
                 selectedAnnotation = tappedAnnotation
                 showCommentDrawer = true // Show the comment drawer for regular annotations
             }
         } else {
             // If the tap wasn't on any annotation
             showDeleteButton = false
             if isAddingComment {
                 // User is adding a comment
                 let textAnnotation = PDFAnnotation(bounds: CGRect(x: tapLocation.x, y: tapLocation.y, width: 30, height: 30), forType: .freeText, withProperties: nil)
                 textAnnotation.contents = "\(commentMessages.count + 1)"
                 textAnnotation.font = UIFont.boldSystemFont(ofSize: 20)
                 textAnnotation.color = .yellow.withAlphaComponent(0.2)
                 textAnnotation.fontColor = .red
                 textAnnotation.alignment = .center
                 
                 selectedAnnotation = textAnnotation
                 showCommentDrawer = true
             } else if isTyping {
                 // If the user is typing, this is for creating on-document annotations
                 if firstTouchLocation == nil {
                     firstTouchLocation = location
                 } else if secondTouchLocation == nil {
                     secondTouchLocation = location
                     createOnDocumentAnnotation()
                 }
             }
         }
     }



     

     
     func deleteAnnotation() {
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
                 
             }
         }
         
         
         
         showDeleteButton = false
     }
     

     
     func createOnDocumentAnnotation() {
         guard let firstTouchLocation = firstTouchLocation,
               let secondTouchLocation = secondTouchLocation,
               let pdfView = PDFViewWrapper.pdfView,
               let tappedPage = pdfView.page(for: firstTouchLocation, nearest: true) else {
             return
         }
         
         
         let convertedFirstLocation = pdfView.convert(firstTouchLocation, to: tappedPage)
         let convertedSecondLocation = pdfView.convert(secondTouchLocation, to: tappedPage)
         
         
         let width: CGFloat
         let height: CGFloat
         
         width = abs(convertedSecondLocation.x - convertedFirstLocation.x)
         height = abs(convertedFirstLocation.y - convertedSecondLocation.y)
         
         // User tapped to create a new annotation
         let bounds = CGRect(x: convertedFirstLocation.x , y: convertedSecondLocation.y , width: width, height: height)
         let freeTextAnnotation = CustomPDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
         
         // Set the appearance characteristics of the free text annotation
         let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
         
         var traits = getFontSymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         let updatedFontDescriptor = fontDescriptor.withSymbolicTraits(traits) ?? fontDescriptor
         
         let font = UIFont(descriptor: updatedFontDescriptor, size: fontSize)
         
         freeTextAnnotation.font = font
         freeTextAnnotation.fontColor = UIColor(fontColor)
         freeTextAnnotation.contents = "" // Set the initial text content to an empty string
         freeTextAnnotation.color = .black.withAlphaComponent(0.2)
         
         // Add the annotation to the current page
         tappedPage.addAnnotation(freeTextAnnotation)
         
         // Create a label for the annotation text
         let annotationLabel = UILabel(frame: bounds)
         annotationLabel.textAlignment = .center
         annotationLabel.font = font
         annotationLabel.textColor = freeTextAnnotation.fontColor
         annotationLabel.text = freeTextAnnotation.contents
         annotationLabel.backgroundColor = .clear
         pdfView.addSubview(annotationLabel)
         
         // Create the text field positioned at the top of the screen
         let textField = UITextField(frame: CGRect(x: 0, y: 0, width: pdfView.bounds.width, height: 40))
         textField.backgroundColor = .gray
         textField.font = font
         textField.textColor = UIColor(fontColor)
         textField.placeholder = "Type here"
         textField.borderStyle = .roundedRect
         
         // Create the "Send" button
         let sendButton = UIButton(type: .system)
         sendButton.setTitle("Send", for: .normal)
         sendButton.sizeToFit()
         
         // Add a closure to execute when the button is tapped
         sendButton.addAction(UIAction { _ in
             self.sendButtonTapped()
         }, for: .touchUpInside)
         
         // Create a toolbar view to hold the button
         let toolbarView = UIToolbar(frame: CGRect(x: 0, y: 0, width: pdfView.bounds.width, height: 44))
         
         // Create a flexible space item to push the button to the right
         let flexibleSpaceItem = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
         
         // Create a bar button item with the send button
         let sendBarButtonItem = UIBarButtonItem(customView: sendButton)
         
         // Add the flexible space item and the send button item to the toolbar
         toolbarView.items = [flexibleSpaceItem, sendBarButtonItem]
         
         // Set the toolbar view as the input accessory view of the text field
         textField.inputAccessoryView = toolbarView
         
         tappedPage.addAnnotation(freeTextAnnotation)
         pdfView.addSubview(annotationLabel)
         pdfView.addSubview(textField)
         
         // Set the selectedAnnotation to the created free text annotation
         selectedOnDocumentAnnotation = freeTextAnnotation
         
         let annotationID = UUID().uuidString
         selectedOnDocumentAnnotation!.annotationID = annotationID
         
         pdfView.becomeFirstResponder()
         isTyping = false
         
     }
     
     
     public func getFontSymbolicTraits() -> UIFontDescriptor.SymbolicTraits {
         var traits = UIFontDescriptor.SymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         return traits
     }
     
     
     func sendButtonTapped() {
         guard let pdfView = PDFViewWrapper.pdfView,
               let textField = pdfView.subviews.first(where: { $0 is UITextField }) as? UITextField,
               let selectedOnDocumentAnnotation = selectedOnDocumentAnnotation as? CustomPDFAnnotation else {
             return
         }
         
         selectedOnDocumentAnnotation.contents = textField.text ?? ""
         
         var traits = getFontSymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         
         let currentFontSize = selectedOnDocumentAnnotation.font?.pointSize ?? 16
         let resizedFontDescriptor = selectedOnDocumentAnnotation.font?.fontDescriptor.withSymbolicTraits(traits)
         let resizedFont = UIFont(descriptor: resizedFontDescriptor ?? UIFontDescriptor(), size: currentFontSize)
         
         selectedOnDocumentAnnotation.font = resizedFont
         
         textField.resignFirstResponder() // Hide the keyboard
         textField.removeFromSuperview() // Remove the textField from its superview
         
         if let freeTextAnnotation = selectedOnDocumentAnnotation as? CustomPDFAnnotation {
             saveOnDocumentComment(freeTextAnnotation, documentURL: documentURL, isBold: isBold, isItalic: isItalic, fontSize: fontSize, fontColor: fontColor, location: firstTouchLocation!)
         }
         isTyping = false
         showDeleteButton = false
         // Trigger a re-draw of the PDF view to reflect the updated annotation appearance
         pdfView.setNeedsDisplay()
         
         //   fetchOnDocumentComment(documentURL: documentURL)
         
         // Reset touch locations for future highlights
         self.firstTouchLocation = nil
         self.secondTouchLocation = nil

     }
 }


 extension UIColor {
     convenience init?(hexString: String) {
         var hexFormatted = hexString.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
         hexFormatted = hexFormatted.replacingOccurrences(of: "#", with: "")
         
         var rgbValue: UInt64 = 0
         Scanner(string: hexFormatted).scanHexInt64(&rgbValue)
         
         var alpha, red, green, blue: CGFloat
         if hexFormatted.count == 6 {
             red = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
             green = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
             blue = CGFloat(rgbValue & 0x0000FF) / 255.0
             alpha = 1.0
         } else if hexFormatted.count == 8 {
             red = CGFloat((rgbValue & 0xFF000000) >> 24) / 255.0
             green = CGFloat((rgbValue & 0x00FF0000) >> 16) / 255.0
             blue = CGFloat((rgbValue & 0x0000FF00) >> 8) / 255.0
             alpha = CGFloat(rgbValue & 0x000000FF) / 255.0
         } else {
             return nil
         }
         
         self.init(red: red, green: green, blue: blue, alpha: alpha)
     }
 }







 struct CommentAnnotation {
     let documentURL: String
     let annotationID: String
     let type: String
     let senderEmail: String
     let content: String
     let bounds: [String: CGFloat]
     
 }
 */









































/*
 import SwiftUI
 import FirebaseAuth
 import FirebaseFirestore
 import PDFKit
 import UIKit
 import Firebase
 import AVFoundation

 class CustomPDFAnnotation: PDFAnnotation {
     var annotationID: String?
 }

 struct PageAnnotation {
     let annotation: PDFAnnotation
     let pageIndex: Int
 }


 public struct DocumentView: View {
     let documentURL: URL
     @State private var showChatDrawer = false
     @State private var showCommentDrawer = false
     @State private var commentMessages: [CommentMessage] = [] // Store comment messages
     @State private var commentText: String?
     @State private var isAddingComment = false // Track if a comment is being added
     @State private var selectedAnnotationType: PDFAnnotationSubtype? // Track the selected annotation type
     @State private var chatMessages: [ChatMessage] = [] // Store chat messages
     @State private var commentAnnotations: [CommentAnnotation] = [] // Store comment annotations
     @State private var selectedAnnotation: PDFAnnotation? // Store the selected annotation
     @State private var selectedOnDocumentAnnotation: CustomPDFAnnotation? // Store the selected annotation on the document
     @State private var isTyping = false // Track if the user is typing
     @State private var pdfView: PDFView? // Store the PDF view
     @State private var fontColor: Color = .black // Store the font color
     @State private var showDeleteButton: Bool = false // Track whether to show the delete button
     @State private var isBold: Bool = false // Track if the text is bold
     @State private var isItalic: Bool = false // Track if the text is italic
     @State private var fontSize: CGFloat = 16 // Store the selected font size
     let availableFontSizes: [CGFloat] = [8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32]
     @Environment(\.colorScheme) var colorScheme
     
     // Gesture-related states for highlighting annotations
     @State private var firstTouchLocation: CGPoint?
     @State private var secondTouchLocation: CGPoint?
     @State private var isHighlighting: Bool = false
     @State private var highlightAnnotations: [PDFAnnotation] = []
     @State private var lastSynthesisPosition: Int = 0 // Track last synthesis position here

     public var body: some View {
         VStack {
             PDFViewWrapper(url: documentURL, handleTapGesture: handleTapGesture, isHighlighting: $isHighlighting, selectedOnDocumentAnnotation: $selectedOnDocumentAnnotation )
                 .onTapGesture {
                     
                 }
         }
         .overlay(
             VStack {
                 Spacer()
                 HStack {
                     Spacer()
                     Button(action: {
                         showChatDrawer.toggle()
                     }) {
                         Image(systemName: "message.fill")
                             .resizable()
                             .frame(width: 20, height: 20)
                             .padding()
                             .background(Color.blue)
                             .foregroundColor(.white)
                             .clipShape(Circle())
                     }
                     .padding(.trailing)
                 }
             }
                 .padding()
         )
         
         .navigationBarItems(
             trailing:
                 HStack {
                     AnnotationToolbar(selectedAnnotationType: $selectedAnnotationType, isAddingComment: $isAddingComment, commentText: $commentText, showCommentDrawer: $showCommentDrawer, isTyping: $isTyping, fontColor: $fontColor, showDeleteButton: $showDeleteButton, isBold: $isBold, isItalic: $isItalic, fontSize: $fontSize, deleteAction: deleteAnnotation, availableFontSizes: availableFontSizes, isHighlighting: $isHighlighting, documentURL: documentURL, lastSynthesisPosition: $lastSynthesisPosition)
                    // Spacer()
                 }
         )
         .sheet(isPresented: $showCommentDrawer) {
             CommentDrawerView(commentMessages: $commentMessages, documentURL: documentURL, commentText: $commentText, isAddingComment: $isAddingComment, selectedAnnotation: $selectedAnnotation, saveCommentAnnotation: saveCommentAnnotation, showCommentDrawer: $showCommentDrawer)
         }
         .sheet(isPresented: $showChatDrawer) {
             ChatDrawerView(chatMessages: $chatMessages, documentURL: documentURL, commentText: $commentText)
         }
         .onAppear {
             fetchOnDocumentComment(documentURL: documentURL)
             fetchCommentAnnotations(documentURL: documentURL)
             fetchCommentMessages(documentURL: documentURL) { fetchedCommentMessages in
                 commentMessages = fetchedCommentMessages
             }
             fetchHighlightAnnotations(documentURL: documentURL)
         }
     }
     
     func handleTapGesture(location: CGPoint) {
         // Ensure the PDF view is available
         guard let pdfView = PDFViewWrapper.pdfView,
               let currentPage = pdfView.currentPage else { return }

         // Convert the tap location to the coordinate system of the current page
         let tapLocation = pdfView.convert(location, to: currentPage)
         
         // Check if the tap was on an annotation
         if let tappedAnnotation = currentPage.annotation(at: tapLocation) {
             // Check if the annotation is a custom annotation
             if let customAnnotation = tappedAnnotation as? CustomPDFAnnotation {
                 selectedOnDocumentAnnotation = customAnnotation
                 showDeleteButton = true // Show the delete button if it's a custom annotation
             } else {
                 // If the tapped annotation is not a custom one, assume it's a regular PDF annotation
                 selectedAnnotation = tappedAnnotation
                 showCommentDrawer = true // Show the comment drawer for regular annotations
             }
         } else {
             // If the tap wasn't on any annotation
             showDeleteButton = false
             if isAddingComment {
                 // User is adding a comment
                 let textAnnotation = PDFAnnotation(bounds: CGRect(x: tapLocation.x, y: tapLocation.y, width: 30, height: 30), forType: .freeText, withProperties: nil)
                 textAnnotation.contents = "\(commentMessages.count + 1)"
                 textAnnotation.font = UIFont.boldSystemFont(ofSize: 20)
                 textAnnotation.color = .yellow.withAlphaComponent(0.2)
                 textAnnotation.fontColor = .red
                 textAnnotation.alignment = .center
                 
                 selectedAnnotation = textAnnotation
                 showCommentDrawer = true
             } else if isTyping {
                 // If the user is typing, this is for creating on-document annotations
                 if firstTouchLocation == nil {
                     firstTouchLocation = location
                 } else if secondTouchLocation == nil {
                     secondTouchLocation = location
                     createOnDocumentAnnotation()
                 }
             }
         }
     }



     

     
     func deleteAnnotation() {
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
                 
             }
         }
         
         
         
         showDeleteButton = false
     }
     

     
     func createOnDocumentAnnotation() {
         guard let firstTouchLocation = firstTouchLocation,
               let secondTouchLocation = secondTouchLocation,
               let pdfView = PDFViewWrapper.pdfView,
               let tappedPage = pdfView.page(for: firstTouchLocation, nearest: true) else {
             return
         }
         
         
         let convertedFirstLocation = pdfView.convert(firstTouchLocation, to: tappedPage)
         let convertedSecondLocation = pdfView.convert(secondTouchLocation, to: tappedPage)
         
         
         let width: CGFloat
         let height: CGFloat
         
         width = abs(convertedSecondLocation.x - convertedFirstLocation.x)
         height = abs(convertedFirstLocation.y - convertedSecondLocation.y)
         
         // User tapped to create a new annotation
         let bounds = CGRect(x: convertedFirstLocation.x , y: convertedSecondLocation.y , width: width, height: height)
         let freeTextAnnotation = CustomPDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
         
         // Set the appearance characteristics of the free text annotation
         let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
         
         var traits = getFontSymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         let updatedFontDescriptor = fontDescriptor.withSymbolicTraits(traits) ?? fontDescriptor
         
         let font = UIFont(descriptor: updatedFontDescriptor, size: fontSize)
         
         freeTextAnnotation.font = font
         freeTextAnnotation.fontColor = UIColor(fontColor)
         freeTextAnnotation.contents = "" // Set the initial text content to an empty string
         freeTextAnnotation.color = .black.withAlphaComponent(0.2)
         
         // Add the annotation to the current page
         tappedPage.addAnnotation(freeTextAnnotation)
         
         // Create a label for the annotation text
         let annotationLabel = UILabel(frame: bounds)
         annotationLabel.textAlignment = .center
         annotationLabel.font = font
         annotationLabel.textColor = freeTextAnnotation.fontColor
         annotationLabel.text = freeTextAnnotation.contents
         annotationLabel.backgroundColor = .clear
         pdfView.addSubview(annotationLabel)
         
         // Create the text field positioned at the top of the screen
         let textField = UITextField(frame: CGRect(x: 0, y: 0, width: pdfView.bounds.width, height: 40))
         textField.backgroundColor = .gray
         textField.font = font
         textField.textColor = UIColor(fontColor)
         textField.placeholder = "Type here"
         textField.borderStyle = .roundedRect
         
         // Create the "Send" button
         let sendButton = UIButton(type: .system)
         sendButton.setTitle("Send", for: .normal)
         sendButton.sizeToFit()
         
         // Add a closure to execute when the button is tapped
         sendButton.addAction(UIAction { _ in
             self.sendButtonTapped()
         }, for: .touchUpInside)
         
         // Create a toolbar view to hold the button
         let toolbarView = UIToolbar(frame: CGRect(x: 0, y: 0, width: pdfView.bounds.width, height: 44))
         
         // Create a flexible space item to push the button to the right
         let flexibleSpaceItem = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
         
         // Create a bar button item with the send button
         let sendBarButtonItem = UIBarButtonItem(customView: sendButton)
         
         // Add the flexible space item and the send button item to the toolbar
         toolbarView.items = [flexibleSpaceItem, sendBarButtonItem]
         
         // Set the toolbar view as the input accessory view of the text field
         textField.inputAccessoryView = toolbarView
         
         tappedPage.addAnnotation(freeTextAnnotation)
         pdfView.addSubview(annotationLabel)
         pdfView.addSubview(textField)
         
         // Set the selectedAnnotation to the created free text annotation
         selectedOnDocumentAnnotation = freeTextAnnotation
         
         let annotationID = UUID().uuidString
         selectedOnDocumentAnnotation!.annotationID = annotationID
         
         pdfView.becomeFirstResponder()
         isTyping = false
         
     }
     
     
     public func getFontSymbolicTraits() -> UIFontDescriptor.SymbolicTraits {
         var traits = UIFontDescriptor.SymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         return traits
     }
     
     
     func sendButtonTapped() {
         guard let pdfView = PDFViewWrapper.pdfView,
               let textField = pdfView.subviews.first(where: { $0 is UITextField }) as? UITextField,
               let selectedOnDocumentAnnotation = selectedOnDocumentAnnotation as? CustomPDFAnnotation else {
             return
         }
         
         selectedOnDocumentAnnotation.contents = textField.text ?? ""
         
         var traits = getFontSymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         
         let currentFontSize = selectedOnDocumentAnnotation.font?.pointSize ?? 16
         let resizedFontDescriptor = selectedOnDocumentAnnotation.font?.fontDescriptor.withSymbolicTraits(traits)
         let resizedFont = UIFont(descriptor: resizedFontDescriptor ?? UIFontDescriptor(), size: currentFontSize)
         
         selectedOnDocumentAnnotation.font = resizedFont
         
         textField.resignFirstResponder() // Hide the keyboard
         textField.removeFromSuperview() // Remove the textField from its superview
         
         if let freeTextAnnotation = selectedOnDocumentAnnotation as? CustomPDFAnnotation {
             saveOnDocumentComment(freeTextAnnotation, documentURL: documentURL, isBold: isBold, isItalic: isItalic, fontSize: fontSize, fontColor: fontColor, location: firstTouchLocation!)
         }
         isTyping = false
         showDeleteButton = false
         // Trigger a re-draw of the PDF view to reflect the updated annotation appearance
         pdfView.setNeedsDisplay()
         
         //   fetchOnDocumentComment(documentURL: documentURL)
         
         // Reset touch locations for future highlights
         self.firstTouchLocation = nil
         self.secondTouchLocation = nil

     }
 }


 extension UIColor {
     convenience init?(hexString: String) {
         var hexFormatted = hexString.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
         hexFormatted = hexFormatted.replacingOccurrences(of: "#", with: "")
         
         var rgbValue: UInt64 = 0
         Scanner(string: hexFormatted).scanHexInt64(&rgbValue)
         
         var alpha, red, green, blue: CGFloat
         if hexFormatted.count == 6 {
             red = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
             green = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
             blue = CGFloat(rgbValue & 0x0000FF) / 255.0
             alpha = 1.0
         } else if hexFormatted.count == 8 {
             red = CGFloat((rgbValue & 0xFF000000) >> 24) / 255.0
             green = CGFloat((rgbValue & 0x00FF0000) >> 16) / 255.0
             blue = CGFloat((rgbValue & 0x0000FF00) >> 8) / 255.0
             alpha = CGFloat(rgbValue & 0x000000FF) / 255.0
         } else {
             return nil
         }
         
         self.init(red: red, green: green, blue: blue, alpha: alpha)
     }
 }







 struct CommentAnnotation {
     let documentURL: String
     let annotationID: String
     let type: String
     let senderEmail: String
     let content: String
     let bounds: [String: CGFloat]
     
 }
 */





















/*
 import SwiftUI
 import FirebaseAuth
 import FirebaseFirestore
 import PDFKit
 import UIKit
 import Firebase
 import AVFoundation

 class CustomPDFAnnotation: PDFAnnotation {
     var annotationID: String?
 }

 struct PageAnnotation {
     let annotation: PDFAnnotation
     let pageIndex: Int
 }


 public struct DocumentView: View {
     let documentURL: URL
     @State private var showChatDrawer = false
     @State private var showCommentDrawer = false
     @State private var commentMessages: [CommentMessage] = [] // Store comment messages
     @State private var commentText: String?
     @State private var isAddingComment = false // Track if a comment is being added
     @State private var selectedAnnotationType: PDFAnnotationSubtype? // Track the selected annotation type
     @State private var chatMessages: [ChatMessage] = [] // Store chat messages
     @State private var commentAnnotations: [CommentAnnotation] = [] // Store comment annotations
     @State private var selectedAnnotation: PDFAnnotation? // Store the selected annotation
     @State private var selectedOnDocumentAnnotation: CustomPDFAnnotation? // Store the selected annotation on the document
     @State private var isTyping = false // Track if the user is typing
     @State private var pdfView: PDFView? // Store the PDF view
     @State private var fontColor: Color = .black // Store the font color
     @State private var showDeleteButton: Bool = false // Track whether to show the delete button
     @State private var isBold: Bool = false // Track if the text is bold
     @State private var isItalic: Bool = false // Track if the text is italic
     @State private var fontSize: CGFloat = 16 // Store the selected font size
     let availableFontSizes: [CGFloat] = [8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32]
     @Environment(\.colorScheme) var colorScheme
     
     // Gesture-related states for highlighting annotations
     @State private var firstTouchLocation: CGPoint?
     @State private var secondTouchLocation: CGPoint?
     @State private var isHighlighting: Bool = false
     @State private var highlightAnnotations: [PDFAnnotation] = []
     @State private var lastSynthesisPosition: Int = 0 // Track last synthesis position here

     public var body: some View {
         VStack {
             PDFViewWrapper(url: documentURL, handleTapGesture: handleTapGesture, isHighlighting: $isHighlighting)
                 .onTapGesture {
                     
                 }
         }
         .overlay(
             VStack {
                 Spacer()
                 HStack {
                     Spacer()
                     Button(action: {
                         showChatDrawer.toggle()
                     }) {
                         Image(systemName: "message.fill")
                             .resizable()
                             .frame(width: 20, height: 20)
                             .padding()
                             .background(Color.blue)
                             .foregroundColor(.white)
                             .clipShape(Circle())
                     }
                     .padding(.trailing)
                 }
             }
                 .padding()
         )
         
         .navigationBarItems(
             trailing:
                 HStack {
                     AnnotationToolbar(selectedAnnotationType: $selectedAnnotationType, isAddingComment: $isAddingComment, commentText: $commentText, showCommentDrawer: $showCommentDrawer, isTyping: $isTyping, fontColor: $fontColor, showDeleteButton: $showDeleteButton, isBold: $isBold, isItalic: $isItalic, fontSize: $fontSize, deleteAction: deleteAnnotation, availableFontSizes: availableFontSizes, isHighlighting: $isHighlighting, documentURL: documentURL, lastSynthesisPosition: $lastSynthesisPosition)
                    // Spacer()
                 }
         )
         .sheet(isPresented: $showCommentDrawer) {
             CommentDrawerView(commentMessages: $commentMessages, documentURL: documentURL, commentText: $commentText, isAddingComment: $isAddingComment, selectedAnnotation: $selectedAnnotation, saveCommentAnnotation: saveCommentAnnotation, showCommentDrawer: $showCommentDrawer)
         }
         .sheet(isPresented: $showChatDrawer) {
             ChatDrawerView(chatMessages: $chatMessages, documentURL: documentURL, commentText: $commentText)
         }
         .onAppear {
             fetchOnDocumentComment(documentURL: documentURL)
             fetchCommentAnnotations(documentURL: documentURL)
             fetchCommentMessages(documentURL: documentURL) { fetchedCommentMessages in
                 commentMessages = fetchedCommentMessages
             }
             fetchHighlightAnnotations(documentURL: documentURL)
         }
     }
     
     func handleTapGesture(location: CGPoint) {
         if let pdfView = PDFViewWrapper.pdfView,
            let currentPage = pdfView.currentPage {
             let tapLocation = pdfView.convert(location, to: currentPage)
             
             if let tappedAnnotation = currentPage.annotation(at: tapLocation) {
                 
                 if let customAnnotation = tappedAnnotation as? CustomPDFAnnotation {
                     selectedOnDocumentAnnotation = customAnnotation
                     showDeleteButton = true
                     //   isTyping = false
                 }
                 else if let pdfAnnotation = tappedAnnotation as? PDFAnnotation{
                     showCommentDrawer = true
                 }
             }
             else {
                 showDeleteButton = false
             }
             if isAddingComment {
                 let textAnnotation = PDFAnnotation(bounds: CGRect(x: tapLocation.x, y: tapLocation.y, width: 30, height: 30), forType: .freeText, withProperties: nil)
                 textAnnotation.contents = "\(commentMessages.count + 1)" // Calculate the comment count and set it as the annotation content
                 textAnnotation.font = UIFont.boldSystemFont(ofSize: 20) // Adjust the font size if needed
                 textAnnotation.color = .yellow.withAlphaComponent(0.2)
                 textAnnotation.fontColor = .red
                 textAnnotation.alignment = .center
                 
                 selectedAnnotation = textAnnotation
                 
                 // Open the CommentDrawerView
                 showCommentDrawer = true
             }
             else if isTyping {
                 if firstTouchLocation == nil {
                     firstTouchLocation = location
                 }
                 else if secondTouchLocation == nil {
                     secondTouchLocation = location
                     createOnDocumentAnnotation()
                 }
                 
             }
         }
     }


     
     func deleteAnnotation() {
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
                 
             }
         }
         
         
         
         showDeleteButton = false
     }
     

     
     func createOnDocumentAnnotation() {
         guard let firstTouchLocation = firstTouchLocation,
               let secondTouchLocation = secondTouchLocation,
               let pdfView = PDFViewWrapper.pdfView,
               let tappedPage = pdfView.page(for: firstTouchLocation, nearest: true) else {
             return
         }
         
         
         let convertedFirstLocation = pdfView.convert(firstTouchLocation, to: tappedPage)
         let convertedSecondLocation = pdfView.convert(secondTouchLocation, to: tappedPage)
         
         
         let width: CGFloat
         let height: CGFloat
         
         width = abs(convertedSecondLocation.x - convertedFirstLocation.x)
         height = abs(convertedFirstLocation.y - convertedSecondLocation.y)
         
         // User tapped to create a new annotation
         let bounds = CGRect(x: convertedFirstLocation.x , y: convertedSecondLocation.y , width: width, height: height)
         let freeTextAnnotation = CustomPDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
         
         // Set the appearance characteristics of the free text annotation
         let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
         
         var traits = getFontSymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         let updatedFontDescriptor = fontDescriptor.withSymbolicTraits(traits) ?? fontDescriptor
         
         let font = UIFont(descriptor: updatedFontDescriptor, size: fontSize)
         
         freeTextAnnotation.font = font
         freeTextAnnotation.fontColor = UIColor(fontColor)
         freeTextAnnotation.contents = "" // Set the initial text content to an empty string
         freeTextAnnotation.color = .black.withAlphaComponent(0.2)
         
         // Add the annotation to the current page
         tappedPage.addAnnotation(freeTextAnnotation)
         
         // Create a label for the annotation text
         let annotationLabel = UILabel(frame: bounds)
         annotationLabel.textAlignment = .center
         annotationLabel.font = font
         annotationLabel.textColor = freeTextAnnotation.fontColor
         annotationLabel.text = freeTextAnnotation.contents
         annotationLabel.backgroundColor = .clear
         pdfView.addSubview(annotationLabel)
         
         // Create the text field positioned at the top of the screen
         let textField = UITextField(frame: CGRect(x: 0, y: 0, width: pdfView.bounds.width, height: 40))
         textField.backgroundColor = .gray
         textField.font = font
         textField.textColor = UIColor(fontColor)
         textField.placeholder = "Type here"
         textField.borderStyle = .roundedRect
         
         // Create the "Send" button
         let sendButton = UIButton(type: .system)
         sendButton.setTitle("Send", for: .normal)
         sendButton.sizeToFit()
         
         // Add a closure to execute when the button is tapped
         sendButton.addAction(UIAction { _ in
             self.sendButtonTapped()
         }, for: .touchUpInside)
         
         // Create a toolbar view to hold the button
         let toolbarView = UIToolbar(frame: CGRect(x: 0, y: 0, width: pdfView.bounds.width, height: 44))
         
         // Create a flexible space item to push the button to the right
         let flexibleSpaceItem = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
         
         // Create a bar button item with the send button
         let sendBarButtonItem = UIBarButtonItem(customView: sendButton)
         
         // Add the flexible space item and the send button item to the toolbar
         toolbarView.items = [flexibleSpaceItem, sendBarButtonItem]
         
         // Set the toolbar view as the input accessory view of the text field
         textField.inputAccessoryView = toolbarView
         
         tappedPage.addAnnotation(freeTextAnnotation)
         pdfView.addSubview(annotationLabel)
         pdfView.addSubview(textField)
         
         // Set the selectedAnnotation to the created free text annotation
         selectedOnDocumentAnnotation = freeTextAnnotation
         
         let annotationID = UUID().uuidString
         selectedOnDocumentAnnotation!.annotationID = annotationID
         
         pdfView.becomeFirstResponder()
         isTyping = false
         
     }
     
     
     public func getFontSymbolicTraits() -> UIFontDescriptor.SymbolicTraits {
         var traits = UIFontDescriptor.SymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         return traits
     }
     
     
     func sendButtonTapped() {
         guard let pdfView = PDFViewWrapper.pdfView,
               let textField = pdfView.subviews.first(where: { $0 is UITextField }) as? UITextField,
               let selectedOnDocumentAnnotation = selectedOnDocumentAnnotation as? CustomPDFAnnotation else {
             return
         }
         
         selectedOnDocumentAnnotation.contents = textField.text ?? ""
         
         var traits = getFontSymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         
         let currentFontSize = selectedOnDocumentAnnotation.font?.pointSize ?? 16
         let resizedFontDescriptor = selectedOnDocumentAnnotation.font?.fontDescriptor.withSymbolicTraits(traits)
         let resizedFont = UIFont(descriptor: resizedFontDescriptor ?? UIFontDescriptor(), size: currentFontSize)
         
         selectedOnDocumentAnnotation.font = resizedFont
         
         textField.resignFirstResponder() // Hide the keyboard
         textField.removeFromSuperview() // Remove the textField from its superview
         
         if let freeTextAnnotation = selectedOnDocumentAnnotation as? CustomPDFAnnotation {
             saveOnDocumentComment(freeTextAnnotation, documentURL: documentURL, isBold: isBold, isItalic: isItalic, fontSize: fontSize, fontColor: fontColor, location: firstTouchLocation!)
         }
         isTyping = false
         showDeleteButton = false
         // Trigger a re-draw of the PDF view to reflect the updated annotation appearance
         pdfView.setNeedsDisplay()
         
         //   fetchOnDocumentComment(documentURL: documentURL)
         
         // Reset touch locations for future highlights
         self.firstTouchLocation = nil
         self.secondTouchLocation = nil

     }
 }


 extension UIColor {
     convenience init?(hexString: String) {
         var hexFormatted = hexString.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
         hexFormatted = hexFormatted.replacingOccurrences(of: "#", with: "")
         
         var rgbValue: UInt64 = 0
         Scanner(string: hexFormatted).scanHexInt64(&rgbValue)
         
         var alpha, red, green, blue: CGFloat
         if hexFormatted.count == 6 {
             red = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
             green = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
             blue = CGFloat(rgbValue & 0x0000FF) / 255.0
             alpha = 1.0
         } else if hexFormatted.count == 8 {
             red = CGFloat((rgbValue & 0xFF000000) >> 24) / 255.0
             green = CGFloat((rgbValue & 0x00FF0000) >> 16) / 255.0
             blue = CGFloat((rgbValue & 0x0000FF00) >> 8) / 255.0
             alpha = CGFloat(rgbValue & 0x000000FF) / 255.0
         } else {
             return nil
         }
         
         self.init(red: red, green: green, blue: blue, alpha: alpha)
     }
 }







 struct CommentAnnotation {
     let documentURL: String
     let annotationID: String
     let type: String
     let senderEmail: String
     let content: String
     let bounds: [String: CGFloat]
     
 }
 */
