import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import PDFKit
import UIKit
import Firebase

class CustomPDFAnnotation: PDFAnnotation {
    var annotationID: String?
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
    
    
    
    public var body: some View {
        VStack {
            PDFViewWrapper(url: documentURL, handleTapGesture: handleTapGesture)
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
                    AnnotationToolbar(selectedAnnotationType: $selectedAnnotationType, isAddingComment: $isAddingComment, commentText: $commentText, showCommentDrawer: $showCommentDrawer, isTyping: $isTyping, fontColor: $fontColor, showDeleteButton: $showDeleteButton, isBold: $isBold, isItalic: $isItalic, fontSize: $fontSize, deleteAction: deleteAnnotation, availableFontSizes: availableFontSizes, isHighlighting: $isHighlighting, documentURL: documentURL)
                    Spacer()
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
                // Use the fetched comment messages here
                // You can assign them to a variable, update the UI, or perform any other necessary operations
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
            if isHighlighting {
                if firstTouchLocation == nil {
                    firstTouchLocation = location
                } else if secondTouchLocation == nil {
                    secondTouchLocation = location
                    createHighlightAnnotation(firstTouchLocation: &firstTouchLocation, secondTouchLocation: &secondTouchLocation, pdfView: pdfView, documentURL: documentURL)
                }
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
        freeTextAnnotation.color = .black.withAlphaComponent(0.5)
        
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





/*
 import SwiftUI
 import FirebaseAuth
 import FirebaseFirestore
 import PDFKit
 import UIKit
 import Firebase

 class CustomPDFAnnotation: PDFAnnotation {
     var annotationID: String?
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
     
     
     
     public var body: some View {
         VStack {
             PDFViewWrapper(url: documentURL, handleTapGesture: handleTapGesture)
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
                     AnnotationToolbar(selectedAnnotationType: $selectedAnnotationType, isAddingComment: $isAddingComment, commentText: $commentText, showCommentDrawer: $showCommentDrawer, isTyping: $isTyping, fontColor: $fontColor, showDeleteButton: $showDeleteButton, isBold: $isBold, isItalic: $isItalic, fontSize: $fontSize, deleteAction: deleteAnnotation, availableFontSizes: availableFontSizes, isHighlighting: $isHighlighting, documentURL: documentURL)
                     Spacer()
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
                 // Use the fetched comment messages here
                 // You can assign them to a variable, update the UI, or perform any other necessary operations
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
             if isHighlighting {
                 if firstTouchLocation == nil {
                     firstTouchLocation = location
                 } else if secondTouchLocation == nil {
                     secondTouchLocation = location
                     createHighlightAnnotation(firstTouchLocation: &firstTouchLocation, secondTouchLocation: &secondTouchLocation, pdfView: pdfView, documentURL: documentURL)
                 }
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
         freeTextAnnotation.color = .black.withAlphaComponent(0.5)
         
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
