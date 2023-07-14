import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import PDFKit
import UIKit


class CustomPDFAnnotation: PDFAnnotation {
    var annotationID: String?
}

public struct DocumentView: View {
    let documentURL: URL
    @State private var showChatDrawer = false
    @State private var showCommentDrawer = false
    @State private var commentMessages: [CommentMessage] = [] // Store comment messages
    @State private var commentText: String?
    @State private var isAddingComment = false // Add isAddingComment state
    @State private var selectedAnnotationType: PDFAnnotationSubtype? // Add selectedAnnotationType state
    @State private var chatMessages: [ChatMessage] = [] // Store chat messages
    @State private var commentAnnotations: [CommentAnnotation] = [] // Store comment annotations
    @State private var selectedAnnotation: PDFAnnotation? // Store the selected annotation
    @State private var selectedOnDocumentAnnotation: CustomPDFAnnotation? // Store the selected annotation
    @State private var isTyping = false // Add isTyping state
    @State private var pdfView: PDFView? // Add pdfView property
    @State private var fontColor: Color = .black // Add a state variable to store the font color
    @State private var showDeleteButton: Bool = false // Track whether to show the delete button
    @State private var isBold: Bool = false // Track whether the text is bold
    @State private var isItalic: Bool = false // Track whether the text is italic
    @State private var fontSize: CGFloat = 16 // Track the selected font size
    let availableFontSizes: [CGFloat] = [8, 10, 12, 14, 16,18, 20, 22, 24, 26, 28, 30, 32]
    @Environment(\.colorScheme) var colorScheme
    
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
                            .frame(width: 32, height: 32)
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
            CommentDrawerView(commentMessages: $commentMessages, documentURL: documentURL, commentText: $commentText, isAddingComment: $isAddingComment, selectedAnnotation: $selectedAnnotation, saveCommentAnnotation: saveCommentAnnotation)
        }
        .sheet(isPresented: $showChatDrawer) {
            ChatDrawerView(chatMessages: $chatMessages, documentURL: documentURL, commentText: $commentText)
        }
        .onAppear {
            fetchOnDocumentComment(documentURL: documentURL)
            fetchCommentAnnotations(documentURL: documentURL)
            fetchCommentMessages()
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
                    createHighlightAnnotation()
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
    
    func createHighlightAnnotation() {

        guard let firstTouchLocation = firstTouchLocation,
              let secondTouchLocation = secondTouchLocation,
              let pdfView = PDFViewWrapper.pdfView,
              let tappedPage = pdfView.page(for: firstTouchLocation, nearest: true)
        else {
            return
        }
        
        let convertedFirstLocation = pdfView.convert(firstTouchLocation, to: tappedPage)
        let convertedSecondLocation = pdfView.convert(secondTouchLocation, to: tappedPage)
        
        let width: CGFloat
        
        width = abs(convertedSecondLocation.x - convertedFirstLocation.x)
        
        let minY = min(convertedFirstLocation.y, convertedSecondLocation.y)
        let highlightBounds = CGRect(x: convertedFirstLocation.x, y: minY, width: width, height: 10)
        
        let highlightAnnotation = CustomPDFAnnotation(bounds: highlightBounds, forType: .highlight, withProperties: nil)
        tappedPage.addAnnotation(highlightAnnotation)

        
        // Reset touch locations for future highlights
        self.firstTouchLocation = nil
        self.secondTouchLocation = nil
        self.selectedOnDocumentAnnotation = highlightAnnotation

        let annotationID = UUID().uuidString
        selectedOnDocumentAnnotation!.annotationID = annotationID
        
        // Save the highlight annotation to Firestore
        saveHighlightAnnotation(highlightAnnotation, documentURL: documentURL, location: firstTouchLocation)
        //  fetchHighlightAnnotations(documentURL: documentURL)  //check if needed
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


struct ColorButton: View {
    var color: Color
    var isSelected: Bool
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
        }
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


 class CustomPDFAnnotation: PDFAnnotation {
     var annotationID: String?
 }

 public struct DocumentView: View {
     let documentURL: URL
     @State private var showChatDrawer = false
     @State private var showCommentDrawer = false
     @State private var commentMessages: [CommentMessage] = [] // Store comment messages
     @State private var commentText: String?
     @State private var isAddingComment = false // Add isAddingComment state
     @State private var selectedAnnotationType: PDFAnnotationSubtype? // Add selectedAnnotationType state
     @State private var chatMessages: [ChatMessage] = [] // Store chat messages
     @State private var commentAnnotations: [CommentAnnotation] = [] // Store comment annotations
     @State private var selectedAnnotation: PDFAnnotation? // Store the selected annotation
     @State private var selectedOnDocumentAnnotation: CustomPDFAnnotation? // Store the selected annotation
     @State private var isTyping = false // Add isTyping state
     @State private var pdfView: PDFView? // Add pdfView property
     @State private var fontColor: Color = .black // Add a state variable to store the font color
     @State private var showDeleteButton: Bool = false // Track whether to show the delete button
     @State private var isBold: Bool = false // Track whether the text is bold
     @State private var isItalic: Bool = false // Track whether the text is italic
     @State private var fontSize: CGFloat = 16 // Track the selected font size
     let availableFontSizes: [CGFloat] = [8, 10, 12, 14, 16,18, 20, 22, 24, 26, 28, 30, 32]
     @Environment(\.colorScheme) var colorScheme
     
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
                             .frame(width: 32, height: 32)
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
             CommentDrawerView(commentMessages: $commentMessages, documentURL: documentURL, commentText: $commentText, isAddingComment: $isAddingComment, selectedAnnotation: $selectedAnnotation, saveCommentAnnotation: saveCommentAnnotation)
         }
         .sheet(isPresented: $showChatDrawer) {
             ChatDrawerView(chatMessages: $chatMessages, documentURL: documentURL, commentText: $commentText)
         }
         .onAppear {
             fetchOnDocumentComment(documentURL: documentURL)
             fetchCommentAnnotations(documentURL: documentURL)
             fetchCommentMessages()
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
                     createHighlightAnnotation()
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
     
     func createHighlightAnnotation() {

         guard let firstTouchLocation = firstTouchLocation,
               let secondTouchLocation = secondTouchLocation,
               let pdfView = PDFViewWrapper.pdfView,
               let tappedPage = pdfView.page(for: firstTouchLocation, nearest: true)
         else {
             return
         }
         
         let convertedFirstLocation = pdfView.convert(firstTouchLocation, to: tappedPage)
         let convertedSecondLocation = pdfView.convert(secondTouchLocation, to: tappedPage)
         
         let width: CGFloat
         
         width = abs(convertedSecondLocation.x - convertedFirstLocation.x)
         
         let minY = min(convertedFirstLocation.y, convertedSecondLocation.y)
         let highlightBounds = CGRect(x: convertedFirstLocation.x, y: minY, width: width, height: 10)
         
         let highlightAnnotation = CustomPDFAnnotation(bounds: highlightBounds, forType: .highlight, withProperties: nil)
         tappedPage.addAnnotation(highlightAnnotation)

         
         // Reset touch locations for future highlights
         self.firstTouchLocation = nil
         self.secondTouchLocation = nil
         self.selectedOnDocumentAnnotation = highlightAnnotation

         let annotationID = UUID().uuidString
         selectedOnDocumentAnnotation!.annotationID = annotationID
         
         // Save the highlight annotation to Firestore
         saveHighlightAnnotation(highlightAnnotation, documentURL: documentURL, location: firstTouchLocation)
         //  fetchHighlightAnnotations(documentURL: documentURL)  //check if needed
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


 struct ColorButton: View {
     var color: Color
     var isSelected: Bool
     var action: () -> Void
     
     var body: some View {
         Button(action: action) {
             ZStack {
                 Circle()
                     .fill(color)
                     .frame(width: 5, height: 5)
                 
                 if isSelected {
                     Image(systemName: "checkmark.circle.fill")
                         .foregroundColor(.white)
                 }
             }
         }
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


 class CustomPDFAnnotation: PDFAnnotation {
     var annotationID: String?
 }

 public struct DocumentView: View {
     let documentURL: URL
     @State private var showChatDrawer = false
     @State private var showCommentDrawer = false
     @State private var commentMessages: [CommentMessage] = [] // Store comment messages
     @State private var commentText: String?
     @State private var isAddingComment = false // Add isAddingComment state
     @State private var selectedAnnotationType: PDFAnnotationSubtype? // Add selectedAnnotationType state
     @State private var chatMessages: [ChatMessage] = [] // Store chat messages
     @State private var commentAnnotations: [CommentAnnotation] = [] // Store comment annotations
     @State private var selectedAnnotation: PDFAnnotation? // Store the selected annotation
     @State private var selectedOnDocumentAnnotation: CustomPDFAnnotation? // Store the selected annotation
     @State private var isTyping = false // Add isTyping state
     @State private var pdfView: PDFView? // Add pdfView property
     @State private var fontColor: Color = .black // Add a state variable to store the font color
     @State private var showDeleteButton: Bool = false // Track whether to show the delete button
     @State private var isBold: Bool = false // Track whether the text is bold
     @State private var isItalic: Bool = false // Track whether the text is italic
     @State private var fontSize: CGFloat = 16 // Track the selected font size
     let availableFontSizes: [CGFloat] = [8, 10, 12, 14, 16,18, 20, 22, 24, 26, 28, 30, 32]
     @Environment(\.colorScheme) var colorScheme
     
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
                             .frame(width: 32, height: 32)
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
             CommentDrawerView(commentMessages: $commentMessages, documentURL: documentURL, commentText: $commentText, isAddingComment: $isAddingComment, selectedAnnotation: $selectedAnnotation, saveCommentAnnotation: saveCommentAnnotation)
         }
         .sheet(isPresented: $showChatDrawer) {
             ChatDrawerView(chatMessages: $chatMessages, documentURL: documentURL, commentText: $commentText)
         }
         .onAppear {
             fetchOnDocumentComment(documentURL: documentURL)
             fetchCommentAnnotations(documentURL: documentURL)
             fetchCommentMessages()
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
                     createHighlightAnnotation()
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
     
     
     func createHighlightAnnotation() {
         guard let firstTouchLocation = firstTouchLocation,
               let secondTouchLocation = secondTouchLocation,
               let pdfView = PDFViewWrapper.pdfView,
               let tappedPage = pdfView.page(for: firstTouchLocation, nearest: true) else {
             return
         }
         
         let convertedFirstLocation = pdfView.convert(firstTouchLocation, to: tappedPage)
         let convertedSecondLocation = pdfView.convert(secondTouchLocation, to: tappedPage)
         
         let width: CGFloat
         
         width = abs(convertedSecondLocation.x - convertedFirstLocation.x)
         
         let minY = min(convertedFirstLocation.y, convertedSecondLocation.y)
         let highlightBounds = CGRect(x: convertedFirstLocation.x, y: minY, width: width, height: 10)
         
         let highlightAnnotation = CustomPDFAnnotation(bounds: highlightBounds, forType: .highlight, withProperties: nil)
         tappedPage.addAnnotation(highlightAnnotation)
         
         // Reset touch locations for future highlights
         self.firstTouchLocation = nil
         self.secondTouchLocation = nil
         
         
         // Save the highlight annotation to Firestore
         saveHighlightAnnotation(highlightAnnotation, documentURL: documentURL, location: firstTouchLocation)
         //  fetchHighlightAnnotations(documentURL: documentURL)  //check if needed
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
         pdfView.becomeFirstResponder()
         isTyping = false

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
     
     func deleteAnnotation() {
         guard let pdfView = PDFViewWrapper.pdfView,
               let selectedOnDocumentAnnotation = selectedOnDocumentAnnotation,
               let annotationID = selectedOnDocumentAnnotation.annotationID else {
             return
         }
         print("Hello1")
         
         // Remove the annotation from the PDF view
         if let currentPage = pdfView.currentPage {
             print("Hello2")
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


 struct ColorButton: View {
     var color: Color
     var isSelected: Bool
     var action: () -> Void
     
     var body: some View {
         Button(action: action) {
             ZStack {
                 Circle()
                     .fill(color)
                     .frame(width: 5, height: 5)
                 
                 if isSelected {
                     Image(systemName: "checkmark.circle.fill")
                         .foregroundColor(.white)
                 }
             }
         }
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


 class CustomPDFAnnotation: PDFAnnotation {
     var annotationID: String?
 }

 public struct DocumentView: View {
     let documentURL: URL
     @State private var showChatDrawer = false
     @State private var showCommentDrawer = false
     @State private var commentMessages: [CommentMessage] = [] // Store comment messages
     @State private var commentText: String?
     @State private var isAddingComment = false // Add isAddingComment state
     @State private var selectedAnnotationType: PDFAnnotationSubtype? // Add selectedAnnotationType state
     @State private var chatMessages: [ChatMessage] = [] // Store chat messages
     @State private var commentAnnotations: [CommentAnnotation] = [] // Store comment annotations
     @State private var selectedAnnotation: PDFAnnotation? // Store the selected annotation
     @State private var selectedOnDocumentAnnotation: CustomPDFAnnotation? // Store the selected annotation
     @State private var isTyping = false // Add isTyping state
     @State private var pdfView: PDFView? // Add pdfView property
     @State private var fontColor: Color = .black // Add a state variable to store the font color
     @State private var showDeleteButton: Bool = false // Track whether to show the delete button
     @State private var isBold: Bool = false // Track whether the text is bold
     @State private var isItalic: Bool = false // Track whether the text is italic
     @State private var fontSize: CGFloat = 16 // Track the selected font size
     let availableFontSizes: [CGFloat] = [8, 10, 12, 14, 16,18, 20, 22, 24, 26, 28, 30, 32]
     @Environment(\.colorScheme) var colorScheme
     
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
                             .frame(width: 32, height: 32)
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
             CommentDrawerView(commentMessages: $commentMessages, documentURL: documentURL, commentText: $commentText, isAddingComment: $isAddingComment, selectedAnnotation: $selectedAnnotation, saveCommentAnnotation: saveCommentAnnotation)
         }
         .sheet(isPresented: $showChatDrawer) {
             ChatDrawerView(chatMessages: $chatMessages, documentURL: documentURL, commentText: $commentText)
         }
         .onAppear {
             fetchOnDocumentComment(documentURL: documentURL)
             fetchCommentAnnotations(documentURL: documentURL)
             fetchCommentMessages()
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
                     createHighlightAnnotation()
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
     
     
     func createHighlightAnnotation() {
         guard let firstTouchLocation = firstTouchLocation,
               let secondTouchLocation = secondTouchLocation,
               let pdfView = PDFViewWrapper.pdfView,
               let tappedPage = pdfView.page(for: firstTouchLocation, nearest: true) else {
             return
         }
         
         let convertedFirstLocation = pdfView.convert(firstTouchLocation, to: tappedPage)
         let convertedSecondLocation = pdfView.convert(secondTouchLocation, to: tappedPage)
         
         let width: CGFloat
         
         width = abs(convertedSecondLocation.x - convertedFirstLocation.x)
         
         let minY = min(convertedFirstLocation.y, convertedSecondLocation.y)
         let highlightBounds = CGRect(x: convertedFirstLocation.x, y: minY, width: width, height: 10)
         
         let highlightAnnotation = CustomPDFAnnotation(bounds: highlightBounds, forType: .highlight, withProperties: nil)
         tappedPage.addAnnotation(highlightAnnotation)
         
         // Reset touch locations for future highlights
         self.firstTouchLocation = nil
         self.secondTouchLocation = nil
         
         
         // Save the highlight annotation to Firestore
         saveHighlightAnnotation(highlightAnnotation, documentURL: documentURL, location: firstTouchLocation)
         //  fetchHighlightAnnotations(documentURL: documentURL)  //check if needed
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
         selectedAnnotation = freeTextAnnotation
         pdfView.becomeFirstResponder()
         isTyping = false
         
     }
     
     func sendButtonTapped() {
         guard let pdfView = PDFViewWrapper.pdfView,
               let textField = pdfView.subviews.first(where: { $0 is UITextField }) as? UITextField,
               let selectedAnnotation = selectedAnnotation as? PDFAnnotation else {
             return
         }
         
         selectedAnnotation.contents = textField.text ?? ""
         
         var traits = getFontSymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         
         let currentFontSize = selectedAnnotation.font?.pointSize ?? 16
         let resizedFontDescriptor = selectedAnnotation.font?.fontDescriptor.withSymbolicTraits(traits)
         let resizedFont = UIFont(descriptor: resizedFontDescriptor ?? UIFontDescriptor(), size: currentFontSize)
         
         selectedAnnotation.font = resizedFont
         
         textField.resignFirstResponder() // Hide the keyboard
         textField.removeFromSuperview() // Remove the textField from its superview
         
         if let freeTextAnnotation = selectedAnnotation as? CustomPDFAnnotation {
             saveOnDocumentComment(freeTextAnnotation, documentURL: documentURL, isBold: isBold, isItalic: isItalic, fontSize: fontSize, fontColor: fontColor, location: firstTouchLocation!)
         }
         isTyping = false
         showDeleteButton = false
         // Trigger a re-draw of the PDF view to reflect the updated annotation appearance
         pdfView.setNeedsDisplay()
         
         //   fetchOnDocumentComment(documentURL: documentURL)
         
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
     
     func deleteAnnotation() {
         guard let pdfView = PDFViewWrapper.pdfView,
               let selectedOnDocumentAnnotation = selectedOnDocumentAnnotation,
               let annotationID = selectedOnDocumentAnnotation.annotationID else {
             return
         }
         print("Hello1")
         
         // Remove the annotation from the PDF view
         if let currentPage = pdfView.currentPage {
             print("Hello2")
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





 struct ColorButton: View {
     var color: Color
     var isSelected: Bool
     var action: () -> Void
     
     var body: some View {
         Button(action: action) {
             ZStack {
                 Circle()
                     .fill(color)
                     .frame(width: 5, height: 5)
                 
                 if isSelected {
                     Image(systemName: "checkmark.circle.fill")
                         .foregroundColor(.white)
                 }
             }
         }
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


 class CustomPDFAnnotation: PDFAnnotation {
     var annotationID: String?
 }

 public struct DocumentView: View {
     let documentURL: URL
     @State private var showChatDrawer = false
     @State private var showCommentDrawer = false
     @State private var commentMessages: [CommentMessage] = [] // Store comment messages
     @State private var commentText: String?
     @State private var isAddingComment = false // Add isAddingComment state
     @State private var selectedAnnotationType: PDFAnnotationSubtype? // Add selectedAnnotationType state
     @State private var chatMessages: [ChatMessage] = [] // Store chat messages
     @State private var commentAnnotations: [CommentAnnotation] = [] // Store comment annotations
     @State private var selectedAnnotation: PDFAnnotation? // Store the selected annotation
     @State private var selectedOnDocumentAnnotation: CustomPDFAnnotation? // Store the selected annotation
     @State private var isTyping = false // Add isTyping state
     @State private var pdfView: PDFView? // Add pdfView property
     @State private var fontColor: Color = .black // Add a state variable to store the font color
     @State private var showDeleteButton: Bool = false // Track whether to show the delete button
     @State private var isBold: Bool = false // Track whether the text is bold
     @State private var isItalic: Bool = false // Track whether the text is italic
     @State private var fontSize: CGFloat = 16 // Track the selected font size
     let availableFontSizes: [CGFloat] = [8, 10, 12, 14, 16,18, 20, 22, 24, 26, 28, 30, 32]
     @Environment(\.colorScheme) var colorScheme
     
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
                             .frame(width: 32, height: 32)
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
             CommentDrawerView(commentMessages: $commentMessages, documentURL: documentURL, commentText: $commentText, isAddingComment: $isAddingComment, selectedAnnotation: $selectedAnnotation, saveCommentAnnotation: saveCommentAnnotation)
         }
         .sheet(isPresented: $showChatDrawer) {
             ChatDrawerView(chatMessages: $chatMessages, documentURL: documentURL, commentText: $commentText)
         }
         .onAppear {
             fetchOnDocumentComment(documentURL: documentURL)
             fetchCommentAnnotations(documentURL: documentURL)
             fetchCommentMessages()
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
                     createHighlightAnnotation()
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
     
     
     func createHighlightAnnotation() {
         guard let firstTouchLocation = firstTouchLocation,
               let secondTouchLocation = secondTouchLocation,
               let pdfView = PDFViewWrapper.pdfView,
               let tappedPage = pdfView.page(for: firstTouchLocation, nearest: true) else {
             return
         }
         
         let convertedFirstLocation = pdfView.convert(firstTouchLocation, to: tappedPage)
         let convertedSecondLocation = pdfView.convert(secondTouchLocation, to: tappedPage)
         
         let width: CGFloat
         
         width = abs(convertedSecondLocation.x - convertedFirstLocation.x)
         
         let minY = min(convertedFirstLocation.y, convertedSecondLocation.y)
         let highlightBounds = CGRect(x: convertedFirstLocation.x, y: minY, width: width, height: 10)
         
         let highlightAnnotation = CustomPDFAnnotation(bounds: highlightBounds, forType: .highlight, withProperties: nil)
         tappedPage.addAnnotation(highlightAnnotation)
         
         // Reset touch locations for future highlights
         self.firstTouchLocation = nil
         self.secondTouchLocation = nil
         
         
         // Save the highlight annotation to Firestore
         saveHighlightAnnotation(highlightAnnotation, documentURL: documentURL)
         fetchHighlightAnnotations(documentURL: documentURL)  //check if needed
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
         selectedAnnotation = freeTextAnnotation
         pdfView.becomeFirstResponder()
         isTyping = false
         
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


     
     func sendButtonTapped() {
         guard let pdfView = PDFViewWrapper.pdfView,
               let textField = pdfView.subviews.first(where: { $0 is UITextField }) as? UITextField,
               let selectedAnnotation = selectedAnnotation as? PDFAnnotation else {
             return
         }
         
         selectedAnnotation.contents = textField.text ?? ""
         
         var traits = getFontSymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         
         let currentFontSize = selectedAnnotation.font?.pointSize ?? 16
         let resizedFontDescriptor = selectedAnnotation.font?.fontDescriptor.withSymbolicTraits(traits)
         let resizedFont = UIFont(descriptor: resizedFontDescriptor ?? UIFontDescriptor(), size: currentFontSize)
         
         selectedAnnotation.font = resizedFont
         
         textField.resignFirstResponder() // Hide the keyboard
         textField.removeFromSuperview() // Remove the textField from its superview
         
         if let freeTextAnnotation = selectedAnnotation as? CustomPDFAnnotation {
             saveOnDocumentComment(freeTextAnnotation, documentURL: documentURL, isBold: isBold, isItalic: isItalic, fontSize: fontSize, fontColor: fontColor)
         }
         isTyping = false
         showDeleteButton = false
         // Trigger a re-draw of the PDF view to reflect the updated annotation appearance
         pdfView.setNeedsDisplay()
         
         fetchOnDocumentComment(documentURL: documentURL)
         
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
     
     func deleteAnnotation() {
         guard let pdfView = PDFViewWrapper.pdfView,
               let selectedOnDocumentAnnotation = selectedOnDocumentAnnotation,
               let annotationID = selectedOnDocumentAnnotation.annotationID else {
             return
         }
         print("Hello1")

         // Remove the annotation from the PDF view
         if let currentPage = pdfView.currentPage {
             print("Hello2")
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





 struct ColorButton: View {
     var color: Color
     var isSelected: Bool
     var action: () -> Void
     
     var body: some View {
         Button(action: action) {
             ZStack {
                 Circle()
                     .fill(color)
                     .frame(width: 5, height: 5)
                 
                 if isSelected {
                     Image(systemName: "checkmark.circle.fill")
                         .foregroundColor(.white)
                 }
             }
         }
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


 class CustomPDFAnnotation: PDFAnnotation {
     var annotationID: String?
 }




 public struct DocumentView: View {
     let documentURL: URL
     @State private var showChatDrawer = false
     @State private var showCommentDrawer = false
     @State private var commentMessages: [CommentMessage] = [] // Store comment messages
     @State private var commentText: String?
     @State private var isAddingComment = false // Add isAddingComment state
     @State private var selectedAnnotationType: PDFAnnotationSubtype? // Add selectedAnnotationType state
     @State private var chatMessages: [ChatMessage] = [] // Store chat messages
     @State private var commentAnnotations: [CommentAnnotation] = [] // Store comment annotations
     @State private var selectedAnnotation: PDFAnnotation? // Store the selected annotation
     @State private var selectedOnDocumentAnnotation: CustomPDFAnnotation? // Store the selected annotation
     @State private var isTyping = false // Add isTyping state
     @State private var pdfView: PDFView? // Add pdfView property
     @State private var fontColor: Color = .black // Add a state variable to store the font color
     @State private var showDeleteButton: Bool = false // Track whether to show the delete button
     @State private var isBold: Bool = false // Track whether the text is bold
     @State private var isItalic: Bool = false // Track whether the text is italic
     @State private var fontSize: CGFloat = 16 // Track the selected font size
     let availableFontSizes: [CGFloat] = [8, 10, 12, 14, 16,18, 20, 22, 24, 26, 28, 30, 32]
     @Environment(\.colorScheme) var colorScheme

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
                             .frame(width: 32, height: 32)
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
         
         .toolbar {
             ToolbarItem(placement: .navigationBarTrailing) {
                 AnnotationToolbar(selectedAnnotationType: $selectedAnnotationType, isAddingComment: $isAddingComment, commentText: $commentText, showCommentDrawer: $showCommentDrawer, isTyping: $isTyping, fontColor: $fontColor, showDeleteButton: $showDeleteButton, isBold: $isBold, isItalic: $isItalic, fontSize: $fontSize, deleteAction: deleteAnnotation, availableFontSizes: availableFontSizes, isHighlighting: $isHighlighting)
             }
             ToolbarItem(placement: .navigationBarTrailing) {
                 Spacer()
             }
             
         }
         .sheet(isPresented: $showCommentDrawer) {
             CommentDrawerView(commentMessages: $commentMessages, documentURL: documentURL, commentText: $commentText, isAddingComment: $isAddingComment, selectedAnnotation: $selectedAnnotation, saveCommentAnnotation: saveCommentAnnotation)
         }
         .sheet(isPresented: $showChatDrawer) {
             ChatDrawerView(chatMessages: $chatMessages, documentURL: documentURL, commentText: $commentText)
         }
         .onAppear {
             fetchOnDocumentComment(documentURL: documentURL)
             fetchCommentAnnotations()
             fetchCommentMessages()
             fetchHighlightAnnotations()
         }
     }
     
     func handleTapGesture(location: CGPoint) {
         if let pdfView = PDFViewWrapper.pdfView,
            let currentPage = pdfView.currentPage {
             let tapLocation = pdfView.convert(location, to: currentPage)
             
             if let tappedAnnotation = currentPage.annotation(at: tapLocation) {
                 // User tapped on an existing annotation
                 
                 
                 if let customAnnotation = tappedAnnotation as? CustomPDFAnnotation {
                     selectedOnDocumentAnnotation = customAnnotation
                     let annotationWidth = customAnnotation.bounds.size.width
                     
                  //   if annotationWidth == 200 {
                         showDeleteButton = true
                         isTyping = false
                   //  }
                 }
                 else if let pdfAnnotation = tappedAnnotation as? PDFAnnotation{
                     
                     selectedAnnotation = pdfAnnotation
                     let annotationWidth = pdfAnnotation.bounds.size.width
                     if annotationWidth == 30 {
                         // Handle other types of annotations if necessary
                         showCommentDrawer = true
                     }
                     else {
                         showDeleteButton = true
                     }
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
                     createHighlightAnnotation()
                 }
             }
             if isAddingComment {
                 
                // let tapLocation = pdfView.convert(location, to: currentPage)
                 // Create a text annotation at the tapped location
                 let textAnnotation = PDFAnnotation(bounds: CGRect(x: tapLocation.x, y: tapLocation.y, width: 30, height: 30), forType: .freeText, withProperties: nil)
                 textAnnotation.contents = "\(commentMessages.count + 1)" // Calculate the comment count and set it as the annotation content
                 textAnnotation.font = UIFont.boldSystemFont(ofSize: 20) // Adjust the font size if needed
                 textAnnotation.color = .yellow.withAlphaComponent(0.2)
                 textAnnotation.fontColor = .red
                 textAnnotation.alignment = .center
                 // Store the selected annotation
                 
                 
                 selectedAnnotation = textAnnotation
                 
                 // Open the CommentDrawerView
                 showCommentDrawer = true
             }
             
             else if isTyping {
                 
                 if firstTouchLocation == nil {
                     firstTouchLocation = location
                 } else if secondTouchLocation == nil {
                     secondTouchLocation = location
                 }
                 guard let firstTouchLocation = firstTouchLocation,
                       let secondTouchLocation = secondTouchLocation,
                       let pdfView = PDFViewWrapper.pdfView,
                       let tappedPage = pdfView.page(for: firstTouchLocation, nearest: true) else {
                     return
                 }

                 
                 let convertedFirstLocation = pdfView.convert(firstTouchLocation, to: currentPage)
                 let convertedSecondLocation = pdfView.convert(secondTouchLocation, to: currentPage)

                 
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
                 currentPage.addAnnotation(freeTextAnnotation)
                 
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
                 
                 currentPage.addAnnotation(freeTextAnnotation)
                 pdfView.addSubview(annotationLabel)
                 pdfView.addSubview(textField)
                 
                 // Set the selectedAnnotation to the created free text annotation
                 selectedAnnotation = freeTextAnnotation
                 pdfView.becomeFirstResponder()
             }
         }
     }
     
     
     func createHighlightAnnotation() {
         guard let firstTouchLocation = firstTouchLocation,
               let secondTouchLocation = secondTouchLocation,
               let pdfView = PDFViewWrapper.pdfView,
               let tappedPage = pdfView.page(for: firstTouchLocation, nearest: true) else {
             return
         }
         
         let convertedFirstLocation = pdfView.convert(firstTouchLocation, to: tappedPage)
         let convertedSecondLocation = pdfView.convert(secondTouchLocation, to: tappedPage)
         
         let width: CGFloat
      //   var height = abs(convertedSecondLocation.y - convertedFirstLocation.y)
         
     //    if height < 20 {
             width = abs(convertedSecondLocation.x - convertedFirstLocation.x)
     //        height = 10
     //    } else {
      //       width = tappedPage.bounds(for: .cropBox).width
     //    }
         
         let minY = min(convertedFirstLocation.y, convertedSecondLocation.y)
         let highlightBounds = CGRect(x: convertedFirstLocation.x, y: minY, width: width, height: 10)
         
         let highlightAnnotation = CustomPDFAnnotation(bounds: highlightBounds, forType: .highlight, withProperties: nil)
         tappedPage.addAnnotation(highlightAnnotation)
         
         // Reset touch locations for future highlights
         self.firstTouchLocation = nil
         self.secondTouchLocation = nil
         
        // isHighlighting = false
         
         // Save the highlight annotation to Firestore
         saveHighlightAnnotation(highlightAnnotation, documentURL: documentURL)
         fetchHighlightAnnotations()
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
     
     
     
     func fetchHighlightAnnotations() {
         print("Fetching highlight annotations")
         
         guard let currentUserEmail = Auth.auth().currentUser?.email else {
             print("User is not signed in.")
             return
         }
         
         let db = Firestore.firestore()
         let annotationsCollection = db.collection("highlightAnnotations").document(documentURL.lastPathComponent).collection("annotations")
         
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
                     } else {
                         print("Invalid page index: \(pageIndex)")
                     }
                 }
             } else {
                 print("PDFView is nil.")
             }
         }
     }




     
     func sendButtonTapped() {
         guard let pdfView = PDFViewWrapper.pdfView,
               let textField = pdfView.subviews.first(where: { $0 is UITextField }) as? UITextField,
               let selectedAnnotation = selectedAnnotation as? PDFAnnotation else {
             return
         }
         
         selectedAnnotation.contents = textField.text ?? ""
         
         var traits = getFontSymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         
         let currentFontSize = selectedAnnotation.font?.pointSize ?? 16
         let resizedFontDescriptor = selectedAnnotation.font?.fontDescriptor.withSymbolicTraits(traits)
         let resizedFont = UIFont(descriptor: resizedFontDescriptor ?? UIFontDescriptor(), size: currentFontSize)
         
         selectedAnnotation.font = resizedFont
         
         textField.resignFirstResponder() // Hide the keyboard
         textField.removeFromSuperview() // Remove the textField from its superview
         
         if let freeTextAnnotation = selectedAnnotation as? CustomPDFAnnotation {
             saveOnDocumentComment(freeTextAnnotation, documentURL: documentURL, isBold: isBold, isItalic: isItalic, fontSize: fontSize, fontColor: fontColor)
         }
         isTyping = false
         showDeleteButton = false
         // Trigger a re-draw of the PDF view to reflect the updated annotation appearance
         pdfView.setNeedsDisplay()
         
         fetchOnDocumentComment(documentURL: documentURL)
         
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
                     
                     
                     var traits = getFontSymbolicTraits()
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
                     
                     if let currentPage = pdfView.document?.page(at: pageNumber - 1) {
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


     
     func deleteButtonClicked(annotation: CustomPDFAnnotation) {
         // Remove the annotation from the PDF view
         guard let pdfView = PDFViewWrapper.pdfView,
               let currentPage = pdfView.currentPage else {
             print("Failed to get current page or PDF view.")
             return
         }
         
         currentPage.removeAnnotation(annotation)

         
         // Remove the annotation from Firestore
         guard let annotationID = annotation.annotationID else {
             print("Annotation ID not found.")
             return
         }
         
         let db = Firestore.firestore()
         let annotationsCollection = db.collection("highlightAnnotations")
         
         annotationsCollection.whereField("annotationID", isEqualTo: annotationID)
             .getDocuments { querySnapshot, error in
                 if let error = error {
                     print("Error fetching annotation to delete: \(error.localizedDescription)")
                     return
                 }
                 
                 guard let documents = querySnapshot?.documents else {
                     print("No annotations found to delete.")
                     return
                 }
                 
                 for document in documents {
                     document.reference.delete { error in
                         if let error = error {
                             print("Error deleting annotation from Firestore: \(error.localizedDescription)")
                         } else {
                             print("Annotation deleted from Firestore")

                         }
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


     
     
     
     
     func fetchCommentAnnotations() {
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

 struct PDFViewWrapper: UIViewRepresentable {
     let url: URL
     let handleTapGesture: (CGPoint) -> Void
     static var pdfView: PDFView? // Static reference to access pdfView
     
     func makeUIView(context: Context) -> PDFView {
         let pdfView = PDFView()
         pdfView.autoScales = true
         pdfView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = pdfView // Assign pdfView to static property
         
         let gestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
         pdfView.addGestureRecognizer(gestureRecognizer)
         
         return pdfView
     }
     
     func updateUIView(_ uiView: PDFView, context: Context) {
         uiView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = uiView // Update the static reference
     }
     
     func makeCoordinator() -> Coordinator {
         Coordinator(self)
     }
     
     class Coordinator: NSObject {
         let pdfViewWrapper: PDFViewWrapper
         
         init(_ pdfViewWrapper: PDFViewWrapper) {
             self.pdfViewWrapper = pdfViewWrapper
         }
         
         @objc func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
             let location = gestureRecognizer.location(in: PDFViewWrapper.pdfView)
             pdfViewWrapper.handleTapGesture(location)
         }
     }
     
     // Function to add an annotation to the current PDFPage
     static func addAnnotationToCurrentPage(annotation: PDFAnnotation) {
         if let currentPage = pdfView?.currentPage {
             currentPage.addAnnotation(annotation)
             pdfView?.setNeedsDisplay()
         }
     }
 }


 struct AnnotationToolbar: View {
     @Binding var selectedAnnotationType: PDFAnnotationSubtype?
     @Binding var isAddingComment: Bool
     @Binding var commentText: String?
     @Binding var showCommentDrawer: Bool
     @Binding var isTyping: Bool
     @Binding var fontColor: Color // Use Color instead of UIColor
     @Binding var showDeleteButton: Bool // Track whether to show the delete button
     @Binding var isBold: Bool // Track whether the text is bold
     @Binding var isItalic: Bool // Track whether the text is italic
     @Binding var fontSize: CGFloat // Track the selected font size
     var deleteAction: () -> Void // Action to delete the annotation
     @State private var isDropdownOpen = false
     let availableFontSizes: [CGFloat]
     let colorButtonSize: CGFloat = 24 // Size of the color buttons
     @Environment(\.colorScheme) var colorScheme
     @Binding var isHighlighting: Bool

     
     var body: some View {

         ZStack {
             if !isTyping && !isAddingComment && !showDeleteButton && !isHighlighting{
                 HStack {
                     Button(action: {
                         selectedAnnotationType = nil
                         isAddingComment.toggle()
                     }) {
                         Image(systemName: "rectangle.and.pencil.and.ellipsis")
                     }
                     .foregroundColor(.primary)
                     
                     Button(action: {
                         selectedAnnotationType = .freeText
                         isTyping.toggle()
                     }) {
                         Image(systemName: "pencil.tip")
                     }
                     .foregroundColor(.primary)
                     
                         Button(action: {
                             isHighlighting.toggle()
                         }) {
                             Image(systemName: "highlighter")
                         }
                         .foregroundColor(isHighlighting ? .blue : .black)
                     
                 }
             }
             else if isAddingComment {
                 Button(action: {
                     selectedAnnotationType = nil
                     isAddingComment.toggle()
                 }) {
                     Image(systemName: "rectangle.and.pencil.and.ellipsis")
                 }
                 .foregroundColor(.blue )
             }
             else if isTyping {
                 HStack(spacing: 0) {
                     Button(action: {
                         isBold.toggle()
                     }) {
                         Image(systemName: isBold ? "bold" : "bold")
                     }
                     .foregroundColor(isBold ? .blue : .primary)
                     
                     Button(action: {
                         isItalic.toggle()
                     }) {
                         Image(systemName: isItalic ? "italic" : "italic")
                     }
                     .foregroundColor(isItalic ? .blue : .primary)
                     
                     //ColorButton(color: .black, isSelected: fontColor == .black, action: { fontColor = .black })
                     ColorButton(color: .red, isSelected: fontColor == .red, action: { fontColor = .red })
                     ColorButton(color: .green, isSelected: fontColor == .green, action: { fontColor = .green })
                     ColorButton(color: .blue, isSelected: fontColor == .blue, action: { fontColor = .blue })
                     
                     Menu {
                         ForEach(availableFontSizes, id: \.self) { size in
                             Button(action: {
                                 fontSize = size
                             }) {
                                 Text("\(Int(size))")
                             }
                         }
                     } label: {
                         HStack {
                             Text("Size: \(Int(fontSize))")
                         }
                     }
                     
                     
                     Button(action: {
                         isTyping.toggle()
                     }) {
                         Image(systemName: "pencil.tip")
                             .foregroundColor(isTyping ? .blue : .primary)
                     }
                 }
                 .frame(maxWidth: .infinity)
                 .padding(.horizontal, 8)
             }
             
             else if isHighlighting {
                 Button(action: {
                     isHighlighting.toggle()
                 }) {
                     Image(systemName: "highlighter")
                 }
                 .foregroundColor(isHighlighting ? .blue : .black)

             }
             else if showDeleteButton {
                 Button(action: deleteAction) {
                     Image(systemName: "trash")
                 }
                 .foregroundColor(.red)
             }
             
             
         }

     }
 }




 struct ColorButton: View {
     var color: Color
     var isSelected: Bool
     var action: () -> Void
     
     var body: some View {
         Button(action: action) {
             ZStack {
                 Circle()
                     .fill(color)
                     .frame(width: 5, height: 5)
                 
                 if isSelected {
                     Image(systemName: "checkmark.circle.fill")
                         .foregroundColor(.white)
                 }
             }
         }
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

 class CustomPDFAnnotation: PDFAnnotation {
     var annotationID: String?
 }




 struct DocumentView: View {
     let documentURL: URL
     @State private var showChatDrawer = false
     @State private var showCommentDrawer = false
     @State private var commentMessages: [CommentMessage] = [] // Store comment messages
     @State private var commentText: String?
     @State private var isAddingComment = false // Add isAddingComment state
     @State private var selectedAnnotationType: PDFAnnotationSubtype? // Add selectedAnnotationType state
     @State private var chatMessages: [ChatMessage] = [] // Store chat messages
     @State private var commentAnnotations: [CommentAnnotation] = [] // Store comment annotations
     @State private var selectedAnnotation: PDFAnnotation? // Store the selected annotation
     @State private var selectedOnDocumentAnnotation: CustomPDFAnnotation? // Store the selected annotation
     @State private var isTyping = false // Add isTyping state
     @State private var pdfView: PDFView? // Add pdfView property
     @State private var fontColor: Color = .black // Add a state variable to store the font color
     @State private var showDeleteButton: Bool = false // Track whether to show the delete button
     @State private var isBold: Bool = false // Track whether the text is bold
     @State private var isItalic: Bool = false // Track whether the text is italic
     @State private var fontSize: CGFloat = 16 // Track the selected font size
     let availableFontSizes: [CGFloat] = [8, 10, 12, 14, 16,18, 20, 22, 24, 26, 28, 30, 32]
     @Environment(\.colorScheme) var colorScheme

     @State private var firstTouchLocation: CGPoint?
     @State private var secondTouchLocation: CGPoint?
     @State private var isHighlighting: Bool = false
     @State private var highlightAnnotations: [PDFAnnotation] = []

     
     
     var body: some View {
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
                             .frame(width: 32, height: 32)
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
         
         .toolbar {
             ToolbarItem(placement: .navigationBarTrailing) {
                 AnnotationToolbar(selectedAnnotationType: $selectedAnnotationType, isAddingComment: $isAddingComment, commentText: $commentText, showCommentDrawer: $showCommentDrawer, isTyping: $isTyping, fontColor: $fontColor, showDeleteButton: $showDeleteButton, isBold: $isBold, isItalic: $isItalic, fontSize: $fontSize, deleteAction: deleteAnnotation, availableFontSizes: availableFontSizes, isHighlighting: $isHighlighting)
             }
             ToolbarItem(placement: .navigationBarTrailing) {
                 Spacer()
             }
             
         }
         .sheet(isPresented: $showCommentDrawer) {
             CommentDrawerView(commentMessages: $commentMessages, documentURL: documentURL, commentText: $commentText, isAddingComment: $isAddingComment, selectedAnnotation: $selectedAnnotation, saveCommentAnnotation: saveCommentAnnotation)
         }
         .sheet(isPresented: $showChatDrawer) {
             ChatDrawerView(chatMessages: $chatMessages, documentURL: documentURL, commentText: $commentText)
         }
         .onAppear {
             fetchOnDocumentComment()
             fetchCommentAnnotations()
             fetchCommentMessages()
            fetchHighlightAnnotations()
         }
     }
     
     func handleTapGesture(location: CGPoint) {
         if let pdfView = PDFViewWrapper.pdfView,
            let currentPage = pdfView.currentPage {
             let tapLocation = pdfView.convert(location, to: currentPage)
             
             if let tappedAnnotation = currentPage.annotation(at: tapLocation) {
                 // User tapped on an existing annotation
                 
                 
                 if let customAnnotation = tappedAnnotation as? CustomPDFAnnotation {
                     selectedOnDocumentAnnotation = customAnnotation
                     let annotationWidth = customAnnotation.bounds.size.width
                     
                  //   if annotationWidth == 200 {
                         showDeleteButton = true
                         isTyping = false
                   //  }
                 }
                 else if let pdfAnnotation = tappedAnnotation as? PDFAnnotation{
                     
                     selectedAnnotation = pdfAnnotation
                     let annotationWidth = pdfAnnotation.bounds.size.width
                     if annotationWidth == 30 {
                         // Handle other types of annotations if necessary
                         showCommentDrawer = true
                     }
                     else {
                         showDeleteButton = true
                     }
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
                     createHighlightAnnotation()
                 }
             }
             if isAddingComment {
                 
                // let tapLocation = pdfView.convert(location, to: currentPage)
                 // Create a text annotation at the tapped location
                 let textAnnotation = PDFAnnotation(bounds: CGRect(x: tapLocation.x, y: tapLocation.y, width: 30, height: 30), forType: .freeText, withProperties: nil)
                 textAnnotation.contents = "\(commentMessages.count + 1)" // Calculate the comment count and set it as the annotation content
                 textAnnotation.font = UIFont.boldSystemFont(ofSize: 20) // Adjust the font size if needed
                 textAnnotation.color = .yellow.withAlphaComponent(0.2)
                 textAnnotation.fontColor = .red
                 textAnnotation.alignment = .center
                 // Store the selected annotation
                 
                 
                 selectedAnnotation = textAnnotation
                 
                 // Open the CommentDrawerView
                 showCommentDrawer = true
             }
             
             else if isTyping {
                 
                 if firstTouchLocation == nil {
                     firstTouchLocation = location
                 } else if secondTouchLocation == nil {
                     secondTouchLocation = location
                 }
                 guard let firstTouchLocation = firstTouchLocation,
                       let secondTouchLocation = secondTouchLocation,
                       let pdfView = PDFViewWrapper.pdfView,
                       let tappedPage = pdfView.page(for: firstTouchLocation, nearest: true) else {
                     return
                 }

                 
                 let convertedFirstLocation = pdfView.convert(firstTouchLocation, to: currentPage)
                 let convertedSecondLocation = pdfView.convert(secondTouchLocation, to: currentPage)

                 
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
                 currentPage.addAnnotation(freeTextAnnotation)
                 
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
                 
                 currentPage.addAnnotation(freeTextAnnotation)
                 pdfView.addSubview(annotationLabel)
                 pdfView.addSubview(textField)
                 
                 // Set the selectedAnnotation to the created free text annotation
                 selectedAnnotation = freeTextAnnotation
                 pdfView.becomeFirstResponder()
             }
         }
     }
     
     
     func createHighlightAnnotation() {
         guard let firstTouchLocation = firstTouchLocation,
               let secondTouchLocation = secondTouchLocation,
               let pdfView = PDFViewWrapper.pdfView,
               let tappedPage = pdfView.page(for: firstTouchLocation, nearest: true) else {
             return
         }
         
         let convertedFirstLocation = pdfView.convert(firstTouchLocation, to: tappedPage)
         let convertedSecondLocation = pdfView.convert(secondTouchLocation, to: tappedPage)
         
         let width: CGFloat
      //   var height = abs(convertedSecondLocation.y - convertedFirstLocation.y)
         
     //    if height < 20 {
             width = abs(convertedSecondLocation.x - convertedFirstLocation.x)
     //        height = 10
     //    } else {
      //       width = tappedPage.bounds(for: .cropBox).width
     //    }
         
         let minY = min(convertedFirstLocation.y, convertedSecondLocation.y)
         let highlightBounds = CGRect(x: convertedFirstLocation.x, y: minY, width: width, height: 10)
         
         let highlightAnnotation = CustomPDFAnnotation(bounds: highlightBounds, forType: .highlight, withProperties: nil)
         tappedPage.addAnnotation(highlightAnnotation)
         
         // Reset touch locations for future highlights
         self.firstTouchLocation = nil
         self.secondTouchLocation = nil
         
        // isHighlighting = false
         
         // Save the highlight annotation to Firestore
         saveHighlightAnnotation(highlightAnnotation)
         fetchHighlightAnnotations()
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
     
     

     func saveHighlightAnnotation(_ annotation: CustomPDFAnnotation) {
         guard let currentUserEmail = Auth.auth().currentUser?.email else {
             print("User is not signed in.")
             return
         }
         
         guard let pdfView = PDFViewWrapper.pdfView,
               let currentPage = pdfView.currentPage,
               let pageIndex = pdfView.document?.index(for: currentPage) else {
             print("Failed to get current page or index.")
             return
         }


         let db = Firestore.firestore()
         
         // Generate a unique ID for the free text annotation
         let annotationID = UUID().uuidString

         let annotationRef = db.collection("highlightAnnotations").document(documentURL.lastPathComponent).collection("annotations").document(annotationID)

         
         let bounds = annotation.bounds
         let boundsData: [String: Any] = [
             "x": bounds.origin.x,
             "y": bounds.origin.y,
             "width": bounds.size.width,
             "height": bounds.size.height
         ]
         
         let annotationData: [String: Any] = [
             "documentURL": documentURL.absoluteString,
             "pageIndex": pageIndex,
             "bounds": boundsData,
             "senderEmail": currentUserEmail,
             "annotationID": annotationID,

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
     
     
     func fetchHighlightAnnotations() {
         print("Fetching highlight annotations")
         
         guard let currentUserEmail = Auth.auth().currentUser?.email else {
             print("User is not signed in.")
             return
         }
         
         let db = Firestore.firestore()
         let annotationsCollection = db.collection("highlightAnnotations").document(documentURL.lastPathComponent).collection("annotations")
         
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
                     } else {
                         print("Invalid page index: \(pageIndex)")
                     }
                 }
             } else {
                 print("PDFView is nil.")
             }
         }
     }


     func fetchOnDocumentComment() {
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
                     
                     
                     var traits = getFontSymbolicTraits()
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
                     
                     if let currentPage = pdfView.document?.page(at: pageNumber - 1) {
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


     
     func sendButtonTapped() {
         guard let pdfView = PDFViewWrapper.pdfView,
               let textField = pdfView.subviews.first(where: { $0 is UITextField }) as? UITextField,
               let selectedAnnotation = selectedAnnotation as? PDFAnnotation else {
             return
         }
         
         selectedAnnotation.contents = textField.text ?? ""
         
         var traits = getFontSymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         
         let currentFontSize = selectedAnnotation.font?.pointSize ?? 16
         let resizedFontDescriptor = selectedAnnotation.font?.fontDescriptor.withSymbolicTraits(traits)
         let resizedFont = UIFont(descriptor: resizedFontDescriptor ?? UIFontDescriptor(), size: currentFontSize)
         
         selectedAnnotation.font = resizedFont
         
         textField.resignFirstResponder() // Hide the keyboard
         textField.removeFromSuperview() // Remove the textField from its superview
         
         if let freeTextAnnotation = selectedAnnotation as? CustomPDFAnnotation {
             saveOnDocumentComment(freeTextAnnotation, documentURL: documentURL, isBold: isBold, isItalic: isItalic, fontSize: fontSize, fontColor: fontColor)
         }
         isTyping = false
         showDeleteButton = false
         // Trigger a re-draw of the PDF view to reflect the updated annotation appearance
         pdfView.setNeedsDisplay()
         
         fetchOnDocumentComment()
         
     }
     
     func getFontSymbolicTraits() -> UIFontDescriptor.SymbolicTraits {
         var traits = UIFontDescriptor.SymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         return traits
     }
     
     func deleteButtonClicked(annotation: CustomPDFAnnotation) {
         // Remove the annotation from the PDF view
         guard let pdfView = PDFViewWrapper.pdfView,
               let currentPage = pdfView.currentPage else {
             print("Failed to get current page or PDF view.")
             return
         }
         
         currentPage.removeAnnotation(annotation)

         
         // Remove the annotation from Firestore
         guard let annotationID = annotation.annotationID else {
             print("Annotation ID not found.")
             return
         }
         
         let db = Firestore.firestore()
         let annotationsCollection = db.collection("highlightAnnotations")
         
         annotationsCollection.whereField("annotationID", isEqualTo: annotationID)
             .getDocuments { querySnapshot, error in
                 if let error = error {
                     print("Error fetching annotation to delete: \(error.localizedDescription)")
                     return
                 }
                 
                 guard let documents = querySnapshot?.documents else {
                     print("No annotations found to delete.")
                     return
                 }
                 
                 for document in documents {
                     document.reference.delete { error in
                         if let error = error {
                             print("Error deleting annotation from Firestore: \(error.localizedDescription)")
                         } else {
                             print("Annotation deleted from Firestore")

                         }
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


     
     
     
     func saveCommentAnnotation(_ annotation: PDFAnnotation) {
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
     
     
     func fetchCommentAnnotations() {
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

 struct PDFViewWrapper: UIViewRepresentable {
     let url: URL
     let handleTapGesture: (CGPoint) -> Void
     static var pdfView: PDFView? // Static reference to access pdfView
     
     func makeUIView(context: Context) -> PDFView {
         let pdfView = PDFView()
         pdfView.autoScales = true
         pdfView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = pdfView // Assign pdfView to static property
         
         let gestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
         pdfView.addGestureRecognizer(gestureRecognizer)
         
         return pdfView
     }
     
     func updateUIView(_ uiView: PDFView, context: Context) {
         uiView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = uiView // Update the static reference
     }
     
     func makeCoordinator() -> Coordinator {
         Coordinator(self)
     }
     
     class Coordinator: NSObject {
         let pdfViewWrapper: PDFViewWrapper
         
         init(_ pdfViewWrapper: PDFViewWrapper) {
             self.pdfViewWrapper = pdfViewWrapper
         }
         
         @objc func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
             let location = gestureRecognizer.location(in: PDFViewWrapper.pdfView)
             pdfViewWrapper.handleTapGesture(location)
         }
     }
     
     // Function to add an annotation to the current PDFPage
     static func addAnnotationToCurrentPage(annotation: PDFAnnotation) {
         if let currentPage = pdfView?.currentPage {
             currentPage.addAnnotation(annotation)
             pdfView?.setNeedsDisplay()
         }
     }
 }




 struct AnnotationToolbar: View {
     @Binding var selectedAnnotationType: PDFAnnotationSubtype?
     @Binding var isAddingComment: Bool
     @Binding var commentText: String?
     @Binding var showCommentDrawer: Bool
     @Binding var isTyping: Bool
     @Binding var fontColor: Color // Use Color instead of UIColor
     @Binding var showDeleteButton: Bool // Track whether to show the delete button
     @Binding var isBold: Bool // Track whether the text is bold
     @Binding var isItalic: Bool // Track whether the text is italic
     @Binding var fontSize: CGFloat // Track the selected font size
     var deleteAction: () -> Void // Action to delete the annotation
     @State private var isDropdownOpen = false
     let availableFontSizes: [CGFloat]
     let colorButtonSize: CGFloat = 24 // Size of the color buttons
     @Environment(\.colorScheme) var colorScheme
     @Binding var isHighlighting: Bool

     
     var body: some View {

         ZStack {
             if !isTyping && !isAddingComment && !showDeleteButton && !isHighlighting{
                 HStack {
                     Button(action: {
                         selectedAnnotationType = nil
                         isAddingComment.toggle()
                     }) {
                         Image(systemName: "rectangle.and.pencil.and.ellipsis")
                     }
                     .foregroundColor(.primary)
                     
                     Button(action: {
                         selectedAnnotationType = .freeText
                         isTyping.toggle()
                     }) {
                         Image(systemName: "pencil.tip")
                     }
                     .foregroundColor(.primary)
                     
                         Button(action: {
                             isHighlighting.toggle()
                         }) {
                             Image(systemName: "highlighter")
                         }
                         .foregroundColor(isHighlighting ? .blue : .black)
                     
                 }
             }
             else if isAddingComment {
                 Button(action: {
                     selectedAnnotationType = nil
                     isAddingComment.toggle()
                 }) {
                     Image(systemName: "rectangle.and.pencil.and.ellipsis")
                 }
                 .foregroundColor(.blue )
             }
             else if isTyping {
                 HStack(spacing: 0) {
                     Button(action: {
                         isBold.toggle()
                     }) {
                         Image(systemName: isBold ? "bold" : "bold")
                     }
                     .foregroundColor(isBold ? .blue : .primary)
                     
                     Button(action: {
                         isItalic.toggle()
                     }) {
                         Image(systemName: isItalic ? "italic" : "italic")
                     }
                     .foregroundColor(isItalic ? .blue : .primary)
                     
                     //ColorButton(color: .black, isSelected: fontColor == .black, action: { fontColor = .black })
                     ColorButton(color: .red, isSelected: fontColor == .red, action: { fontColor = .red })
                     ColorButton(color: .green, isSelected: fontColor == .green, action: { fontColor = .green })
                     ColorButton(color: .blue, isSelected: fontColor == .blue, action: { fontColor = .blue })
                     
                     Menu {
                         ForEach(availableFontSizes, id: \.self) { size in
                             Button(action: {
                                 fontSize = size
                             }) {
                                 Text("\(Int(size))")
                             }
                         }
                     } label: {
                         HStack {
                             Text("Size: \(Int(fontSize))")
                         }
                     }
                     
                     
                     Button(action: {
                         isTyping.toggle()
                     }) {
                         Image(systemName: "pencil.tip")
                             .foregroundColor(isTyping ? .blue : .primary)
                     }
                 }
                 .frame(maxWidth: .infinity)
                 .padding(.horizontal, 8)
             }
             
             else if isHighlighting {
                 Button(action: {
                     isHighlighting.toggle()
                 }) {
                     Image(systemName: "highlighter")
                 }
                 .foregroundColor(isHighlighting ? .blue : .black)

             }
             else if showDeleteButton {
                 Button(action: deleteAction) {
                     Image(systemName: "trash")
                 }
                 .foregroundColor(.red)
             }
             
             
         }

     }
 }

 struct ColorButton: View {
     var color: Color
     var isSelected: Bool
     var action: () -> Void
     
     var body: some View {
         Button(action: action) {
             ZStack {
                 Circle()
                     .fill(color)
                     .frame(width: 5, height: 5)
                 
                 if isSelected {
                     Image(systemName: "checkmark.circle.fill")
                         .foregroundColor(.white)
                 }
             }
         }
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

 class CustomPDFAnnotation: PDFAnnotation {
     var annotationID: String?
 }




 struct DocumentView: View {
     let documentURL: URL
     @State private var showChatDrawer = false
     @State private var showCommentDrawer = false
     @State private var commentMessages: [CommentMessage] = [] // Store comment messages
     @State private var commentText: String?
     @State private var isAddingComment = false // Add isAddingComment state
     @State private var selectedAnnotationType: PDFAnnotationSubtype? // Add selectedAnnotationType state
     @State private var chatMessages: [ChatMessage] = [] // Store chat messages
     @State private var commentAnnotations: [CommentAnnotation] = [] // Store comment annotations
     @State private var selectedAnnotation: PDFAnnotation? // Store the selected annotation
     @State private var selectedOnDocumentAnnotation: CustomPDFAnnotation? // Store the selected annotation
     @State private var isTyping = false // Add isTyping state
     @State private var pdfView: PDFView? // Add pdfView property
     @State private var fontColor: Color = .black // Add a state variable to store the font color
     @State private var showDeleteButton: Bool = false // Track whether to show the delete button
     @State private var isBold: Bool = false // Track whether the text is bold
     @State private var isItalic: Bool = false // Track whether the text is italic
     @State private var fontSize: CGFloat = 16 // Track the selected font size
     let availableFontSizes: [CGFloat] = [8, 10, 12, 14, 16,18, 20, 22, 24, 26, 28, 30, 32]
     @Environment(\.colorScheme) var colorScheme

     @State private var firstTouchLocation: CGPoint?
     @State private var secondTouchLocation: CGPoint?
     @State private var isHighlighting: Bool = false
     @State private var highlightAnnotations: [PDFAnnotation] = []

     
     
     var body: some View {
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
                             .frame(width: 32, height: 32)
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
         
         .toolbar {
             ToolbarItem(placement: .navigationBarTrailing) {
                 AnnotationToolbar(selectedAnnotationType: $selectedAnnotationType, isAddingComment: $isAddingComment, commentText: $commentText, showCommentDrawer: $showCommentDrawer, isTyping: $isTyping, fontColor: $fontColor, showDeleteButton: $showDeleteButton, isBold: $isBold, isItalic: $isItalic, fontSize: $fontSize, deleteAction: deleteAnnotation, availableFontSizes: availableFontSizes, isHighlighting: $isHighlighting)
             }
             ToolbarItem(placement: .navigationBarTrailing) {
                 Spacer()
             }
             
         }
         .sheet(isPresented: $showCommentDrawer) {
             CommentDrawerView(commentMessages: $commentMessages, documentURL: documentURL, commentText: $commentText, isAddingComment: $isAddingComment, selectedAnnotation: $selectedAnnotation, saveCommentAnnotation: saveCommentAnnotation)
         }
         .sheet(isPresented: $showChatDrawer) {
             ChatDrawerView(chatMessages: $chatMessages, documentURL: documentURL, commentText: $commentText)
         }
         .onAppear {
             fetchOnDocumentComment()
             fetchCommentAnnotations()
             fetchCommentMessages()
            fetchHighlightAnnotations()
         }
     }
     
     func handleTapGesture(location: CGPoint) {
         if let pdfView = PDFViewWrapper.pdfView,
            let currentPage = pdfView.currentPage {
             let tapLocation = pdfView.convert(location, to: currentPage)
             
             if let tappedAnnotation = currentPage.annotation(at: tapLocation) {
                 // User tapped on an existing annotation
                 
                 
                 if let customAnnotation = tappedAnnotation as? CustomPDFAnnotation {
                     selectedOnDocumentAnnotation = customAnnotation
                     let annotationWidth = customAnnotation.bounds.size.width
                     
                  //   if annotationWidth == 200 {
                         showDeleteButton = true
                         isTyping = false
                   //  }
                 }
                 else if let pdfAnnotation = tappedAnnotation as? PDFAnnotation{
                     
                     selectedAnnotation = pdfAnnotation
                     let annotationWidth = pdfAnnotation.bounds.size.width
                     if annotationWidth == 30 {
                         // Handle other types of annotations if necessary
                         showCommentDrawer = true
                     }
                     else {
                         showDeleteButton = true
                     }
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
                     createHighlightAnnotation()
                 }
             }
             if isAddingComment {
                 
                // let tapLocation = pdfView.convert(location, to: currentPage)
                 // Create a text annotation at the tapped location
                 let textAnnotation = PDFAnnotation(bounds: CGRect(x: tapLocation.x, y: tapLocation.y, width: 30, height: 30), forType: .freeText, withProperties: nil)
                 textAnnotation.contents = "\(commentMessages.count + 1)" // Calculate the comment count and set it as the annotation content
                 textAnnotation.font = UIFont.boldSystemFont(ofSize: 20) // Adjust the font size if needed
                 textAnnotation.color = .yellow.withAlphaComponent(0.2)
                 textAnnotation.fontColor = .red
                 textAnnotation.alignment = .center
                 // Store the selected annotation
                 
                 
                 selectedAnnotation = textAnnotation
                 
                 // Open the CommentDrawerView
                 showCommentDrawer = true
             }
             
             else if isTyping {
                 
                 if firstTouchLocation == nil {
                     firstTouchLocation = location
                 } else if secondTouchLocation == nil {
                     secondTouchLocation = location
                 }
                 guard let firstTouchLocation = firstTouchLocation,
                       let secondTouchLocation = secondTouchLocation,
                       let pdfView = PDFViewWrapper.pdfView,
                       let tappedPage = pdfView.page(for: firstTouchLocation, nearest: true) else {
                     return
                 }

                 
                 let convertedFirstLocation = pdfView.convert(firstTouchLocation, to: currentPage)
                 let convertedSecondLocation = pdfView.convert(secondTouchLocation, to: currentPage)

                 
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
                 currentPage.addAnnotation(freeTextAnnotation)
                 
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
                 
                 currentPage.addAnnotation(freeTextAnnotation)
                 pdfView.addSubview(annotationLabel)
                 pdfView.addSubview(textField)
                 
                 // Set the selectedAnnotation to the created free text annotation
                 selectedAnnotation = freeTextAnnotation
                 pdfView.becomeFirstResponder()
             }
         }
     }
     
     func createHighlightAnnotation() {
         guard let firstTouchLocation = firstTouchLocation,
               let secondTouchLocation = secondTouchLocation,
               let pdfView = PDFViewWrapper.pdfView,
               let tappedPage = pdfView.page(for: firstTouchLocation, nearest: true) else {
             return
         }
         
         let convertedFirstLocation = pdfView.convert(firstTouchLocation, to: tappedPage)
         let convertedSecondLocation = pdfView.convert(secondTouchLocation, to: tappedPage)
         
         let width: CGFloat
      //   var height = abs(convertedSecondLocation.y - convertedFirstLocation.y)
         
     //    if height < 20 {
             width = abs(convertedSecondLocation.x - convertedFirstLocation.x)
     //        height = 10
     //    } else {
      //       width = tappedPage.bounds(for: .cropBox).width
     //    }
         
         let minY = min(convertedFirstLocation.y, convertedSecondLocation.y)
         let highlightBounds = CGRect(x: convertedFirstLocation.x, y: minY, width: width, height: 10)
         
         let highlightAnnotation = CustomPDFAnnotation(bounds: highlightBounds, forType: .highlight, withProperties: nil)
         tappedPage.addAnnotation(highlightAnnotation)
         
         // Reset touch locations for future highlights
         self.firstTouchLocation = nil
         self.secondTouchLocation = nil
         
        // isHighlighting = false
         
         // Save the highlight annotation to Firestore
         saveHighlightAnnotation(highlightAnnotation)
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
     
     

     func saveHighlightAnnotation(_ annotation: CustomPDFAnnotation) {
         guard let currentUserEmail = Auth.auth().currentUser?.email else {
             print("User is not signed in.")
             return
         }
         
         guard let pdfView = PDFViewWrapper.pdfView,
               let currentPage = pdfView.currentPage,
               let pageIndex = pdfView.document?.index(for: currentPage) else {
             print("Failed to get current page or index.")
             return
         }


         let db = Firestore.firestore()
         
         // Generate a unique ID for the free text annotation
         let annotationID = UUID().uuidString

         let annotationRef = db.collection("highlightAnnotations").document(documentURL.lastPathComponent).collection("annotations").document(annotationID)

         
         let bounds = annotation.bounds
         let boundsData: [String: Any] = [
             "x": bounds.origin.x,
             "y": bounds.origin.y,
             "width": bounds.size.width,
             "height": bounds.size.height
         ]
         
         let annotationData: [String: Any] = [
             "documentURL": documentURL.absoluteString,
             "pageIndex": pageIndex,
             "bounds": boundsData,
             "senderEmail": currentUserEmail,
             "annotationID": annotationID,

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
     
     func saveOnDocumentComment(_ annotation: CustomPDFAnnotation) {
         guard let currentUserEmail = Auth.auth().currentUser?.email else {
             print("User is not signed in.")
             return
         }
         
         guard let pdfView = PDFViewWrapper.pdfView,
               let currentPage = pdfView.currentPage,
               let pageIndex = pdfView.document?.index(for: currentPage) else {
             print("Failed to get current page or index.")
             return
         }
         
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
             "pageNumber": pageIndex + 1, // Add the page number (incremented by 1 since pages are 0-indexed)
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
     
     func fetchHighlightAnnotations() {
         print("Fetching highlight annotations")
         
         guard let currentUserEmail = Auth.auth().currentUser?.email else {
             print("User is not signed in.")
             return
         }
         
         let db = Firestore.firestore()
         let annotationsCollection = db.collection("highlightAnnotations").document(documentURL.lastPathComponent).collection("annotations")
         
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
                     } else {
                         print("Invalid page index: \(pageIndex)")
                     }
                 }
             } else {
                 print("PDFView is nil.")
             }
         }
     }


     func fetchOnDocumentComment() {
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
                     
                     
                     var traits = getFontSymbolicTraits()
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
                     
                     if let currentPage = pdfView.document?.page(at: pageNumber - 1) {
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


     
     func sendButtonTapped() {
         guard let pdfView = PDFViewWrapper.pdfView,
               let textField = pdfView.subviews.first(where: { $0 is UITextField }) as? UITextField,
               let selectedAnnotation = selectedAnnotation as? PDFAnnotation else {
             return
         }
         
         selectedAnnotation.contents = textField.text ?? ""
         
         var traits = getFontSymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         
         let currentFontSize = selectedAnnotation.font?.pointSize ?? 16
         let resizedFontDescriptor = selectedAnnotation.font?.fontDescriptor.withSymbolicTraits(traits)
         let resizedFont = UIFont(descriptor: resizedFontDescriptor ?? UIFontDescriptor(), size: currentFontSize)
         
         selectedAnnotation.font = resizedFont
         
         textField.resignFirstResponder() // Hide the keyboard
         textField.removeFromSuperview() // Remove the textField from its superview
         
         if let freeTextAnnotation = selectedAnnotation as? CustomPDFAnnotation {
             saveOnDocumentComment(freeTextAnnotation)
             

         }
         isTyping = false
         showDeleteButton = false
         // Trigger a re-draw of the PDF view to reflect the updated annotation appearance
         pdfView.setNeedsDisplay()
     }
     
     func getFontSymbolicTraits() -> UIFontDescriptor.SymbolicTraits {
         var traits = UIFontDescriptor.SymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         return traits
     }
     
     func deleteButtonClicked(annotation: CustomPDFAnnotation) {
         // Remove the annotation from the PDF view
         guard let pdfView = PDFViewWrapper.pdfView,
               let currentPage = pdfView.currentPage else {
             print("Failed to get current page or PDF view.")
             return
         }
         
         currentPage.removeAnnotation(annotation)
         
         // Remove the annotation from Firestore
         guard let annotationID = annotation.annotationID else {
             print("Annotation ID not found.")
             return
         }
         
         let db = Firestore.firestore()
         let annotationsCollection = db.collection("highlightAnnotations")
         
         annotationsCollection.whereField("annotationID", isEqualTo: annotationID)
             .getDocuments { querySnapshot, error in
                 if let error = error {
                     print("Error fetching annotation to delete: \(error.localizedDescription)")
                     return
                 }
                 
                 guard let documents = querySnapshot?.documents else {
                     print("No annotations found to delete.")
                     return
                 }
                 
                 for document in documents {
                     document.reference.delete { error in
                         if let error = error {
                             print("Error deleting annotation from Firestore: \(error.localizedDescription)")
                         } else {
                             print("Annotation deleted from Firestore")
                         }
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


     
     
     
     func saveCommentAnnotation(_ annotation: PDFAnnotation) {
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
     
     
     func fetchCommentAnnotations() {
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

 struct PDFViewWrapper: UIViewRepresentable {
     let url: URL
     let handleTapGesture: (CGPoint) -> Void
     static var pdfView: PDFView? // Static reference to access pdfView
     
     func makeUIView(context: Context) -> PDFView {
         let pdfView = PDFView()
         pdfView.autoScales = true
         pdfView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = pdfView // Assign pdfView to static property
         
         let gestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
         pdfView.addGestureRecognizer(gestureRecognizer)
         
         return pdfView
     }
     
     func updateUIView(_ uiView: PDFView, context: Context) {
         uiView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = uiView // Update the static reference
     }
     
     func makeCoordinator() -> Coordinator {
         Coordinator(self)
     }
     
     class Coordinator: NSObject {
         let pdfViewWrapper: PDFViewWrapper
         
         init(_ pdfViewWrapper: PDFViewWrapper) {
             self.pdfViewWrapper = pdfViewWrapper
         }
         
         @objc func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
             let location = gestureRecognizer.location(in: PDFViewWrapper.pdfView)
             pdfViewWrapper.handleTapGesture(location)
         }
     }
     
     // Function to add an annotation to the current PDFPage
     static func addAnnotationToCurrentPage(annotation: PDFAnnotation) {
         if let currentPage = pdfView?.currentPage {
             currentPage.addAnnotation(annotation)
             pdfView?.setNeedsDisplay()
         }
     }
 }




 struct AnnotationToolbar: View {
     @Binding var selectedAnnotationType: PDFAnnotationSubtype?
     @Binding var isAddingComment: Bool
     @Binding var commentText: String?
     @Binding var showCommentDrawer: Bool
     @Binding var isTyping: Bool
     @Binding var fontColor: Color // Use Color instead of UIColor
     @Binding var showDeleteButton: Bool // Track whether to show the delete button
     @Binding var isBold: Bool // Track whether the text is bold
     @Binding var isItalic: Bool // Track whether the text is italic
     @Binding var fontSize: CGFloat // Track the selected font size
     var deleteAction: () -> Void // Action to delete the annotation
     @State private var isDropdownOpen = false
     let availableFontSizes: [CGFloat]
     let colorButtonSize: CGFloat = 24 // Size of the color buttons
     @Environment(\.colorScheme) var colorScheme
     @Binding var isHighlighting: Bool

     
     var body: some View {

         ZStack {
             if !isTyping && !isAddingComment && !showDeleteButton && !isHighlighting{
                 HStack {
                     Button(action: {
                         selectedAnnotationType = nil
                         isAddingComment.toggle()
                     }) {
                         Image(systemName: "rectangle.and.pencil.and.ellipsis")
                     }
                     .foregroundColor(.primary)
                     
                     Button(action: {
                         selectedAnnotationType = .freeText
                         isTyping.toggle()
                     }) {
                         Image(systemName: "pencil.tip")
                     }
                     .foregroundColor(.primary)
                     
                         Button(action: {
                             isHighlighting.toggle()
                         }) {
                             Image(systemName: "highlighter")
                         }
                         .foregroundColor(isHighlighting ? .blue : .black)
                     
                 }
             }
             else if isAddingComment {
                 Button(action: {
                     selectedAnnotationType = nil
                     isAddingComment.toggle()
                 }) {
                     Image(systemName: "rectangle.and.pencil.and.ellipsis")
                 }
                 .foregroundColor(.blue )
             }
             else if isTyping {
                 HStack(spacing: 0) {
                     Button(action: {
                         isBold.toggle()
                     }) {
                         Image(systemName: isBold ? "bold" : "bold")
                     }
                     .foregroundColor(isBold ? .blue : .primary)
                     
                     Button(action: {
                         isItalic.toggle()
                     }) {
                         Image(systemName: isItalic ? "italic" : "italic")
                     }
                     .foregroundColor(isItalic ? .blue : .primary)
                     
                     //ColorButton(color: .black, isSelected: fontColor == .black, action: { fontColor = .black })
                     ColorButton(color: .red, isSelected: fontColor == .red, action: { fontColor = .red })
                     ColorButton(color: .green, isSelected: fontColor == .green, action: { fontColor = .green })
                     ColorButton(color: .blue, isSelected: fontColor == .blue, action: { fontColor = .blue })
                     
                     Menu {
                         ForEach(availableFontSizes, id: \.self) { size in
                             Button(action: {
                                 fontSize = size
                             }) {
                                 Text("\(Int(size))")
                             }
                         }
                     } label: {
                         HStack {
                             Text("Size: \(Int(fontSize))")
                         }
                     }
                     
                     
                     Button(action: {
                         isTyping.toggle()
                     }) {
                         Image(systemName: "pencil.tip")
                             .foregroundColor(isTyping ? .blue : .primary)
                     }
                 }
                 .frame(maxWidth: .infinity)
                 .padding(.horizontal, 8)
             }
             
             else if isHighlighting {
                 Button(action: {
                     isHighlighting.toggle()
                 }) {
                     Image(systemName: "highlighter")
                 }
                 .foregroundColor(isHighlighting ? .blue : .black)

             }
             else if showDeleteButton {
                 Button(action: deleteAction) {
                     Image(systemName: "trash")
                 }
                 .foregroundColor(.red)
             }
             
             
         }

     }
 }

 struct ColorButton: View {
     var color: Color
     var isSelected: Bool
     var action: () -> Void
     
     var body: some View {
         Button(action: action) {
             ZStack {
                 Circle()
                     .fill(color)
                     .frame(width: 5, height: 5)
                 
                 if isSelected {
                     Image(systemName: "checkmark.circle.fill")
                         .foregroundColor(.white)
                 }
             }
         }
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

 class CustomPDFAnnotation: PDFAnnotation {
     var annotationID: String?
 }




 struct DocumentView: View {
     let documentURL: URL
     @State private var showChatDrawer = false
     @State private var showCommentDrawer = false
     @State private var commentMessages: [CommentMessage] = [] // Store comment messages
     @State private var commentText: String?
     @State private var isAddingComment = false // Add isAddingComment state
     @State private var selectedAnnotationType: PDFAnnotationSubtype? // Add selectedAnnotationType state
     @State private var chatMessages: [ChatMessage] = [] // Store chat messages
     @State private var commentAnnotations: [CommentAnnotation] = [] // Store comment annotations
     @State private var selectedAnnotation: PDFAnnotation? // Store the selected annotation
     @State private var selectedOnDocumentAnnotation: CustomPDFAnnotation? // Store the selected annotation
     @State private var isTyping = false // Add isTyping state
     @State private var pdfView: PDFView? // Add pdfView property
     @State private var fontColor: Color = .black // Add a state variable to store the font color
     @State private var showDeleteButton: Bool = false // Track whether to show the delete button
     @State private var isBold: Bool = false // Track whether the text is bold
     @State private var isItalic: Bool = false // Track whether the text is italic
     @State private var fontSize: CGFloat = 16 // Track the selected font size
     let availableFontSizes: [CGFloat] = [8, 10, 12, 14, 16,18, 20, 22, 24, 26, 28, 30, 32]
     @Environment(\.colorScheme) var colorScheme

     @State private var firstTouchLocation: CGPoint?
     @State private var secondTouchLocation: CGPoint?
     @State private var isHighlighting: Bool = false
     @State private var highlightAnnotations: [PDFAnnotation] = []

     
     
     var body: some View {
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
                             .frame(width: 32, height: 32)
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
         
         .toolbar {
             ToolbarItem(placement: .navigationBarTrailing) {
                 AnnotationToolbar(selectedAnnotationType: $selectedAnnotationType, isAddingComment: $isAddingComment, commentText: $commentText, showCommentDrawer: $showCommentDrawer, isTyping: $isTyping, fontColor: $fontColor, showDeleteButton: $showDeleteButton, isBold: $isBold, isItalic: $isItalic, fontSize: $fontSize, deleteAction: deleteAnnotation, availableFontSizes: availableFontSizes, isHighlighting: $isHighlighting)
             }
             ToolbarItem(placement: .navigationBarTrailing) {
                 Spacer()
             }
             
         }
         .sheet(isPresented: $showCommentDrawer) {
             CommentDrawerView(commentMessages: $commentMessages, documentURL: documentURL, commentText: $commentText, isAddingComment: $isAddingComment, selectedAnnotation: $selectedAnnotation, saveCommentAnnotation: saveCommentAnnotation)
         }
         .sheet(isPresented: $showChatDrawer) {
             ChatDrawerView(chatMessages: $chatMessages, documentURL: documentURL, commentText: $commentText)
         }
         .onAppear {
             fetchOnDocumentComment()
             fetchCommentAnnotations()
             fetchCommentMessages()
            fetchHighlightAnnotations()
         }
     }
     
     func handleTapGesture(location: CGPoint) {
         if let pdfView = PDFViewWrapper.pdfView,
            let currentPage = pdfView.currentPage {
             let tapLocation = pdfView.convert(location, to: currentPage)
             
             if let tappedAnnotation = currentPage.annotation(at: tapLocation) {
                 // User tapped on an existing annotation
                 
                 
                 if let customAnnotation = tappedAnnotation as? CustomPDFAnnotation {
                     selectedOnDocumentAnnotation = customAnnotation
                     let annotationWidth = customAnnotation.bounds.size.width
                     
                  //   if annotationWidth == 200 {
                         showDeleteButton = true
                         isTyping = false
                   //  }
                 }
                 else if let pdfAnnotation = tappedAnnotation as? PDFAnnotation{
                     
                     selectedAnnotation = pdfAnnotation
                     let annotationWidth = pdfAnnotation.bounds.size.width
                     if annotationWidth == 30 {
                         // Handle other types of annotations if necessary
                         showCommentDrawer = true
                     }
                     else {
                         showDeleteButton = true
                     }
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
                     createHighlightAnnotation()
                 }
             }
             if isAddingComment {
                 
                // let tapLocation = pdfView.convert(location, to: currentPage)
                 // Create a text annotation at the tapped location
                 let textAnnotation = PDFAnnotation(bounds: CGRect(x: tapLocation.x, y: tapLocation.y, width: 30, height: 30), forType: .freeText, withProperties: nil)
                 textAnnotation.contents = "\(commentMessages.count + 1)" // Calculate the comment count and set it as the annotation content
                 textAnnotation.font = UIFont.boldSystemFont(ofSize: 20) // Adjust the font size if needed
                 textAnnotation.color = .yellow.withAlphaComponent(0.2)
                 textAnnotation.fontColor = .red
                 textAnnotation.alignment = .center
                 // Store the selected annotation
                 
                 
                 selectedAnnotation = textAnnotation
                 
                 // Open the CommentDrawerView
                 showCommentDrawer = true
             }
             
             else if isTyping {
                 
                 if firstTouchLocation == nil {
                     firstTouchLocation = location
                 } else if secondTouchLocation == nil {
                     secondTouchLocation = location
                 }
                 guard let firstTouchLocation = firstTouchLocation,
                       let secondTouchLocation = secondTouchLocation,
                       let pdfView = PDFViewWrapper.pdfView,
                       let tappedPage = pdfView.page(for: firstTouchLocation, nearest: true) else {
                     return
                 }

                 
                 let convertedFirstLocation = pdfView.convert(firstTouchLocation, to: currentPage)
                 let convertedSecondLocation = pdfView.convert(secondTouchLocation, to: currentPage)

                 
                 let width: CGFloat
              //   var height = abs(convertedSecondLocation.y - convertedFirstLocation.y)
                 
             //    if height < 20 {
                     width = abs(convertedSecondLocation.x - convertedFirstLocation.x)

                 // User tapped to create a new annotation
                 let bounds = CGRect(x: convertedFirstLocation.x , y: convertedSecondLocation.y - 100, width: width, height: 100)
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
                 currentPage.addAnnotation(freeTextAnnotation)
                 
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
                 
                 currentPage.addAnnotation(freeTextAnnotation)
                 pdfView.addSubview(annotationLabel)
                 pdfView.addSubview(textField)
                 
                 // Set the selectedAnnotation to the created free text annotation
                 selectedAnnotation = freeTextAnnotation
                 pdfView.becomeFirstResponder()
             }
         }
     }
     
     func createHighlightAnnotation() {
         guard let firstTouchLocation = firstTouchLocation,
               let secondTouchLocation = secondTouchLocation,
               let pdfView = PDFViewWrapper.pdfView,
               let tappedPage = pdfView.page(for: firstTouchLocation, nearest: true) else {
             return
         }
         
         let convertedFirstLocation = pdfView.convert(firstTouchLocation, to: tappedPage)
         let convertedSecondLocation = pdfView.convert(secondTouchLocation, to: tappedPage)
         
         let width: CGFloat
      //   var height = abs(convertedSecondLocation.y - convertedFirstLocation.y)
         
     //    if height < 20 {
             width = abs(convertedSecondLocation.x - convertedFirstLocation.x)
     //        height = 10
     //    } else {
      //       width = tappedPage.bounds(for: .cropBox).width
     //    }
         
         let minY = min(convertedFirstLocation.y, convertedSecondLocation.y)
         let highlightBounds = CGRect(x: convertedFirstLocation.x, y: minY, width: width, height: 10)
         
         let highlightAnnotation = CustomPDFAnnotation(bounds: highlightBounds, forType: .highlight, withProperties: nil)
         tappedPage.addAnnotation(highlightAnnotation)
         
         // Reset touch locations for future highlights
         self.firstTouchLocation = nil
         self.secondTouchLocation = nil
         
        // isHighlighting = false
         
         // Save the highlight annotation to Firestore
         saveHighlightAnnotation(highlightAnnotation)
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
     
     

     func saveHighlightAnnotation(_ annotation: CustomPDFAnnotation) {
         guard let currentUserEmail = Auth.auth().currentUser?.email else {
             print("User is not signed in.")
             return
         }
         
         guard let pdfView = PDFViewWrapper.pdfView,
               let currentPage = pdfView.currentPage,
               let pageIndex = pdfView.document?.index(for: currentPage) else {
             print("Failed to get current page or index.")
             return
         }


         let db = Firestore.firestore()
         
         // Generate a unique ID for the free text annotation
         let annotationID = UUID().uuidString

         let annotationRef = db.collection("highlightAnnotations").document(documentURL.lastPathComponent).collection("annotations").document(annotationID)

         
         let bounds = annotation.bounds
         let boundsData: [String: Any] = [
             "x": bounds.origin.x,
             "y": bounds.origin.y,
             "width": bounds.size.width,
             "height": bounds.size.height
         ]
         
         let annotationData: [String: Any] = [
             "documentURL": documentURL.absoluteString,
             "pageIndex": pageIndex,
             "bounds": boundsData,
             "senderEmail": currentUserEmail,
             "annotationID": annotationID,

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
     
     func saveOnDocumentComment(_ annotation: CustomPDFAnnotation) {
         guard let currentUserEmail = Auth.auth().currentUser?.email else {
             print("User is not signed in.")
             return
         }
         
         guard let pdfView = PDFViewWrapper.pdfView,
               let currentPage = pdfView.currentPage,
               let pageIndex = pdfView.document?.index(for: currentPage) else {
             print("Failed to get current page or index.")
             return
         }
         
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
             "pageNumber": pageIndex + 1, // Add the page number (incremented by 1 since pages are 0-indexed)
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
     
     func fetchHighlightAnnotations() {
         print("Fetching highlight annotations")
         
         guard let currentUserEmail = Auth.auth().currentUser?.email else {
             print("User is not signed in.")
             return
         }
         
         let db = Firestore.firestore()
         let annotationsCollection = db.collection("highlightAnnotations").document(documentURL.lastPathComponent).collection("annotations")
         
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
                     } else {
                         print("Invalid page index: \(pageIndex)")
                     }
                 }
             } else {
                 print("PDFView is nil.")
             }
         }
     }


     func fetchOnDocumentComment() {
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
                     
                     
                     var traits = getFontSymbolicTraits()
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
                     
                     if let currentPage = pdfView.document?.page(at: pageNumber - 1) {
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


     
     func sendButtonTapped() {
         guard let pdfView = PDFViewWrapper.pdfView,
               let textField = pdfView.subviews.first(where: { $0 is UITextField }) as? UITextField,
               let selectedAnnotation = selectedAnnotation as? PDFAnnotation else {
             return
         }
         
         selectedAnnotation.contents = textField.text ?? ""
         
         var traits = getFontSymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         
         let currentFontSize = selectedAnnotation.font?.pointSize ?? 16
         let resizedFontDescriptor = selectedAnnotation.font?.fontDescriptor.withSymbolicTraits(traits)
         let resizedFont = UIFont(descriptor: resizedFontDescriptor ?? UIFontDescriptor(), size: currentFontSize)
         
         selectedAnnotation.font = resizedFont
         
         textField.resignFirstResponder() // Hide the keyboard
         textField.removeFromSuperview() // Remove the textField from its superview
         
         if let freeTextAnnotation = selectedAnnotation as? CustomPDFAnnotation {
             saveOnDocumentComment(freeTextAnnotation)
             

         }
         isTyping = false
         showDeleteButton = false
         // Trigger a re-draw of the PDF view to reflect the updated annotation appearance
         pdfView.setNeedsDisplay()
     }
     
     func getFontSymbolicTraits() -> UIFontDescriptor.SymbolicTraits {
         var traits = UIFontDescriptor.SymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         return traits
     }
     
     func deleteButtonClicked(annotation: CustomPDFAnnotation) {
         // Remove the annotation from the PDF view
         guard let pdfView = PDFViewWrapper.pdfView,
               let currentPage = pdfView.currentPage else {
             print("Failed to get current page or PDF view.")
             return
         }
         
         currentPage.removeAnnotation(annotation)
         
         // Remove the annotation from Firestore
         guard let annotationID = annotation.annotationID else {
             print("Annotation ID not found.")
             return
         }
         
         let db = Firestore.firestore()
         let annotationsCollection = db.collection("highlightAnnotations")
         
         annotationsCollection.whereField("annotationID", isEqualTo: annotationID)
             .getDocuments { querySnapshot, error in
                 if let error = error {
                     print("Error fetching annotation to delete: \(error.localizedDescription)")
                     return
                 }
                 
                 guard let documents = querySnapshot?.documents else {
                     print("No annotations found to delete.")
                     return
                 }
                 
                 for document in documents {
                     document.reference.delete { error in
                         if let error = error {
                             print("Error deleting annotation from Firestore: \(error.localizedDescription)")
                         } else {
                             print("Annotation deleted from Firestore")
                         }
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


     
     
     
     func saveCommentAnnotation(_ annotation: PDFAnnotation) {
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
     
     
     func fetchCommentAnnotations() {
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

 struct PDFViewWrapper: UIViewRepresentable {
     let url: URL
     let handleTapGesture: (CGPoint) -> Void
     static var pdfView: PDFView? // Static reference to access pdfView
     
     func makeUIView(context: Context) -> PDFView {
         let pdfView = PDFView()
         pdfView.autoScales = true
         pdfView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = pdfView // Assign pdfView to static property
         
         let gestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
         pdfView.addGestureRecognizer(gestureRecognizer)
         
         return pdfView
     }
     
     func updateUIView(_ uiView: PDFView, context: Context) {
         uiView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = uiView // Update the static reference
     }
     
     func makeCoordinator() -> Coordinator {
         Coordinator(self)
     }
     
     class Coordinator: NSObject {
         let pdfViewWrapper: PDFViewWrapper
         
         init(_ pdfViewWrapper: PDFViewWrapper) {
             self.pdfViewWrapper = pdfViewWrapper
         }
         
         @objc func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
             let location = gestureRecognizer.location(in: PDFViewWrapper.pdfView)
             pdfViewWrapper.handleTapGesture(location)
         }
     }
     
     // Function to add an annotation to the current PDFPage
     static func addAnnotationToCurrentPage(annotation: PDFAnnotation) {
         if let currentPage = pdfView?.currentPage {
             currentPage.addAnnotation(annotation)
             pdfView?.setNeedsDisplay()
         }
     }
 }




 struct AnnotationToolbar: View {
     @Binding var selectedAnnotationType: PDFAnnotationSubtype?
     @Binding var isAddingComment: Bool
     @Binding var commentText: String?
     @Binding var showCommentDrawer: Bool
     @Binding var isTyping: Bool
     @Binding var fontColor: Color // Use Color instead of UIColor
     @Binding var showDeleteButton: Bool // Track whether to show the delete button
     @Binding var isBold: Bool // Track whether the text is bold
     @Binding var isItalic: Bool // Track whether the text is italic
     @Binding var fontSize: CGFloat // Track the selected font size
     var deleteAction: () -> Void // Action to delete the annotation
     @State private var isDropdownOpen = false
     let availableFontSizes: [CGFloat]
     let colorButtonSize: CGFloat = 24 // Size of the color buttons
     @Environment(\.colorScheme) var colorScheme
     @Binding var isHighlighting: Bool

     
     var body: some View {

         ZStack {
             if !isTyping && !isAddingComment && !showDeleteButton && !isHighlighting{
                 HStack {
                     Button(action: {
                         selectedAnnotationType = nil
                         isAddingComment.toggle()
                     }) {
                         Image(systemName: "rectangle.and.pencil.and.ellipsis")
                     }
                     .foregroundColor(.primary)
                     
                     Button(action: {
                         selectedAnnotationType = .freeText
                         isTyping.toggle()
                     }) {
                         Image(systemName: "pencil.tip")
                     }
                     .foregroundColor(.primary)
                     
                         Button(action: {
                             isHighlighting.toggle()
                         }) {
                             Image(systemName: "highlighter")
                         }
                         .foregroundColor(isHighlighting ? .blue : .black)
                     
                 }
             }
             else if isAddingComment {
                 Button(action: {
                     selectedAnnotationType = nil
                     isAddingComment.toggle()
                 }) {
                     Image(systemName: "rectangle.and.pencil.and.ellipsis")
                 }
                 .foregroundColor(.blue )
             }
             else if isTyping {
                 HStack(spacing: 0) {
                     Button(action: {
                         isBold.toggle()
                     }) {
                         Image(systemName: isBold ? "bold" : "bold")
                     }
                     .foregroundColor(isBold ? .blue : .primary)
                     
                     Button(action: {
                         isItalic.toggle()
                     }) {
                         Image(systemName: isItalic ? "italic" : "italic")
                     }
                     .foregroundColor(isItalic ? .blue : .primary)
                     
                     //ColorButton(color: .black, isSelected: fontColor == .black, action: { fontColor = .black })
                     ColorButton(color: .red, isSelected: fontColor == .red, action: { fontColor = .red })
                     ColorButton(color: .green, isSelected: fontColor == .green, action: { fontColor = .green })
                     ColorButton(color: .blue, isSelected: fontColor == .blue, action: { fontColor = .blue })
                     
                     Menu {
                         ForEach(availableFontSizes, id: \.self) { size in
                             Button(action: {
                                 fontSize = size
                             }) {
                                 Text("\(Int(size))")
                             }
                         }
                     } label: {
                         HStack {
                             Text("Size: \(Int(fontSize))")
                         }
                     }
                     
                     
                     Button(action: {
                         isTyping.toggle()
                     }) {
                         Image(systemName: "pencil.tip")
                             .foregroundColor(isTyping ? .blue : .primary)
                     }
                 }
                 .frame(maxWidth: .infinity)
                 .padding(.horizontal, 8)
             }
             
             else if isHighlighting {
                 Button(action: {
                     isHighlighting.toggle()
                 }) {
                     Image(systemName: "highlighter")
                 }
                 .foregroundColor(isHighlighting ? .blue : .black)

             }
             else if showDeleteButton {
                 Button(action: deleteAction) {
                     Image(systemName: "trash")
                 }
                 .foregroundColor(.red)
             }
             
             
         }

     }
 }

 struct ColorButton: View {
     var color: Color
     var isSelected: Bool
     var action: () -> Void
     
     var body: some View {
         Button(action: action) {
             ZStack {
                 Circle()
                     .fill(color)
                     .frame(width: 5, height: 5)
                 
                 if isSelected {
                     Image(systemName: "checkmark.circle.fill")
                         .foregroundColor(.white)
                 }
             }
         }
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

 class CustomPDFAnnotation: PDFAnnotation {
     var annotationID: String?
 }




 struct DocumentView: View {
     let documentURL: URL
     @State private var showChatDrawer = false
     @State private var showCommentDrawer = false
     @State private var commentMessages: [CommentMessage] = [] // Store comment messages
     @State private var commentText: String?
     @State private var isAddingComment = false // Add isAddingComment state
     @State private var selectedAnnotationType: PDFAnnotationSubtype? // Add selectedAnnotationType state
     @State private var chatMessages: [ChatMessage] = [] // Store chat messages
     @State private var commentAnnotations: [CommentAnnotation] = [] // Store comment annotations
     @State private var selectedAnnotation: PDFAnnotation? // Store the selected annotation
     @State private var selectedOnDocumentAnnotation: CustomPDFAnnotation? // Store the selected annotation
     @State private var isTyping = false // Add isTyping state
     @State private var pdfView: PDFView? // Add pdfView property
     @State private var fontColor: Color = .black // Add a state variable to store the font color
     @State private var showDeleteButton: Bool = false // Track whether to show the delete button
     @State private var isBold: Bool = false // Track whether the text is bold
     @State private var isItalic: Bool = false // Track whether the text is italic
     @State private var fontSize: CGFloat = 16 // Track the selected font size
     let availableFontSizes: [CGFloat] = [8, 10, 12, 14, 16,18, 20, 22, 24, 26, 28, 30, 32]
     @Environment(\.colorScheme) var colorScheme

     @State private var firstTouchLocation: CGPoint?
     @State private var secondTouchLocation: CGPoint?
     @State private var isHighlighting: Bool = false
     @State private var highlightAnnotations: [PDFAnnotation] = []

     
     
     var body: some View {
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
                             .frame(width: 32, height: 32)
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
         
         .toolbar {
             ToolbarItem(placement: .navigationBarTrailing) {
                 AnnotationToolbar(selectedAnnotationType: $selectedAnnotationType, isAddingComment: $isAddingComment, commentText: $commentText, showCommentDrawer: $showCommentDrawer, isTyping: $isTyping, fontColor: $fontColor, showDeleteButton: $showDeleteButton, isBold: $isBold, isItalic: $isItalic, fontSize: $fontSize, deleteAction: deleteAnnotation, availableFontSizes: availableFontSizes, isHighlighting: $isHighlighting)
             }
             ToolbarItem(placement: .navigationBarTrailing) {
                 Spacer()
             }
             
         }
         .sheet(isPresented: $showCommentDrawer) {
             CommentDrawerView(commentMessages: $commentMessages, documentURL: documentURL, commentText: $commentText, isAddingComment: $isAddingComment, selectedAnnotation: $selectedAnnotation, saveCommentAnnotation: saveCommentAnnotation)
         }
         .sheet(isPresented: $showChatDrawer) {
             ChatDrawerView(chatMessages: $chatMessages, documentURL: documentURL, commentText: $commentText)
         }
         .onAppear {
             fetchOnDocumentComment()
             fetchCommentAnnotations()
            fetchHighlightAnnotations()
         }
     }
     
     func handleTapGesture(location: CGPoint) {
         if let pdfView = PDFViewWrapper.pdfView,
            let currentPage = pdfView.currentPage {
             let tapLocation = pdfView.convert(location, to: currentPage)
             
             if let tappedAnnotation = currentPage.annotation(at: tapLocation) {
                 // User tapped on an existing annotation
                 
                 if let customAnnotation = tappedAnnotation as? CustomPDFAnnotation {
                     selectedOnDocumentAnnotation = customAnnotation
                     let annotationWidth = customAnnotation.bounds.size.width
                     
                  //   if annotationWidth == 200 {
                         showDeleteButton = true
                         isTyping = false
                   //  }
                 }
                 else if let pdfAnnotation = tappedAnnotation as? PDFAnnotation{
                     
                     selectedAnnotation = pdfAnnotation
                     let annotationWidth = pdfAnnotation.bounds.size.width
                     if annotationWidth == 30 {
                         // Handle other types of annotations if necessary
                         showCommentDrawer = true
                     }
                     else {
                         showDeleteButton = true
                     }
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
                     createHighlightAnnotation()
                 }
             }
             if isAddingComment {
                 
                 let tapLocation = pdfView.convert(location, to: currentPage)
                 // Create a text annotation at the tapped location
                 let textAnnotation = PDFAnnotation(bounds: CGRect(x: tapLocation.x, y: tapLocation.y, width: 30, height: 30), forType: .freeText, withProperties: nil)
                 textAnnotation.contents = "\(commentMessages.count + 1)" // Calculate the comment count and set it as the annotation content
                 textAnnotation.font = UIFont.boldSystemFont(ofSize: 20) // Adjust the font size if needed
                 textAnnotation.color = .yellow.withAlphaComponent(0.2)
                 textAnnotation.fontColor = .red
                 textAnnotation.alignment = .center
                 // Store the selected annotation
                 
                 
                 selectedAnnotation = textAnnotation
                 
                 // Open the CommentDrawerView
                 showCommentDrawer = true
             }
             
             else if isTyping {
                 // User tapped to create a new annotation
                 let bounds = CGRect(x: tapLocation.x , y: tapLocation.y - 85, width: 200, height: 100)
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
                 freeTextAnnotation.color = .black.withAlphaComponent(0)
                 
                 // Add the annotation to the current page
                 currentPage.addAnnotation(freeTextAnnotation)
                 
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
                 
                 currentPage.addAnnotation(freeTextAnnotation)
                 pdfView.addSubview(annotationLabel)
                 pdfView.addSubview(textField)
                 
                 // Set the selectedAnnotation to the created free text annotation
                 selectedAnnotation = freeTextAnnotation
                 pdfView.becomeFirstResponder()
             }
         }
         
         
         
     }
     
     func createHighlightAnnotation() {
         guard let firstTouchLocation = firstTouchLocation,
               let secondTouchLocation = secondTouchLocation,
               let pdfView = PDFViewWrapper.pdfView,
               let tappedPage = pdfView.page(for: firstTouchLocation, nearest: true) else {
             return
         }
         
         let convertedFirstLocation = pdfView.convert(firstTouchLocation, to: tappedPage)
         let convertedSecondLocation = pdfView.convert(secondTouchLocation, to: tappedPage)
         
         let width: CGFloat
      //   var height = abs(convertedSecondLocation.y - convertedFirstLocation.y)
         
     //    if height < 20 {
             width = abs(convertedSecondLocation.x - convertedFirstLocation.x)
     //        height = 10
     //    } else {
      //       width = tappedPage.bounds(for: .cropBox).width
     //    }
         
         let minY = min(convertedFirstLocation.y, convertedSecondLocation.y)
         let highlightBounds = CGRect(x: convertedFirstLocation.x, y: minY, width: width, height: 10)
         
         let highlightAnnotation = CustomPDFAnnotation(bounds: highlightBounds, forType: .highlight, withProperties: nil)
         tappedPage.addAnnotation(highlightAnnotation)
         
         // Reset touch locations for future highlights
         self.firstTouchLocation = nil
         self.secondTouchLocation = nil
         
        // isHighlighting = false
         
         // Save the highlight annotation to Firestore
         saveHighlightAnnotation(highlightAnnotation)
     }

     func saveHighlightAnnotation(_ annotation: CustomPDFAnnotation) {
         guard let currentUserEmail = Auth.auth().currentUser?.email else {
             print("User is not signed in.")
             return
         }
         
         guard let pdfView = PDFViewWrapper.pdfView,
               let currentPage = pdfView.currentPage,
               let pageIndex = pdfView.document?.index(for: currentPage) else {
             print("Failed to get current page or index.")
             return
         }


         let db = Firestore.firestore()
         
         // Generate a unique ID for the free text annotation
         let annotationID = UUID().uuidString

         let annotationRef = db.collection("highlightAnnotations").document(documentURL.lastPathComponent).collection("annotations").document(annotationID)

         
         let bounds = annotation.bounds
         let boundsData: [String: Any] = [
             "x": bounds.origin.x,
             "y": bounds.origin.y,
             "width": bounds.size.width,
             "height": bounds.size.height
         ]
         
         let annotationData: [String: Any] = [
             "documentURL": documentURL.absoluteString,
             "pageIndex": pageIndex,
             "bounds": boundsData,
             "senderEmail": currentUserEmail,
             "annotationID": annotationID,

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
     
     func saveOnDocumentComment(_ annotation: CustomPDFAnnotation) {
         guard let currentUserEmail = Auth.auth().currentUser?.email else {
             print("User is not signed in.")
             return
         }
         
         guard let pdfView = PDFViewWrapper.pdfView,
               let currentPage = pdfView.currentPage,
               let pageIndex = pdfView.document?.index(for: currentPage) else {
             print("Failed to get current page or index.")
             return
         }
         
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
             "pageNumber": pageIndex + 1, // Add the page number (incremented by 1 since pages are 0-indexed)
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
     
     func fetchHighlightAnnotations() {
         print("Fetching highlight annotations")
         
         guard let currentUserEmail = Auth.auth().currentUser?.email else {
             print("User is not signed in.")
             return
         }
         
         let db = Firestore.firestore()
         let annotationsCollection = db.collection("highlightAnnotations").document(documentURL.lastPathComponent).collection("annotations")
         
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
                     } else {
                         print("Invalid page index: \(pageIndex)")
                     }
                 }
             } else {
                 print("PDFView is nil.")
             }
         }
     }


     func fetchOnDocumentComment() {
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
                     
                     
                     var traits = getFontSymbolicTraits()
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
                     
                     if let currentPage = pdfView.document?.page(at: pageNumber - 1) {
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


     
     func sendButtonTapped() {
         guard let pdfView = PDFViewWrapper.pdfView,
               let textField = pdfView.subviews.first(where: { $0 is UITextField }) as? UITextField,
               let selectedAnnotation = selectedAnnotation as? PDFAnnotation else {
             return
         }
         
         selectedAnnotation.contents = textField.text ?? ""
         
         var traits = getFontSymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         
         let currentFontSize = selectedAnnotation.font?.pointSize ?? 16
         let resizedFontDescriptor = selectedAnnotation.font?.fontDescriptor.withSymbolicTraits(traits)
         let resizedFont = UIFont(descriptor: resizedFontDescriptor ?? UIFontDescriptor(), size: currentFontSize)
         
         selectedAnnotation.font = resizedFont
         
         textField.resignFirstResponder() // Hide the keyboard
         textField.removeFromSuperview() // Remove the textField from its superview
         
         if let freeTextAnnotation = selectedAnnotation as? CustomPDFAnnotation {
             saveOnDocumentComment(freeTextAnnotation)
             

         }
         isTyping = false
         showDeleteButton = false
         // Trigger a re-draw of the PDF view to reflect the updated annotation appearance
         pdfView.setNeedsDisplay()
     }
     
     func getFontSymbolicTraits() -> UIFontDescriptor.SymbolicTraits {
         var traits = UIFontDescriptor.SymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         return traits
     }
     
     func deleteButtonClicked(annotation: CustomPDFAnnotation) {
         // Remove the annotation from the PDF view
         guard let pdfView = PDFViewWrapper.pdfView,
               let currentPage = pdfView.currentPage else {
             print("Failed to get current page or PDF view.")
             return
         }
         
         currentPage.removeAnnotation(annotation)
         
         // Remove the annotation from Firestore
         guard let annotationID = annotation.annotationID else {
             print("Annotation ID not found.")
             return
         }
         
         let db = Firestore.firestore()
         let annotationsCollection = db.collection("highlightAnnotations")
         
         annotationsCollection.whereField("annotationID", isEqualTo: annotationID)
             .getDocuments { querySnapshot, error in
                 if let error = error {
                     print("Error fetching annotation to delete: \(error.localizedDescription)")
                     return
                 }
                 
                 guard let documents = querySnapshot?.documents else {
                     print("No annotations found to delete.")
                     return
                 }
                 
                 for document in documents {
                     document.reference.delete { error in
                         if let error = error {
                             print("Error deleting annotation from Firestore: \(error.localizedDescription)")
                         } else {
                             print("Annotation deleted from Firestore")
                         }
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


     
     
     
     func saveCommentAnnotation(_ annotation: PDFAnnotation) {
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
     
     
     func fetchCommentAnnotations() {
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

 struct PDFViewWrapper: UIViewRepresentable {
     let url: URL
     let handleTapGesture: (CGPoint) -> Void
     static var pdfView: PDFView? // Static reference to access pdfView
     
     func makeUIView(context: Context) -> PDFView {
         let pdfView = PDFView()
         pdfView.autoScales = true
         pdfView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = pdfView // Assign pdfView to static property
         
         let gestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
         pdfView.addGestureRecognizer(gestureRecognizer)
         
         return pdfView
     }
     
     func updateUIView(_ uiView: PDFView, context: Context) {
         uiView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = uiView // Update the static reference
     }
     
     func makeCoordinator() -> Coordinator {
         Coordinator(self)
     }
     
     class Coordinator: NSObject {
         let pdfViewWrapper: PDFViewWrapper
         
         init(_ pdfViewWrapper: PDFViewWrapper) {
             self.pdfViewWrapper = pdfViewWrapper
         }
         
         @objc func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
             let location = gestureRecognizer.location(in: PDFViewWrapper.pdfView)
             pdfViewWrapper.handleTapGesture(location)
         }
     }
     
     // Function to add an annotation to the current PDFPage
     static func addAnnotationToCurrentPage(annotation: PDFAnnotation) {
         if let currentPage = pdfView?.currentPage {
             currentPage.addAnnotation(annotation)
             pdfView?.setNeedsDisplay()
         }
     }
 }




 struct AnnotationToolbar: View {
     @Binding var selectedAnnotationType: PDFAnnotationSubtype?
     @Binding var isAddingComment: Bool
     @Binding var commentText: String?
     @Binding var showCommentDrawer: Bool
     @Binding var isTyping: Bool
     @Binding var fontColor: Color // Use Color instead of UIColor
     @Binding var showDeleteButton: Bool // Track whether to show the delete button
     @Binding var isBold: Bool // Track whether the text is bold
     @Binding var isItalic: Bool // Track whether the text is italic
     @Binding var fontSize: CGFloat // Track the selected font size
     var deleteAction: () -> Void // Action to delete the annotation
     @State private var isDropdownOpen = false
     let availableFontSizes: [CGFloat]
     let colorButtonSize: CGFloat = 24 // Size of the color buttons
     @Environment(\.colorScheme) var colorScheme
     @Binding var isHighlighting: Bool

     
     var body: some View {

         ZStack {
             if !isTyping && !isAddingComment && !showDeleteButton && !isHighlighting{
                 HStack {
                     Button(action: {
                         selectedAnnotationType = nil
                         isAddingComment.toggle()
                     }) {
                         Image(systemName: "rectangle.and.pencil.and.ellipsis")
                     }
                     .foregroundColor(.primary)
                     
                     Button(action: {
                         selectedAnnotationType = .freeText
                         isTyping.toggle()
                     }) {
                         Image(systemName: "pencil.tip")
                     }
                     .foregroundColor(.primary)
                     
                         Button(action: {
                             isHighlighting.toggle()
                         }) {
                             Image(systemName: "highlighter")
                         }
                         .foregroundColor(isHighlighting ? .blue : .black)
                     
                 }
             }
             else if isAddingComment {
                 Button(action: {
                     selectedAnnotationType = nil
                     isAddingComment.toggle()
                 }) {
                     Image(systemName: "rectangle.and.pencil.and.ellipsis")
                 }
                 .foregroundColor(.blue )
             }
             else if isTyping {
                 HStack(spacing: 0) {
                     Button(action: {
                         isBold.toggle()
                     }) {
                         Image(systemName: isBold ? "bold" : "bold")
                     }
                     .foregroundColor(isBold ? .blue : .primary)
                     
                     Button(action: {
                         isItalic.toggle()
                     }) {
                         Image(systemName: isItalic ? "italic" : "italic")
                     }
                     .foregroundColor(isItalic ? .blue : .primary)
                     
                     //ColorButton(color: .black, isSelected: fontColor == .black, action: { fontColor = .black })
                     ColorButton(color: .red, isSelected: fontColor == .red, action: { fontColor = .red })
                     ColorButton(color: .green, isSelected: fontColor == .green, action: { fontColor = .green })
                     ColorButton(color: .blue, isSelected: fontColor == .blue, action: { fontColor = .blue })
                     
                     Menu {
                         ForEach(availableFontSizes, id: \.self) { size in
                             Button(action: {
                                 fontSize = size
                             }) {
                                 Text("\(Int(size))")
                             }
                         }
                     } label: {
                         HStack {
                             Text("Size: \(Int(fontSize))")
                         }
                     }
                     
                     
                     Button(action: {
                         isTyping.toggle()
                     }) {
                         Image(systemName: "pencil.tip")
                             .foregroundColor(isTyping ? .blue : .primary)
                     }
                 }
                 .frame(maxWidth: .infinity)
                 .padding(.horizontal, 8)
             }
             
             else if isHighlighting {
                 Button(action: {
                     isHighlighting.toggle()
                 }) {
                     Image(systemName: "highlighter")
                 }
                 .foregroundColor(isHighlighting ? .blue : .black)

             }
             else if showDeleteButton {
                 Button(action: deleteAction) {
                     Image(systemName: "trash")
                 }
                 .foregroundColor(.red)
             }
             
             
         }

     }
 }

 struct ColorButton: View {
     var color: Color
     var isSelected: Bool
     var action: () -> Void
     
     var body: some View {
         Button(action: action) {
             ZStack {
                 Circle()
                     .fill(color)
                     .frame(width: 5, height: 5)
                 
                 if isSelected {
                     Image(systemName: "checkmark.circle.fill")
                         .foregroundColor(.white)
                 }
             }
         }
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

 class CustomPDFAnnotation: PDFAnnotation {
     var annotationID: String?
 }




 struct DocumentView: View {
     let documentURL: URL
     @State private var showChatDrawer = false
     @State private var showCommentDrawer = false
     @State private var commentMessages: [CommentMessage] = [] // Store comment messages
     @State private var commentText: String?
     @State private var isAddingComment = false // Add isAddingComment state
     @State private var selectedAnnotationType: PDFAnnotationSubtype? // Add selectedAnnotationType state
     @State private var chatMessages: [ChatMessage] = [] // Store chat messages
     @State private var commentAnnotations: [CommentAnnotation] = [] // Store comment annotations
     @State private var selectedAnnotation: PDFAnnotation? // Store the selected annotation
     @State private var selectedOnDocumentAnnotation: CustomPDFAnnotation? // Store the selected annotation
     @State private var isTyping = false // Add isTyping state
     @State private var pdfView: PDFView? // Add pdfView property
     @State private var fontColor: Color = .black // Add a state variable to store the font color
     @State private var showDeleteButton: Bool = false // Track whether to show the delete button
     @State private var isBold: Bool = false // Track whether the text is bold
     @State private var isItalic: Bool = false // Track whether the text is italic
     @State private var fontSize: CGFloat = 16 // Track the selected font size
     let availableFontSizes: [CGFloat] = [8, 10, 12, 14, 16,18, 20, 22, 24, 26, 28, 30, 32]
     @Environment(\.colorScheme) var colorScheme

     @State private var firstTouchLocation: CGPoint?
     @State private var secondTouchLocation: CGPoint?
     @State private var isHighlighting: Bool = false
     @State private var highlightAnnotations: [PDFAnnotation] = []

     
     
     var body: some View {
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
                             .frame(width: 32, height: 32)
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
         
         .toolbar {
             ToolbarItem(placement: .navigationBarTrailing) {
                 AnnotationToolbar(selectedAnnotationType: $selectedAnnotationType, isAddingComment: $isAddingComment, commentText: $commentText, showCommentDrawer: $showCommentDrawer, isTyping: $isTyping, fontColor: $fontColor, showDeleteButton: $showDeleteButton, isBold: $isBold, isItalic: $isItalic, fontSize: $fontSize, deleteAction: deleteAnnotation, availableFontSizes: availableFontSizes, isHighlighting: $isHighlighting)
             }
             ToolbarItem(placement: .navigationBarTrailing) {
                 Spacer()
             }
             
         }
         .sheet(isPresented: $showCommentDrawer) {
             CommentDrawerView(commentMessages: $commentMessages, documentURL: documentURL, commentText: $commentText, isAddingComment: $isAddingComment, selectedAnnotation: $selectedAnnotation, saveCommentAnnotation: saveCommentAnnotation)
         }
         .sheet(isPresented: $showChatDrawer) {
             ChatDrawerView(chatMessages: $chatMessages, documentURL: documentURL, commentText: $commentText)
         }
         .onAppear {
             fetchOnDocumentComment()
             fetchCommentAnnotations()
            fetchHighlightAnnotations()
         }
     }
     
     func handleTapGesture(location: CGPoint) {
         if let pdfView = PDFViewWrapper.pdfView,
            let currentPage = pdfView.currentPage {
             let tapLocation = pdfView.convert(location, to: currentPage)
             
             if let tappedAnnotation = currentPage.annotation(at: tapLocation) {
                 // User tapped on an existing annotation
                 
                 if let customAnnotation = tappedAnnotation as? CustomPDFAnnotation {
                     selectedOnDocumentAnnotation = customAnnotation
                     let annotationWidth = customAnnotation.bounds.size.width
                     
                  //   if annotationWidth == 200 {
                         showDeleteButton = true
                         isTyping = false
                   //  }
                 }
                 else if let pdfAnnotation = tappedAnnotation as? PDFAnnotation{
                     
                     selectedAnnotation = pdfAnnotation
                     let annotationWidth = pdfAnnotation.bounds.size.width
                     if annotationWidth == 30 {
                         // Handle other types of annotations if necessary
                         showCommentDrawer = true
                     }
                     else {
                         showDeleteButton = true
                     }
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
                     createHighlightAnnotation()
                 }
             }
             if isAddingComment {
                 
                 let tapLocation = pdfView.convert(location, to: currentPage)
                 // Create a text annotation at the tapped location
                 let textAnnotation = PDFAnnotation(bounds: CGRect(x: tapLocation.x, y: tapLocation.y, width: 30, height: 30), forType: .freeText, withProperties: nil)
                 textAnnotation.contents = "\(commentMessages.count + 1)" // Calculate the comment count and set it as the annotation content
                 textAnnotation.font = UIFont.boldSystemFont(ofSize: 20) // Adjust the font size if needed
                 textAnnotation.color = .yellow.withAlphaComponent(0.2)
                 textAnnotation.fontColor = .red
                 textAnnotation.alignment = .center
                 // Store the selected annotation
                 
                 
                 selectedAnnotation = textAnnotation
                 
                 // Open the CommentDrawerView
                 showCommentDrawer = true
             }
             
             else if isTyping {
                 // User tapped to create a new annotation
                 let bounds = CGRect(x: tapLocation.x , y: tapLocation.y - 85, width: 200, height: 100)
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
                 freeTextAnnotation.color = .black.withAlphaComponent(0)
                 
                 // Add the annotation to the current page
                 currentPage.addAnnotation(freeTextAnnotation)
                 
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
                 
                 currentPage.addAnnotation(freeTextAnnotation)
                 pdfView.addSubview(annotationLabel)
                 pdfView.addSubview(textField)
                 
                 // Set the selectedAnnotation to the created free text annotation
                 selectedAnnotation = freeTextAnnotation
                 pdfView.becomeFirstResponder()
             }
         }
         
         
         
     }
     
     func createHighlightAnnotation() {
         guard let firstTouchLocation = firstTouchLocation,
               let secondTouchLocation = secondTouchLocation,
               let pdfView = PDFViewWrapper.pdfView,
               let tappedPage = pdfView.page(for: firstTouchLocation, nearest: true) else {
             return
         }
         
         let convertedFirstLocation = pdfView.convert(firstTouchLocation, to: tappedPage)
         let convertedSecondLocation = pdfView.convert(secondTouchLocation, to: tappedPage)
         
         let width: CGFloat
         var height = abs(convertedSecondLocation.y - convertedFirstLocation.y)
         
         if height < 20 {
             width = abs(convertedSecondLocation.x - convertedFirstLocation.x)
             height = 10
         } else {
             width = tappedPage.bounds(for: .cropBox).width
         }
         
         let minY = min(convertedFirstLocation.y, convertedSecondLocation.y)
         let highlightBounds = CGRect(x: convertedFirstLocation.x, y: minY, width: width, height: height)
         
         let highlightAnnotation = CustomPDFAnnotation(bounds: highlightBounds, forType: .highlight, withProperties: nil)
         tappedPage.addAnnotation(highlightAnnotation)
         
         // Reset touch locations for future highlights
         self.firstTouchLocation = nil
         self.secondTouchLocation = nil
         
         isHighlighting = false
         
         // Save the highlight annotation to Firestore
         saveHighlightAnnotation(highlightAnnotation)
     }

     func saveHighlightAnnotation(_ annotation: CustomPDFAnnotation) {
         guard let currentUserEmail = Auth.auth().currentUser?.email else {
             print("User is not signed in.")
             return
         }
         
         guard let pdfView = PDFViewWrapper.pdfView,
               let currentPage = pdfView.currentPage,
               let pageIndex = pdfView.document?.index(for: currentPage) else {
             print("Failed to get current page or index.")
             return
         }


         let db = Firestore.firestore()
         
         // Generate a unique ID for the free text annotation
         let annotationID = UUID().uuidString

         let annotationRef = db.collection("highlightAnnotations").document(documentURL.lastPathComponent).collection("annotations").document(annotationID)

         
         let bounds = annotation.bounds
         let boundsData: [String: Any] = [
             "x": bounds.origin.x,
             "y": bounds.origin.y,
             "width": bounds.size.width,
             "height": bounds.size.height
         ]
         
         let annotationData: [String: Any] = [
             "documentURL": documentURL.absoluteString,
             "pageIndex": pageIndex,
             "bounds": boundsData,
             "senderEmail": currentUserEmail,
             "annotationID": annotationID,

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
     
     func saveOnDocumentComment(_ annotation: CustomPDFAnnotation) {
         guard let currentUserEmail = Auth.auth().currentUser?.email else {
             print("User is not signed in.")
             return
         }
         
         guard let pdfView = PDFViewWrapper.pdfView,
               let currentPage = pdfView.currentPage,
               let pageIndex = pdfView.document?.index(for: currentPage) else {
             print("Failed to get current page or index.")
             return
         }
         
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
             "pageNumber": pageIndex + 1, // Add the page number (incremented by 1 since pages are 0-indexed)
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
     
     func fetchHighlightAnnotations() {
         print("Fetching highlight annotations")
         
         guard let currentUserEmail = Auth.auth().currentUser?.email else {
             print("User is not signed in.")
             return
         }
         
         let db = Firestore.firestore()
         let annotationsCollection = db.collection("highlightAnnotations").document(documentURL.lastPathComponent).collection("annotations")
         
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
                     } else {
                         print("Invalid page index: \(pageIndex)")
                     }
                 }
             } else {
                 print("PDFView is nil.")
             }
         }
     }


     func fetchOnDocumentComment() {
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
                     
                     
                     var traits = getFontSymbolicTraits()
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
                     
                     if let currentPage = pdfView.document?.page(at: pageNumber - 1) {
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


     
     func sendButtonTapped() {
         guard let pdfView = PDFViewWrapper.pdfView,
               let textField = pdfView.subviews.first(where: { $0 is UITextField }) as? UITextField,
               let selectedAnnotation = selectedAnnotation as? PDFAnnotation else {
             return
         }
         
         selectedAnnotation.contents = textField.text ?? ""
         
         var traits = getFontSymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         
         let currentFontSize = selectedAnnotation.font?.pointSize ?? 16
         let resizedFontDescriptor = selectedAnnotation.font?.fontDescriptor.withSymbolicTraits(traits)
         let resizedFont = UIFont(descriptor: resizedFontDescriptor ?? UIFontDescriptor(), size: currentFontSize)
         
         selectedAnnotation.font = resizedFont
         
         textField.resignFirstResponder() // Hide the keyboard
         textField.removeFromSuperview() // Remove the textField from its superview
         
         if let freeTextAnnotation = selectedAnnotation as? CustomPDFAnnotation {
             saveOnDocumentComment(freeTextAnnotation)
             

         }
         isTyping = false
         showDeleteButton = false
         // Trigger a re-draw of the PDF view to reflect the updated annotation appearance
         pdfView.setNeedsDisplay()
     }
     
     func getFontSymbolicTraits() -> UIFontDescriptor.SymbolicTraits {
         var traits = UIFontDescriptor.SymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         return traits
     }
     
     func deleteButtonClicked(annotation: CustomPDFAnnotation) {
         // Remove the annotation from the PDF view
         guard let pdfView = PDFViewWrapper.pdfView,
               let currentPage = pdfView.currentPage else {
             print("Failed to get current page or PDF view.")
             return
         }
         
         currentPage.removeAnnotation(annotation)
         
         // Remove the annotation from Firestore
         guard let annotationID = annotation.annotationID else {
             print("Annotation ID not found.")
             return
         }
         
         let db = Firestore.firestore()
         let annotationsCollection = db.collection("highlightAnnotations")
         
         annotationsCollection.whereField("annotationID", isEqualTo: annotationID)
             .getDocuments { querySnapshot, error in
                 if let error = error {
                     print("Error fetching annotation to delete: \(error.localizedDescription)")
                     return
                 }
                 
                 guard let documents = querySnapshot?.documents else {
                     print("No annotations found to delete.")
                     return
                 }
                 
                 for document in documents {
                     document.reference.delete { error in
                         if let error = error {
                             print("Error deleting annotation from Firestore: \(error.localizedDescription)")
                         } else {
                             print("Annotation deleted from Firestore")
                         }
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
                 
                 // Refresh the PDF view to reflect the changes
                 if let currentPage = pdfView.currentPage {
                     pdfView.go(to: PDFDestination(page: currentPage, at: .zero))
                 }
             }
         }
         
         
         showDeleteButton = false
         //  deselectAnnotation()
     }


     
     
     
     func saveCommentAnnotation(_ annotation: PDFAnnotation) {
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
     
     
     func fetchCommentAnnotations() {
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

 struct PDFViewWrapper: UIViewRepresentable {
     let url: URL
     let handleTapGesture: (CGPoint) -> Void
     static var pdfView: PDFView? // Static reference to access pdfView
     
     func makeUIView(context: Context) -> PDFView {
         let pdfView = PDFView()
         pdfView.autoScales = true
         pdfView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = pdfView // Assign pdfView to static property
         
         let gestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
         pdfView.addGestureRecognizer(gestureRecognizer)
         
         return pdfView
     }
     
     func updateUIView(_ uiView: PDFView, context: Context) {
         uiView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = uiView // Update the static reference
     }
     
     func makeCoordinator() -> Coordinator {
         Coordinator(self)
     }
     
     class Coordinator: NSObject {
         let pdfViewWrapper: PDFViewWrapper
         
         init(_ pdfViewWrapper: PDFViewWrapper) {
             self.pdfViewWrapper = pdfViewWrapper
         }
         
         @objc func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
             let location = gestureRecognizer.location(in: PDFViewWrapper.pdfView)
             pdfViewWrapper.handleTapGesture(location)
         }
     }
     
     // Function to add an annotation to the current PDFPage
     static func addAnnotationToCurrentPage(annotation: PDFAnnotation) {
         if let currentPage = pdfView?.currentPage {
             currentPage.addAnnotation(annotation)
             pdfView?.setNeedsDisplay()
         }
     }
 }




 struct AnnotationToolbar: View {
     @Binding var selectedAnnotationType: PDFAnnotationSubtype?
     @Binding var isAddingComment: Bool
     @Binding var commentText: String?
     @Binding var showCommentDrawer: Bool
     @Binding var isTyping: Bool
     @Binding var fontColor: Color // Use Color instead of UIColor
     @Binding var showDeleteButton: Bool // Track whether to show the delete button
     @Binding var isBold: Bool // Track whether the text is bold
     @Binding var isItalic: Bool // Track whether the text is italic
     @Binding var fontSize: CGFloat // Track the selected font size
     var deleteAction: () -> Void // Action to delete the annotation
     @State private var isDropdownOpen = false
     let availableFontSizes: [CGFloat]
     let colorButtonSize: CGFloat = 24 // Size of the color buttons
     @Environment(\.colorScheme) var colorScheme
     @Binding var isHighlighting: Bool

     
     var body: some View {

         ZStack {
             if !isTyping && !isAddingComment && !showDeleteButton && !isHighlighting{
                 HStack {
                     Button(action: {
                         selectedAnnotationType = nil
                         isAddingComment.toggle()
                     }) {
                         Image(systemName: "rectangle.and.pencil.and.ellipsis")
                     }
                     .foregroundColor(.primary)
                     
                     Button(action: {
                         selectedAnnotationType = .freeText
                         isTyping.toggle()
                     }) {
                         Image(systemName: "pencil.tip")
                     }
                     .foregroundColor(.primary)
                     
                         Button(action: {
                             isHighlighting.toggle()
                         }) {
                             Image(systemName: "highlighter")
                         }
                         .foregroundColor(isHighlighting ? .blue : .black)
                     
                 }
             }
             else if isAddingComment {
                 Button(action: {
                     selectedAnnotationType = nil
                     isAddingComment.toggle()
                 }) {
                     Image(systemName: "rectangle.and.pencil.and.ellipsis")
                 }
                 .foregroundColor(.blue )
             }
             else if isTyping {
                 HStack(spacing: 0) {
                     Button(action: {
                         isBold.toggle()
                     }) {
                         Image(systemName: isBold ? "bold" : "bold")
                     }
                     .foregroundColor(isBold ? .blue : .primary)
                     
                     Button(action: {
                         isItalic.toggle()
                     }) {
                         Image(systemName: isItalic ? "italic" : "italic")
                     }
                     .foregroundColor(isItalic ? .blue : .primary)
                     
                     //ColorButton(color: .black, isSelected: fontColor == .black, action: { fontColor = .black })
                     ColorButton(color: .red, isSelected: fontColor == .red, action: { fontColor = .red })
                     ColorButton(color: .green, isSelected: fontColor == .green, action: { fontColor = .green })
                     ColorButton(color: .blue, isSelected: fontColor == .blue, action: { fontColor = .blue })
                     
                     Menu {
                         ForEach(availableFontSizes, id: \.self) { size in
                             Button(action: {
                                 fontSize = size
                             }) {
                                 Text("\(Int(size))")
                             }
                         }
                     } label: {
                         HStack {
                             Text("Size: \(Int(fontSize))")
                         }
                     }
                     
                     
                     Button(action: {
                         isTyping.toggle()
                     }) {
                         Image(systemName: "pencil.tip")
                             .foregroundColor(isTyping ? .blue : .primary)
                     }
                 }
                 .frame(maxWidth: .infinity)
                 .padding(.horizontal, 8)
             }
             
             else if isHighlighting {
                 Button(action: {
                     isHighlighting.toggle()
                 }) {
                     Image(systemName: "highlighter")
                 }
                 .foregroundColor(isHighlighting ? .blue : .black)

             }
             else if showDeleteButton {
                 Button(action: deleteAction) {
                     Image(systemName: "trash")
                 }
                 .foregroundColor(.red)
             }
             
             
         }

     }
 }

 struct ColorButton: View {
     var color: Color
     var isSelected: Bool
     var action: () -> Void
     
     var body: some View {
         Button(action: action) {
             ZStack {
                 Circle()
                     .fill(color)
                     .frame(width: 5, height: 5)
                 
                 if isSelected {
                     Image(systemName: "checkmark.circle.fill")
                         .foregroundColor(.white)
                 }
             }
         }
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

 class CustomPDFAnnotation: PDFAnnotation {
     var annotationID: String?
 }




 struct DocumentView: View {
     let documentURL: URL
     @State private var showChatDrawer = false
     @State private var showCommentDrawer = false
     @State private var commentMessages: [CommentMessage] = [] // Store comment messages
     @State private var commentText: String?
     @State private var isAddingComment = false // Add isAddingComment state
     @State private var selectedAnnotationType: PDFAnnotationSubtype? // Add selectedAnnotationType state
     @State private var chatMessages: [ChatMessage] = [] // Store chat messages
     @State private var commentAnnotations: [CommentAnnotation] = [] // Store comment annotations
     @State private var selectedAnnotation: PDFAnnotation? // Store the selected annotation
     @State private var selectedOnDocumentAnnotation: CustomPDFAnnotation? // Store the selected annotation
     @State private var isTyping = false // Add isTyping state
     @State private var pdfView: PDFView? // Add pdfView property
     @State private var fontColor: Color = .black // Add a state variable to store the font color
     @State private var showDeleteButton: Bool = false // Track whether to show the delete button
     @State private var isBold: Bool = false // Track whether the text is bold
     @State private var isItalic: Bool = false // Track whether the text is italic
     @State private var fontSize: CGFloat = 16 // Track the selected font size
     let availableFontSizes: [CGFloat] = [8, 10, 12, 14, 16,18, 20, 22, 24, 26, 28, 30, 32]
     @Environment(\.colorScheme) var colorScheme

     @State private var firstTouchLocation: CGPoint?
     @State private var secondTouchLocation: CGPoint?
     @State private var isHighlighting: Bool = false
     @State private var highlightAnnotations: [PDFAnnotation] = []

     
     
     var body: some View {
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
                             .frame(width: 32, height: 32)
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
         
         .toolbar {
             ToolbarItem(placement: .navigationBarTrailing) {
                 AnnotationToolbar(selectedAnnotationType: $selectedAnnotationType, isAddingComment: $isAddingComment, commentText: $commentText, showCommentDrawer: $showCommentDrawer, isTyping: $isTyping, fontColor: $fontColor, showDeleteButton: $showDeleteButton, isBold: $isBold, isItalic: $isItalic, fontSize: $fontSize, deleteAction: deleteAnnotation, availableFontSizes: availableFontSizes, isHighlighting: $isHighlighting)
             }
             ToolbarItem(placement: .navigationBarTrailing) {
                 Spacer()
             }
             
         }
         .sheet(isPresented: $showCommentDrawer) {
             CommentDrawerView(commentMessages: $commentMessages, documentURL: documentURL, commentText: $commentText, isAddingComment: $isAddingComment, selectedAnnotation: $selectedAnnotation, saveCommentAnnotation: saveCommentAnnotation)
         }
         .sheet(isPresented: $showChatDrawer) {
             ChatDrawerView(chatMessages: $chatMessages, documentURL: documentURL, commentText: $commentText)
         }
         .onAppear {
             fetchOnDocumentComment()
             fetchCommentAnnotations()
             fetchHighlightAnnotations()
         }
     }
     
     func handleTapGesture(location: CGPoint) {
         if let pdfView = PDFViewWrapper.pdfView,
            let currentPage = pdfView.currentPage {
             let tapLocation = pdfView.convert(location, to: currentPage)
             
             if let tappedAnnotation = currentPage.annotation(at: tapLocation) {
                 // User tapped on an existing annotation
                 
                 if let customAnnotation = tappedAnnotation as? CustomPDFAnnotation {
                     selectedOnDocumentAnnotation = customAnnotation
                     let annotationWidth = customAnnotation.bounds.size.width
                     
                  //   if annotationWidth == 200 {
                         showDeleteButton = true
                         isTyping = false
                   //  }
                 }
                 else if let pdfAnnotation = tappedAnnotation as? PDFAnnotation{
                     
                     selectedAnnotation = pdfAnnotation
                     let annotationWidth = pdfAnnotation.bounds.size.width
                     if annotationWidth == 30 {
                         // Handle other types of annotations if necessary
                         showCommentDrawer = true
                     }
                     else {
                         showDeleteButton = true
                     }
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
                     createHighlightAnnotation()
                 }
             }
             if isAddingComment {
                 
                 let tapLocation = pdfView.convert(location, to: currentPage)
                 // Create a text annotation at the tapped location
                 let textAnnotation = PDFAnnotation(bounds: CGRect(x: tapLocation.x, y: tapLocation.y, width: 30, height: 30), forType: .freeText, withProperties: nil)
                 textAnnotation.contents = "\(commentMessages.count + 1)" // Calculate the comment count and set it as the annotation content
                 textAnnotation.font = UIFont.boldSystemFont(ofSize: 20) // Adjust the font size if needed
                 textAnnotation.color = .yellow.withAlphaComponent(0.2)
                 textAnnotation.fontColor = .red
                 textAnnotation.alignment = .center
                 // Store the selected annotation
                 
                 
                 selectedAnnotation = textAnnotation
                 
                 // Open the CommentDrawerView
                 showCommentDrawer = true
             }
             
             else if isTyping {
                 // User tapped to create a new annotation
                 let bounds = CGRect(x: tapLocation.x , y: tapLocation.y - 85, width: 200, height: 100)
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
                 freeTextAnnotation.color = .black.withAlphaComponent(0)
                 
                 // Add the annotation to the current page
                 currentPage.addAnnotation(freeTextAnnotation)
                 
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
                 
                 currentPage.addAnnotation(freeTextAnnotation)
                 pdfView.addSubview(annotationLabel)
                 pdfView.addSubview(textField)
                 
                 // Set the selectedAnnotation to the created free text annotation
                 selectedAnnotation = freeTextAnnotation
                 pdfView.becomeFirstResponder()
             }
         }
         
         
         
     }
     
     func createHighlightAnnotation() {
         guard let firstTouchLocation = firstTouchLocation,
               let secondTouchLocation = secondTouchLocation,
               let pdfView = PDFViewWrapper.pdfView,
               let tappedPage = pdfView.page(for: firstTouchLocation, nearest: true) else {
             return
         }
         
         let convertedFirstLocation = pdfView.convert(firstTouchLocation, to: tappedPage)
         let convertedSecondLocation = pdfView.convert(secondTouchLocation, to: tappedPage)
         
         let width: CGFloat
         var height = abs(convertedSecondLocation.y - convertedFirstLocation.y)
         
         if height < 20 {
             width = abs(convertedSecondLocation.x - convertedFirstLocation.x)
             height = 10
         } else {
             width = tappedPage.bounds(for: .cropBox).width
         }
         
         let minY = min(convertedFirstLocation.y, convertedSecondLocation.y)
         let highlightBounds = CGRect(x: convertedFirstLocation.x, y: minY, width: width, height: height)
         
         let highlightAnnotation = CustomPDFAnnotation(bounds: highlightBounds, forType: .highlight, withProperties: nil)
         tappedPage.addAnnotation(highlightAnnotation)
         
         // Reset touch locations for future highlights
         self.firstTouchLocation = nil
         self.secondTouchLocation = nil
         
         isHighlighting = false
         
         // Save the highlight annotation to Firestore
         saveHighlightAnnotation(highlightAnnotation)
     }

     func saveHighlightAnnotation(_ annotation: CustomPDFAnnotation) {
         guard let pdfView = PDFViewWrapper.pdfView,
               let currentPage = pdfView.currentPage,
               let pageIndex = pdfView.document?.index(for: currentPage) else {
             print("Failed to get current page or index.")
             return
         }
         
         let db = Firestore.firestore()
         let annotationsCollection = db.collection("highlightAnnotations")
         
         let bounds = annotation.bounds
         let boundsData: [String: Any] = [
             "x": bounds.origin.x,
             "y": bounds.origin.y,
             "width": bounds.size.width,
             "height": bounds.size.height
         ]
         
         let annotationData: [String: Any] = [
             "documentURL": documentURL.absoluteString,
             "pageIndex": pageIndex,
             "bounds": boundsData
         ]
         
         annotationsCollection.addDocument(data: annotationData) { error in
             if let error = error {
                 // Handle the error appropriately
                 print("Error saving highlight annotation to Firestore: \(error)")
             } else {
                 // Saving successful
                 print("Highlight annotation saved to Firestore")
             }
         }
     }

     func fetchHighlightAnnotations() {
         let annotationsCollection = Firestore.firestore().collection("highlightAnnotations")
         
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
                     
                     // Retrieve the annotation data from Firestore
                     guard let bounds = data["bounds"] as? [String: CGFloat],
                           let x = bounds["x"],
                           let y = bounds["y"],
                           let width = bounds["width"],
                           let height = bounds["height"],
                           let documentURLString = data["documentURL"] as? String,
                           let pageIndex = data["pageIndex"] as? Int else {
                         print("Error parsing annotation data.")
                         continue
                     }
                     
                     let documentURL = URL(string: documentURLString)
                     
                     // Create the annotation object and set its properties
                     let annotationBounds = CGRect(x: x, y: y, width: width, height: height)
                     let annotation = PDFAnnotation(bounds: annotationBounds, forType: .highlight, withProperties: nil)
                     
                     
                     if let currentPage = pdfView.document?.page(at: pageIndex ) {
                         currentPage.addAnnotation(annotation)
                     } else {
                         print("Invalid page number: \(pageIndex)")
                     }
                 }
             }
             else {
                 print("PDFView is nil.")
             }
         }
     }

     func fetchOnDocumentComment() {
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
                     
                     
                     var traits = getFontSymbolicTraits()
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
                     
                     if let currentPage = pdfView.document?.page(at: pageNumber - 1) {
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


     
     func sendButtonTapped() {
         guard let pdfView = PDFViewWrapper.pdfView,
               let textField = pdfView.subviews.first(where: { $0 is UITextField }) as? UITextField,
               let selectedAnnotation = selectedAnnotation as? PDFAnnotation else {
             return
         }
         
         selectedAnnotation.contents = textField.text ?? ""
         
         var traits = getFontSymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         
         let currentFontSize = selectedAnnotation.font?.pointSize ?? 16
         let resizedFontDescriptor = selectedAnnotation.font?.fontDescriptor.withSymbolicTraits(traits)
         let resizedFont = UIFont(descriptor: resizedFontDescriptor ?? UIFontDescriptor(), size: currentFontSize)
         
         selectedAnnotation.font = resizedFont
         
         textField.resignFirstResponder() // Hide the keyboard
         textField.removeFromSuperview() // Remove the textField from its superview
         
         if let freeTextAnnotation = selectedAnnotation as? CustomPDFAnnotation {
             saveOnDocumentComment(freeTextAnnotation)
             

         }
         isTyping = false
         showDeleteButton = false
         // Trigger a re-draw of the PDF view to reflect the updated annotation appearance
         pdfView.setNeedsDisplay()
     }
     
     func getFontSymbolicTraits() -> UIFontDescriptor.SymbolicTraits {
         var traits = UIFontDescriptor.SymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         return traits
     }
     
     func deleteButtonClicked(annotation: CustomPDFAnnotation) {
         // Remove the annotation from the PDF view
         guard let pdfView = PDFViewWrapper.pdfView,
               let currentPage = pdfView.currentPage else {
             print("Failed to get current page or PDF view.")
             return
         }
         
         currentPage.removeAnnotation(annotation)
         
         // Remove the annotation from Firestore
         guard let annotationID = annotation.annotationID else {
             print("Annotation ID not found.")
             return
         }
         
         let db = Firestore.firestore()
         let annotationsCollection = db.collection("highlightAnnotations")
         
         annotationsCollection.whereField("annotationID", isEqualTo: annotationID)
             .getDocuments { querySnapshot, error in
                 if let error = error {
                     print("Error fetching annotation to delete: \(error.localizedDescription)")
                     return
                 }
                 
                 guard let documents = querySnapshot?.documents else {
                     print("No annotations found to delete.")
                     return
                 }
                 
                 for document in documents {
                     document.reference.delete { error in
                         if let error = error {
                             print("Error deleting annotation from Firestore: \(error.localizedDescription)")
                         } else {
                             print("Annotation deleted from Firestore")
                         }
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
                 
                 // Refresh the PDF view to reflect the changes
                 if let currentPage = pdfView.currentPage {
                     pdfView.go(to: PDFDestination(page: currentPage, at: .zero))
                 }
             }
         }
         
         
         showDeleteButton = false
         //  deselectAnnotation()
     }
     


     
     
     func saveOnDocumentComment(_ annotation: CustomPDFAnnotation) {
         guard let currentUserEmail = Auth.auth().currentUser?.email else {
             print("User is not signed in.")
             return
         }
         
         guard let pdfView = PDFViewWrapper.pdfView,
               let currentPage = pdfView.currentPage,
               let pageIndex = pdfView.document?.index(for: currentPage) else {
             print("Failed to get current page or index.")
             return
         }
         
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
             "pageNumber": pageIndex + 1, // Add the page number (incremented by 1 since pages are 0-indexed)
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
     


     
     
     
     func saveCommentAnnotation(_ annotation: PDFAnnotation) {
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
     
     
     func fetchCommentAnnotations() {
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

 struct PDFViewWrapper: UIViewRepresentable {
     let url: URL
     let handleTapGesture: (CGPoint) -> Void
     static var pdfView: PDFView? // Static reference to access pdfView
     
     func makeUIView(context: Context) -> PDFView {
         let pdfView = PDFView()
         pdfView.autoScales = true
         pdfView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = pdfView // Assign pdfView to static property
         
         let gestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
         pdfView.addGestureRecognizer(gestureRecognizer)
         
         return pdfView
     }
     
     func updateUIView(_ uiView: PDFView, context: Context) {
         uiView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = uiView // Update the static reference
     }
     
     func makeCoordinator() -> Coordinator {
         Coordinator(self)
     }
     
     class Coordinator: NSObject {
         let pdfViewWrapper: PDFViewWrapper
         
         init(_ pdfViewWrapper: PDFViewWrapper) {
             self.pdfViewWrapper = pdfViewWrapper
         }
         
         @objc func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
             let location = gestureRecognizer.location(in: PDFViewWrapper.pdfView)
             pdfViewWrapper.handleTapGesture(location)
         }
     }
     
     // Function to add an annotation to the current PDFPage
     static func addAnnotationToCurrentPage(annotation: PDFAnnotation) {
         if let currentPage = pdfView?.currentPage {
             currentPage.addAnnotation(annotation)
             pdfView?.setNeedsDisplay()
         }
     }
 }




 struct AnnotationToolbar: View {
     @Binding var selectedAnnotationType: PDFAnnotationSubtype?
     @Binding var isAddingComment: Bool
     @Binding var commentText: String?
     @Binding var showCommentDrawer: Bool
     @Binding var isTyping: Bool
     @Binding var fontColor: Color // Use Color instead of UIColor
     @Binding var showDeleteButton: Bool // Track whether to show the delete button
     @Binding var isBold: Bool // Track whether the text is bold
     @Binding var isItalic: Bool // Track whether the text is italic
     @Binding var fontSize: CGFloat // Track the selected font size
     var deleteAction: () -> Void // Action to delete the annotation
     @State private var isDropdownOpen = false
     let availableFontSizes: [CGFloat]
     let colorButtonSize: CGFloat = 24 // Size of the color buttons
     @Environment(\.colorScheme) var colorScheme
     @Binding var isHighlighting: Bool

     
     var body: some View {

         ZStack {
             if !isTyping && !isAddingComment && !showDeleteButton && !isHighlighting{
                 HStack {
                     Button(action: {
                         selectedAnnotationType = nil
                         isAddingComment.toggle()
                     }) {
                         Image(systemName: "rectangle.and.pencil.and.ellipsis")
                     }
                     .foregroundColor(.primary)
                     
                     Button(action: {
                         selectedAnnotationType = .freeText
                         isTyping.toggle()
                     }) {
                         Image(systemName: "pencil.tip")
                     }
                     .foregroundColor(.primary)
                     
                         Button(action: {
                             isHighlighting.toggle()
                         }) {
                             Image(systemName: "highlighter")
                         }
                         .foregroundColor(isHighlighting ? .blue : .black)
                     
                 }
             }
             else if isAddingComment {
                 Button(action: {
                     selectedAnnotationType = nil
                     isAddingComment.toggle()
                 }) {
                     Image(systemName: "rectangle.and.pencil.and.ellipsis")
                 }
                 .foregroundColor(.blue )
             }
             else if isTyping {
                 HStack(spacing: 0) {
                     Button(action: {
                         isBold.toggle()
                     }) {
                         Image(systemName: isBold ? "bold" : "bold")
                     }
                     .foregroundColor(isBold ? .blue : .primary)
                     
                     Button(action: {
                         isItalic.toggle()
                     }) {
                         Image(systemName: isItalic ? "italic" : "italic")
                     }
                     .foregroundColor(isItalic ? .blue : .primary)
                     
                     //ColorButton(color: .black, isSelected: fontColor == .black, action: { fontColor = .black })
                     ColorButton(color: .red, isSelected: fontColor == .red, action: { fontColor = .red })
                     ColorButton(color: .green, isSelected: fontColor == .green, action: { fontColor = .green })
                     ColorButton(color: .blue, isSelected: fontColor == .blue, action: { fontColor = .blue })
                     
                     Menu {
                         ForEach(availableFontSizes, id: \.self) { size in
                             Button(action: {
                                 fontSize = size
                             }) {
                                 Text("\(Int(size))")
                             }
                         }
                     } label: {
                         HStack {
                             Text("Size: \(Int(fontSize))")
                         }
                     }
                     
                     
                     Button(action: {
                         isTyping.toggle()
                     }) {
                         Image(systemName: "pencil.tip")
                             .foregroundColor(isTyping ? .blue : .primary)
                     }
                 }
                 .frame(maxWidth: .infinity)
                 .padding(.horizontal, 8)
             }
             
             else if isHighlighting {
                 Button(action: {
                     isHighlighting.toggle()
                 }) {
                     Image(systemName: "highlighter")
                 }
                 .foregroundColor(isHighlighting ? .blue : .black)

             }
             else if showDeleteButton {
                 Button(action: deleteAction) {
                     Image(systemName: "trash")
                 }
                 .foregroundColor(.red)
             }
             
             
         }

     }
 }

 struct ColorButton: View {
     var color: Color
     var isSelected: Bool
     var action: () -> Void
     
     var body: some View {
         Button(action: action) {
             ZStack {
                 Circle()
                     .fill(color)
                     .frame(width: 5, height: 5)
                 
                 if isSelected {
                     Image(systemName: "checkmark.circle.fill")
                         .foregroundColor(.white)
                 }
             }
         }
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

 class CustomPDFAnnotation: PDFAnnotation {
     var annotationID: String?
 }




 struct DocumentView: View {
     let documentURL: URL
     @State private var showChatDrawer = false
     @State private var showCommentDrawer = false
     @State private var commentMessages: [CommentMessage] = [] // Store comment messages
     @State private var commentText: String?
     @State private var isAddingComment = false // Add isAddingComment state
     @State private var selectedAnnotationType: PDFAnnotationSubtype? // Add selectedAnnotationType state
     @State private var chatMessages: [ChatMessage] = [] // Store chat messages
     @State private var commentAnnotations: [CommentAnnotation] = [] // Store comment annotations
     @State private var selectedAnnotation: PDFAnnotation? // Store the selected annotation
     @State private var selectedOnDocumentAnnotation: CustomPDFAnnotation? // Store the selected annotation
     @State private var isTyping = false // Add isTyping state
     @State private var pdfView: PDFView? // Add pdfView property
     @State private var fontColor: Color = .black // Add a state variable to store the font color
     @State private var showDeleteButton: Bool = false // Track whether to show the delete button
     @State private var isBold: Bool = false // Track whether the text is bold
     @State private var isItalic: Bool = false // Track whether the text is italic
     @State private var fontSize: CGFloat = 16 // Track the selected font size
     let availableFontSizes: [CGFloat] = [8, 10, 12, 14, 16,18, 20, 22, 24, 26, 28, 30, 32]
     @Environment(\.colorScheme) var colorScheme
     
     @State private var firstTouchLocation: CGPoint?
     @State private var secondTouchLocation: CGPoint?
     @State private var isHighlighting: Bool = false
     @State private var highlightAnnotations: [PDFAnnotation] = []

     
     
     var body: some View {
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
                             .frame(width: 32, height: 32)
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
         
         .toolbar {
             ToolbarItem(placement: .navigationBarTrailing) {
                 AnnotationToolbar(selectedAnnotationType: $selectedAnnotationType, isAddingComment: $isAddingComment, commentText: $commentText, showCommentDrawer: $showCommentDrawer, isTyping: $isTyping, fontColor: $fontColor, showDeleteButton: $showDeleteButton, isBold: $isBold, isItalic: $isItalic, fontSize: $fontSize, deleteAction: deleteAnnotation, availableFontSizes: availableFontSizes, isHighlighting: $isHighlighting)
             }
             ToolbarItem(placement: .navigationBarTrailing) {
                 Spacer()
             }
             
         }
         .sheet(isPresented: $showCommentDrawer) {
             CommentDrawerView(commentMessages: $commentMessages, documentURL: documentURL, commentText: $commentText, isAddingComment: $isAddingComment, selectedAnnotation: $selectedAnnotation, saveCommentAnnotation: saveCommentAnnotation)
         }
         .sheet(isPresented: $showChatDrawer) {
             ChatDrawerView(chatMessages: $chatMessages, documentURL: documentURL, commentText: $commentText)
         }
         .onAppear {
             fetchOnDocumentComment()
             fetchCommentAnnotations()
             fetchHighlightAnnotations()
         }
     }
     
     func handleTapGesture(location: CGPoint) {
         if let pdfView = PDFViewWrapper.pdfView,
            let currentPage = pdfView.currentPage {
             let tapLocation = pdfView.convert(location, to: currentPage)
             
             if let tappedAnnotation = currentPage.annotation(at: tapLocation) {
                 // User tapped on an existing annotation
                 
                 if let customAnnotation = tappedAnnotation as? CustomPDFAnnotation {
                     selectedOnDocumentAnnotation = customAnnotation
                     let annotationWidth = customAnnotation.bounds.size.width
                     
                     if annotationWidth == 200 {
                         showDeleteButton = true
                         isTyping = false
                     }
                 }
                 else if let pdfAnnotation = tappedAnnotation as? PDFAnnotation{
                     
                     selectedAnnotation = pdfAnnotation
                     let annotationWidth = pdfAnnotation.bounds.size.width
                     if annotationWidth == 30 {
                         // Handle other types of annotations if necessary
                         showCommentDrawer = true
                     }
                     else {
                         showDeleteButton = true
                     }
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
                     createHighlightAnnotation()
                 }
             }
             if isAddingComment {
                 
                 let tapLocation = pdfView.convert(location, to: currentPage)
                 // Create a text annotation at the tapped location
                 let textAnnotation = PDFAnnotation(bounds: CGRect(x: tapLocation.x, y: tapLocation.y, width: 30, height: 30), forType: .freeText, withProperties: nil)
                 textAnnotation.contents = "\(commentMessages.count + 1)" // Calculate the comment count and set it as the annotation content
                 textAnnotation.font = UIFont.boldSystemFont(ofSize: 20) // Adjust the font size if needed
                 textAnnotation.color = .yellow.withAlphaComponent(0.2)
                 textAnnotation.fontColor = .red
                 textAnnotation.alignment = .center
                 // Store the selected annotation
                 
                 
                 selectedAnnotation = textAnnotation
                 
                 // Open the CommentDrawerView
                 showCommentDrawer = true
             }
             
             else if isTyping {
                 // User tapped to create a new annotation
                 let bounds = CGRect(x: tapLocation.x , y: tapLocation.y - 85, width: 200, height: 100)
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
                 freeTextAnnotation.color = .black.withAlphaComponent(0)
                 
                 // Add the annotation to the current page
                 currentPage.addAnnotation(freeTextAnnotation)
                 
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
                 
                 currentPage.addAnnotation(freeTextAnnotation)
                 pdfView.addSubview(annotationLabel)
                 pdfView.addSubview(textField)
                 
                 // Set the selectedAnnotation to the created free text annotation
                 selectedAnnotation = freeTextAnnotation
                 pdfView.becomeFirstResponder()
             }
         }
         
         
         
     }
     
     func createHighlightAnnotation() {
         guard let firstTouchLocation = firstTouchLocation,
               let secondTouchLocation = secondTouchLocation,
               let pdfView = PDFViewWrapper.pdfView,
               let tappedPage = pdfView.page(for: firstTouchLocation, nearest: true) else {
             return
         }
         
         let convertedFirstLocation = pdfView.convert(firstTouchLocation, to: tappedPage)
         let convertedSecondLocation = pdfView.convert(secondTouchLocation, to: tappedPage)
         
         let width: CGFloat
         var height = abs(convertedSecondLocation.y - convertedFirstLocation.y)
         
         if height < 20 {
             width = abs(convertedSecondLocation.x - convertedFirstLocation.x)
             height = 10
         } else {
             width = tappedPage.bounds(for: .cropBox).width
         }
         
         let minY = min(convertedFirstLocation.y, convertedSecondLocation.y)
         let highlightBounds = CGRect(x: convertedFirstLocation.x, y: minY, width: width, height: height)
         
         let highlightAnnotation = PDFAnnotation(bounds: highlightBounds, forType: .highlight, withProperties: nil)
         tappedPage.addAnnotation(highlightAnnotation)
         
         // Reset touch locations for future highlights
         self.firstTouchLocation = nil
         self.secondTouchLocation = nil
         
         isHighlighting = false
         
         // Save the highlight annotation to Firestore
         saveHighlightAnnotation(annotation: highlightAnnotation)
     }

     func saveHighlightAnnotation(annotation: PDFAnnotation) {
         guard let pdfView = PDFViewWrapper.pdfView,
               let currentPage = pdfView.currentPage,
               let pageIndex = pdfView.document?.index(for: currentPage) else {
             print("Failed to get current page or index.")
             return
         }
         
         let db = Firestore.firestore()
         let annotationsCollection = db.collection("highlightAnnotations")
         
         let bounds = annotation.bounds
         let boundsData: [String: Any] = [
             "x": bounds.origin.x,
             "y": bounds.origin.y,
             "width": bounds.size.width,
             "height": bounds.size.height
         ]
         
         let annotationData: [String: Any] = [
             "documentURL": documentURL.absoluteString,
             "pageIndex": pageIndex,
             "bounds": boundsData
         ]
         
         annotationsCollection.addDocument(data: annotationData) { error in
             if let error = error {
                 // Handle the error appropriately
                 print("Error saving highlight annotation to Firestore: \(error)")
             } else {
                 // Saving successful
                 print("Highlight annotation saved to Firestore")
             }
         }
     }

     func fetchHighlightAnnotations() {
         let annotationsCollection = Firestore.firestore().collection("highlightAnnotations")
         
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
                     
                     // Retrieve the annotation data from Firestore
                     guard let bounds = data["bounds"] as? [String: CGFloat],
                           let x = bounds["x"],
                           let y = bounds["y"],
                           let width = bounds["width"],
                           let height = bounds["height"],
                           let documentURLString = data["documentURL"] as? String,
                           let pageIndex = data["pageIndex"] as? Int else {
                         print("Error parsing annotation data.")
                         continue
                     }
                     
                     let documentURL = URL(string: documentURLString)
                     
                     // Create the annotation object and set its properties
                     let annotationBounds = CGRect(x: x, y: y, width: width, height: height)
                     let annotation = PDFAnnotation(bounds: annotationBounds, forType: .highlight, withProperties: nil)
                     
                     
                     if let currentPage = pdfView.document?.page(at: pageIndex ) {
                         currentPage.addAnnotation(annotation)
                     } else {
                         print("Invalid page number: \(pageIndex)")
                     }
                 }
             }
             else {
                 print("PDFView is nil.")
             }
         }
     }

     func fetchOnDocumentComment() {
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
                     
                     
                     var traits = getFontSymbolicTraits()
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
                     
                     if let currentPage = pdfView.document?.page(at: pageNumber - 1) {
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


     
     func sendButtonTapped() {
         guard let pdfView = PDFViewWrapper.pdfView,
               let textField = pdfView.subviews.first(where: { $0 is UITextField }) as? UITextField,
               let selectedAnnotation = selectedAnnotation as? PDFAnnotation else {
             return
         }
         
         selectedAnnotation.contents = textField.text ?? ""
         
         var traits = getFontSymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         
         let currentFontSize = selectedAnnotation.font?.pointSize ?? 16
         let resizedFontDescriptor = selectedAnnotation.font?.fontDescriptor.withSymbolicTraits(traits)
         let resizedFont = UIFont(descriptor: resizedFontDescriptor ?? UIFontDescriptor(), size: currentFontSize)
         
         selectedAnnotation.font = resizedFont
         
         textField.resignFirstResponder() // Hide the keyboard
         textField.removeFromSuperview() // Remove the textField from its superview
         
         if let freeTextAnnotation = selectedAnnotation as? CustomPDFAnnotation {
             saveOnDocumentComment(freeTextAnnotation)
             

         }
         isTyping = false
         showDeleteButton = false
         // Trigger a re-draw of the PDF view to reflect the updated annotation appearance
         pdfView.setNeedsDisplay()
     }
     
     func getFontSymbolicTraits() -> UIFontDescriptor.SymbolicTraits {
         var traits = UIFontDescriptor.SymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         return traits
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
                 
                 // Refresh the PDF view to reflect the changes
                 if let currentPage = pdfView.currentPage {
                     pdfView.go(to: PDFDestination(page: currentPage, at: .zero))
                 }
             }
         }
         
         
         showDeleteButton = false
         //  deselectAnnotation()
     }
     


     
     
     func saveOnDocumentComment(_ annotation: CustomPDFAnnotation) {
         guard let currentUserEmail = Auth.auth().currentUser?.email else {
             print("User is not signed in.")
             return
         }
         
         guard let pdfView = PDFViewWrapper.pdfView,
               let currentPage = pdfView.currentPage,
               let pageIndex = pdfView.document?.index(for: currentPage) else {
             print("Failed to get current page or index.")
             return
         }
         
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
             "pageNumber": pageIndex + 1, // Add the page number (incremented by 1 since pages are 0-indexed)
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
     


     
     
     
     func saveCommentAnnotation(_ annotation: PDFAnnotation) {
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
     
     
     func fetchCommentAnnotations() {
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

 struct PDFViewWrapper: UIViewRepresentable {
     let url: URL
     let handleTapGesture: (CGPoint) -> Void
     static var pdfView: PDFView? // Static reference to access pdfView
     
     func makeUIView(context: Context) -> PDFView {
         let pdfView = PDFView()
         pdfView.autoScales = true
         pdfView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = pdfView // Assign pdfView to static property
         
         let gestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
         pdfView.addGestureRecognizer(gestureRecognizer)
         
         return pdfView
     }
     
     func updateUIView(_ uiView: PDFView, context: Context) {
         uiView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = uiView // Update the static reference
     }
     
     func makeCoordinator() -> Coordinator {
         Coordinator(self)
     }
     
     class Coordinator: NSObject {
         let pdfViewWrapper: PDFViewWrapper
         
         init(_ pdfViewWrapper: PDFViewWrapper) {
             self.pdfViewWrapper = pdfViewWrapper
         }
         
         @objc func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
             let location = gestureRecognizer.location(in: PDFViewWrapper.pdfView)
             pdfViewWrapper.handleTapGesture(location)
         }
     }
     
     // Function to add an annotation to the current PDFPage
     static func addAnnotationToCurrentPage(annotation: PDFAnnotation) {
         if let currentPage = pdfView?.currentPage {
             currentPage.addAnnotation(annotation)
             pdfView?.setNeedsDisplay()
         }
     }
 }




 struct AnnotationToolbar: View {
     @Binding var selectedAnnotationType: PDFAnnotationSubtype?
     @Binding var isAddingComment: Bool
     @Binding var commentText: String?
     @Binding var showCommentDrawer: Bool
     @Binding var isTyping: Bool
     @Binding var fontColor: Color // Use Color instead of UIColor
     @Binding var showDeleteButton: Bool // Track whether to show the delete button
     @Binding var isBold: Bool // Track whether the text is bold
     @Binding var isItalic: Bool // Track whether the text is italic
     @Binding var fontSize: CGFloat // Track the selected font size
     var deleteAction: () -> Void // Action to delete the annotation
     @State private var isDropdownOpen = false
     let availableFontSizes: [CGFloat]
     let colorButtonSize: CGFloat = 24 // Size of the color buttons
     @Environment(\.colorScheme) var colorScheme
     @Binding var isHighlighting: Bool

     
     var body: some View {

         ZStack {
             if !isTyping && !isAddingComment && !showDeleteButton && !isHighlighting{
                 HStack {
                     Button(action: {
                         selectedAnnotationType = nil
                         isAddingComment.toggle()
                     }) {
                         Image(systemName: "rectangle.and.pencil.and.ellipsis")
                     }
                     .foregroundColor(.primary)
                     
                     Button(action: {
                         selectedAnnotationType = .freeText
                         isTyping.toggle()
                     }) {
                         Image(systemName: "pencil.tip")
                     }
                     .foregroundColor(.primary)
                     
                         Button(action: {
                             isHighlighting.toggle()
                         }) {
                             Image(systemName: "highlighter")
                         }
                         .foregroundColor(isHighlighting ? .blue : .black)
                     
                 }
             }
             else if isAddingComment {
                 Button(action: {
                     selectedAnnotationType = nil
                     isAddingComment.toggle()
                 }) {
                     Image(systemName: "rectangle.and.pencil.and.ellipsis")
                 }
                 .foregroundColor(.blue )
             }
             else if isTyping {
                 HStack(spacing: 0) {
                     Button(action: {
                         isBold.toggle()
                     }) {
                         Image(systemName: isBold ? "bold" : "bold")
                     }
                     .foregroundColor(isBold ? .blue : .primary)
                     
                     Button(action: {
                         isItalic.toggle()
                     }) {
                         Image(systemName: isItalic ? "italic" : "italic")
                     }
                     .foregroundColor(isItalic ? .blue : .primary)
                     
                     //ColorButton(color: .black, isSelected: fontColor == .black, action: { fontColor = .black })
                     ColorButton(color: .red, isSelected: fontColor == .red, action: { fontColor = .red })
                     ColorButton(color: .green, isSelected: fontColor == .green, action: { fontColor = .green })
                     ColorButton(color: .blue, isSelected: fontColor == .blue, action: { fontColor = .blue })
                     
                     Menu {
                         ForEach(availableFontSizes, id: \.self) { size in
                             Button(action: {
                                 fontSize = size
                             }) {
                                 Text("\(Int(size))")
                             }
                         }
                     } label: {
                         HStack {
                             Text("Size: \(Int(fontSize))")
                         }
                     }
                     
                     
                     Button(action: {
                         isTyping.toggle()
                     }) {
                         Image(systemName: "pencil.tip")
                             .foregroundColor(isTyping ? .blue : .primary)
                     }
                 }
                 .frame(maxWidth: .infinity)
                 .padding(.horizontal, 8)
             }
             
             else if isHighlighting {
                 Button(action: {
                     isHighlighting.toggle()
                 }) {
                     Image(systemName: "highlighter")
                 }
                 .foregroundColor(isHighlighting ? .blue : .black)

             }
             else if showDeleteButton {
                 Button(action: deleteAction) {
                     Image(systemName: "trash")
                 }
                 .foregroundColor(.red)
             }
             
             
         }

     }
 }

 struct ColorButton: View {
     var color: Color
     var isSelected: Bool
     var action: () -> Void
     
     var body: some View {
         Button(action: action) {
             ZStack {
                 Circle()
                     .fill(color)
                     .frame(width: 5, height: 5)
                 
                 if isSelected {
                     Image(systemName: "checkmark.circle.fill")
                         .foregroundColor(.white)
                 }
             }
         }
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

 class CustomPDFAnnotation: PDFAnnotation {
     var annotationID: String?
 }




 struct DocumentView: View {
     let documentURL: URL
     @State private var showChatDrawer = false
     @State private var showCommentDrawer = false
     @State private var commentMessages: [CommentMessage] = [] // Store comment messages
     @State private var commentText: String?
     @State private var isAddingComment = false // Add isAddingComment state
     @State private var selectedAnnotationType: PDFAnnotationSubtype? // Add selectedAnnotationType state
     @State private var chatMessages: [ChatMessage] = [] // Store chat messages
     @State private var commentAnnotations: [CommentAnnotation] = [] // Store comment annotations
     @State private var selectedAnnotation: PDFAnnotation? // Store the selected annotation
     @State private var selectedOnDocumentAnnotation: CustomPDFAnnotation? // Store the selected annotation
     @State private var isTyping = false // Add isTyping state
     @State private var pdfView: PDFView? // Add pdfView property
     @State private var fontColor: Color = .black // Add a state variable to store the font color
     @State private var showDeleteButton: Bool = false // Track whether to show the delete button
     @State private var isBold: Bool = false // Track whether the text is bold
     @State private var isItalic: Bool = false // Track whether the text is italic
     @State private var fontSize: CGFloat = 16 // Track the selected font size
     let availableFontSizes: [CGFloat] = [8, 10, 12, 14, 16,18, 20, 22, 24, 26, 28, 30, 32]
     @Environment(\.colorScheme) var colorScheme
     
     @State private var firstTouchLocation: CGPoint?
     @State private var secondTouchLocation: CGPoint?
     @State private var isHighlighting: Bool = false

     
     
     var body: some View {
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
                             .frame(width: 32, height: 32)
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
         
         .toolbar {
             ToolbarItem(placement: .navigationBarTrailing) {
                 AnnotationToolbar(selectedAnnotationType: $selectedAnnotationType, isAddingComment: $isAddingComment, commentText: $commentText, showCommentDrawer: $showCommentDrawer, isTyping: $isTyping, fontColor: $fontColor, showDeleteButton: $showDeleteButton, isBold: $isBold, isItalic: $isItalic, fontSize: $fontSize, deleteAction: deleteAnnotation, availableFontSizes: availableFontSizes, isHighlighting: $isHighlighting)
             }
             ToolbarItem(placement: .navigationBarTrailing) {
                 Spacer()
             }
             
         }
         .sheet(isPresented: $showCommentDrawer) {
             CommentDrawerView(commentMessages: $commentMessages, documentURL: documentURL, commentText: $commentText, isAddingComment: $isAddingComment, selectedAnnotation: $selectedAnnotation, saveCommentAnnotation: saveCommentAnnotation)
         }
         .sheet(isPresented: $showChatDrawer) {
             ChatDrawerView(chatMessages: $chatMessages, documentURL: documentURL, commentText: $commentText)
         }
         .onAppear {
             fetchOnDocumentComment()
             fetchCommentAnnotations()
         }
     }
     
     func handleTapGesture(location: CGPoint) {
         if let pdfView = PDFViewWrapper.pdfView,
            let currentPage = pdfView.currentPage {
             let tapLocation = pdfView.convert(location, to: currentPage)
             
             if let tappedAnnotation = currentPage.annotation(at: tapLocation) {
                 // User tapped on an existing annotation
                 
                 if let customAnnotation = tappedAnnotation as? CustomPDFAnnotation {
                     selectedOnDocumentAnnotation = customAnnotation
                     let annotationWidth = customAnnotation.bounds.size.width
                     
                     if annotationWidth == 200 {
                         showDeleteButton = true
                         isTyping = false
                     }
                 } else {
                     // Handle other types of annotations if necessary
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
                     createHighlightAnnotation()
                 }
             }
             if isAddingComment {
                 
                 let tapLocation = pdfView.convert(location, to: currentPage)
                 // Create a text annotation at the tapped location
                 let textAnnotation = PDFAnnotation(bounds: CGRect(x: tapLocation.x, y: tapLocation.y, width: 30, height: 30), forType: .freeText, withProperties: nil)
                 textAnnotation.contents = "\(commentMessages.count + 1)" // Calculate the comment count and set it as the annotation content
                 textAnnotation.font = UIFont.boldSystemFont(ofSize: 20) // Adjust the font size if needed
                 textAnnotation.color = .yellow.withAlphaComponent(0.2)
                 textAnnotation.fontColor = .red
                 textAnnotation.alignment = .center
                 // Store the selected annotation
                 
                 
                 selectedAnnotation = textAnnotation
                 
                 // Open the CommentDrawerView
                 showCommentDrawer = true
             }
             
             else if isTyping {
                 // User tapped to create a new annotation
                 let bounds = CGRect(x: tapLocation.x , y: tapLocation.y - 85, width: 200, height: 100)
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
                 freeTextAnnotation.color = .black.withAlphaComponent(0)
                 
                 // Add the annotation to the current page
                 currentPage.addAnnotation(freeTextAnnotation)
                 
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
                 
                 currentPage.addAnnotation(freeTextAnnotation)
                 pdfView.addSubview(annotationLabel)
                 pdfView.addSubview(textField)
                 
                 // Set the selectedAnnotation to the created free text annotation
                 selectedAnnotation = freeTextAnnotation
                 pdfView.becomeFirstResponder()
             }
         }
         
         
         
     }
     
     func createHighlightAnnotation() {
         guard let firstTouchLocation = firstTouchLocation,
               let secondTouchLocation = secondTouchLocation,
               let pdfView = PDFViewWrapper.pdfView,
               let tappedPage = pdfView.page(for: firstTouchLocation, nearest: true) else {
             return
         }
         
         let convertedFirstLocation = pdfView.convert(firstTouchLocation, to: tappedPage)
         let convertedSecondLocation = pdfView.convert(secondTouchLocation, to: tappedPage)
         
         let width: CGFloat
         var height = abs(convertedSecondLocation.y - convertedFirstLocation.y)
         
         if height < 20 {
             width = abs(convertedSecondLocation.x - convertedFirstLocation.x)
             height = 10
         } else {
             width = tappedPage.bounds(for: .cropBox).width
         }
         
         let minY = min(convertedFirstLocation.y, convertedSecondLocation.y)
         let highlightBounds = CGRect(x: convertedFirstLocation.x, y: minY, width: width, height: height)
         
         let highlightAnnotation = PDFAnnotation(bounds: highlightBounds, forType: .highlight, withProperties: nil)
         tappedPage.addAnnotation(highlightAnnotation)
         
         // Reset touch locations for future highlights
         self.firstTouchLocation = nil
         self.secondTouchLocation = nil
     }

     
     func sendButtonTapped() {
         guard let pdfView = PDFViewWrapper.pdfView,
               let textField = pdfView.subviews.first(where: { $0 is UITextField }) as? UITextField,
               let selectedAnnotation = selectedAnnotation as? PDFAnnotation else {
             return
         }
         
         selectedAnnotation.contents = textField.text ?? ""
         
         var traits = getFontSymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         
         let currentFontSize = selectedAnnotation.font?.pointSize ?? 16
         let resizedFontDescriptor = selectedAnnotation.font?.fontDescriptor.withSymbolicTraits(traits)
         let resizedFont = UIFont(descriptor: resizedFontDescriptor ?? UIFontDescriptor(), size: currentFontSize)
         
         selectedAnnotation.font = resizedFont
         
         textField.resignFirstResponder() // Hide the keyboard
         textField.removeFromSuperview() // Remove the textField from its superview
         
         if let freeTextAnnotation = selectedAnnotation as? CustomPDFAnnotation {
             saveOnDocumentComment(freeTextAnnotation)
             

         }
         isTyping = false
         showDeleteButton = false
         // Trigger a re-draw of the PDF view to reflect the updated annotation appearance
         pdfView.setNeedsDisplay()
     }
     
     func getFontSymbolicTraits() -> UIFontDescriptor.SymbolicTraits {
         var traits = UIFontDescriptor.SymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         return traits
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
                 
                 // Refresh the PDF view to reflect the changes
                 if let currentPage = pdfView.currentPage {
                     pdfView.go(to: PDFDestination(page: currentPage, at: .zero))
                 }
             }
         }
         
         
         showDeleteButton = false
         //  deselectAnnotation()
     }
     
     func fetchOnDocumentComment() {
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
                     
                     
                     var traits = getFontSymbolicTraits()
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
                     
                     if let currentPage = pdfView.document?.page(at: pageNumber - 1) {
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


     
     
     func saveOnDocumentComment(_ annotation: CustomPDFAnnotation) {
         guard let currentUserEmail = Auth.auth().currentUser?.email else {
             print("User is not signed in.")
             return
         }
         
         guard let pdfView = PDFViewWrapper.pdfView,
               let currentPage = pdfView.currentPage,
               let pageIndex = pdfView.document?.index(for: currentPage) else {
             print("Failed to get current page or index.")
             return
         }
         
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
             "pageNumber": pageIndex + 1, // Add the page number (incremented by 1 since pages are 0-indexed)
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
     


     
     
     
     func saveCommentAnnotation(_ annotation: PDFAnnotation) {
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
     
     
     func fetchCommentAnnotations() {
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

 struct PDFViewWrapper: UIViewRepresentable {
     let url: URL
     let handleTapGesture: (CGPoint) -> Void
     static var pdfView: PDFView? // Static reference to access pdfView
     
     func makeUIView(context: Context) -> PDFView {
         let pdfView = PDFView()
         pdfView.autoScales = true
         pdfView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = pdfView // Assign pdfView to static property
         
         let gestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
         pdfView.addGestureRecognizer(gestureRecognizer)
         
         return pdfView
     }
     
     func updateUIView(_ uiView: PDFView, context: Context) {
         uiView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = uiView // Update the static reference
     }
     
     func makeCoordinator() -> Coordinator {
         Coordinator(self)
     }
     
     class Coordinator: NSObject {
         let pdfViewWrapper: PDFViewWrapper
         
         init(_ pdfViewWrapper: PDFViewWrapper) {
             self.pdfViewWrapper = pdfViewWrapper
         }
         
         @objc func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
             let location = gestureRecognizer.location(in: PDFViewWrapper.pdfView)
             pdfViewWrapper.handleTapGesture(location)
         }
     }
     
     // Function to add an annotation to the current PDFPage
     static func addAnnotationToCurrentPage(annotation: PDFAnnotation) {
         if let currentPage = pdfView?.currentPage {
             currentPage.addAnnotation(annotation)
             pdfView?.setNeedsDisplay()
         }
     }
 }




 struct AnnotationToolbar: View {
     @Binding var selectedAnnotationType: PDFAnnotationSubtype?
     @Binding var isAddingComment: Bool
     @Binding var commentText: String?
     @Binding var showCommentDrawer: Bool
     @Binding var isTyping: Bool
     @Binding var fontColor: Color // Use Color instead of UIColor
     @Binding var showDeleteButton: Bool // Track whether to show the delete button
     @Binding var isBold: Bool // Track whether the text is bold
     @Binding var isItalic: Bool // Track whether the text is italic
     @Binding var fontSize: CGFloat // Track the selected font size
     var deleteAction: () -> Void // Action to delete the annotation
     @State private var isDropdownOpen = false
     let availableFontSizes: [CGFloat]
     let colorButtonSize: CGFloat = 24 // Size of the color buttons
     @Environment(\.colorScheme) var colorScheme
     @Binding var isHighlighting: Bool

     
     var body: some View {

         ZStack {
             if !isTyping && !isAddingComment && !showDeleteButton && !isHighlighting{
                 HStack {
                     Button(action: {
                         selectedAnnotationType = nil
                         isAddingComment.toggle()
                     }) {
                         Image(systemName: "rectangle.and.pencil.and.ellipsis")
                     }
                     .foregroundColor(.primary)
                     
                     Button(action: {
                         selectedAnnotationType = .freeText
                         isTyping.toggle()
                     }) {
                         Image(systemName: "pencil.tip")
                     }
                     .foregroundColor(.primary)
                     
                         Button(action: {
                             isHighlighting.toggle()
                         }) {
                             Image(systemName: "highlighter")
                         }
                         .foregroundColor(isHighlighting ? .blue : .black)
                     
                 }
             }
             else if isAddingComment {
                 Button(action: {
                     selectedAnnotationType = nil
                     isAddingComment.toggle()
                 }) {
                     Image(systemName: "rectangle.and.pencil.and.ellipsis")
                 }
                 .foregroundColor(.blue )
             }
             else if isTyping {
                 HStack(spacing: 0) {
                     Button(action: {
                         isBold.toggle()
                     }) {
                         Image(systemName: isBold ? "bold" : "bold")
                     }
                     .foregroundColor(isBold ? .blue : .primary)
                     
                     Button(action: {
                         isItalic.toggle()
                     }) {
                         Image(systemName: isItalic ? "italic" : "italic")
                     }
                     .foregroundColor(isItalic ? .blue : .primary)
                     
                     //ColorButton(color: .black, isSelected: fontColor == .black, action: { fontColor = .black })
                     ColorButton(color: .red, isSelected: fontColor == .red, action: { fontColor = .red })
                     ColorButton(color: .green, isSelected: fontColor == .green, action: { fontColor = .green })
                     ColorButton(color: .blue, isSelected: fontColor == .blue, action: { fontColor = .blue })
                     
                     Menu {
                         ForEach(availableFontSizes, id: \.self) { size in
                             Button(action: {
                                 fontSize = size
                             }) {
                                 Text("\(Int(size))")
                             }
                         }
                     } label: {
                         HStack {
                             Text("Size: \(Int(fontSize))")
                         }
                     }
                     
                     
                     Button(action: {
                         isTyping.toggle()
                     }) {
                         Image(systemName: "pencil.tip")
                             .foregroundColor(isTyping ? .blue : .primary)
                     }
                 }
                 .frame(maxWidth: .infinity)
                 .padding(.horizontal, 8)
             }
             
             else if isHighlighting {
                 Button(action: {
                     isHighlighting.toggle()
                 }) {
                     Image(systemName: "highlighter")
                 }
                 .foregroundColor(isHighlighting ? .blue : .black)

             }
             else if showDeleteButton {
                 Button(action: deleteAction) {
                     Image(systemName: "trash")
                 }
                 .foregroundColor(.red)
             }
             
             
         }

     }
 }

 struct ColorButton: View {
     var color: Color
     var isSelected: Bool
     var action: () -> Void
     
     var body: some View {
         Button(action: action) {
             ZStack {
                 Circle()
                     .fill(color)
                     .frame(width: 5, height: 5)
                 
                 if isSelected {
                     Image(systemName: "checkmark.circle.fill")
                         .foregroundColor(.white)
                 }
             }
         }
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

 class CustomPDFAnnotation: PDFAnnotation {
     var annotationID: String?
 }




 struct DocumentView: View {
     let documentURL: URL
     @State private var showChatDrawer = false
     @State private var showCommentDrawer = false
     @State private var commentMessages: [CommentMessage] = [] // Store comment messages
     @State private var commentText: String?
     @State private var isAddingComment = false // Add isAddingComment state
     @State private var selectedAnnotationType: PDFAnnotationSubtype? // Add selectedAnnotationType state
     @State private var chatMessages: [ChatMessage] = [] // Store chat messages
     @State private var commentAnnotations: [CommentAnnotation] = [] // Store comment annotations
     @State private var selectedAnnotation: PDFAnnotation? // Store the selected annotation
     @State private var selectedOnDocumentAnnotation: CustomPDFAnnotation? // Store the selected annotation
     
     @State private var isTyping = false // Add isTyping state
     @State private var pdfView: PDFView? // Add pdfView property
     @State private var fontColor: Color = .black // Add a state variable to store the font color
     @State private var showDeleteButton: Bool = false // Track whether to show the delete button
     @State private var isBold: Bool = false // Track whether the text is bold
     @State private var isItalic: Bool = false // Track whether the text is italic
     @State private var fontSize: CGFloat = 16 // Track the selected font size
     let availableFontSizes: [CGFloat] = [8, 10, 12, 14, 16,18, 20, 22, 24, 26, 28, 30, 32]
     @Environment(\.colorScheme) var colorScheme
     
     
     var body: some View {
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
                             .frame(width: 32, height: 32)
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
         
         .toolbar {
             ToolbarItem(placement: .navigationBarTrailing) {
                 AnnotationToolbar(selectedAnnotationType: $selectedAnnotationType, isAddingComment: $isAddingComment, commentText: $commentText, showCommentDrawer: $showCommentDrawer, isTyping: $isTyping, fontColor: $fontColor, showDeleteButton: $showDeleteButton, isBold: $isBold, isItalic: $isItalic, fontSize: $fontSize, deleteAction: deleteAnnotation, availableFontSizes: availableFontSizes)
             }
             ToolbarItem(placement: .navigationBarTrailing) {
                 Spacer()
             }
             
         }
         .sheet(isPresented: $showCommentDrawer) {
             CommentDrawerView(commentMessages: $commentMessages, documentURL: documentURL, commentText: $commentText, isAddingComment: $isAddingComment, selectedAnnotation: $selectedAnnotation, saveCommentAnnotation: saveCommentAnnotation)
         }
         .sheet(isPresented: $showChatDrawer) {
             ChatDrawerView(chatMessages: $chatMessages, documentURL: documentURL, commentText: $commentText)
         }
         .onAppear {
             fetchOnDocumentComment()
             fetchCommentAnnotations()
         }
     }
     
     func handleTapGesture(location: CGPoint) {
         if let pdfView = PDFViewWrapper.pdfView,
            let currentPage = pdfView.currentPage {
             let tapLocation = pdfView.convert(location, to: currentPage)
             
             if let tappedAnnotation = currentPage.annotation(at: tapLocation) {
                 // User tapped on an existing annotation
                 
                 if let customAnnotation = tappedAnnotation as? CustomPDFAnnotation {
                     selectedOnDocumentAnnotation = customAnnotation
                     let annotationWidth = customAnnotation.bounds.size.width
                     
                     if annotationWidth == 200 {
                         showDeleteButton = true
                         isTyping = false
                     }
                 } else {
                     // Handle other types of annotations if necessary
                     showCommentDrawer = true
                 }
             }
             
             
             else {
                 showDeleteButton = false
                 
             }
             if isAddingComment {
                 
                 let tapLocation = pdfView.convert(location, to: currentPage)
                 // Create a text annotation at the tapped location
                 let textAnnotation = PDFAnnotation(bounds: CGRect(x: tapLocation.x, y: tapLocation.y, width: 30, height: 30), forType: .freeText, withProperties: nil)
                 textAnnotation.contents = "\(commentMessages.count + 1)" // Calculate the comment count and set it as the annotation content
                 textAnnotation.font = UIFont.boldSystemFont(ofSize: 20) // Adjust the font size if needed
                 textAnnotation.color = .yellow.withAlphaComponent(0.2)
                 textAnnotation.fontColor = .red
                 textAnnotation.alignment = .center
                 // Store the selected annotation
                 
                 
                 selectedAnnotation = textAnnotation
                 
                 // Open the CommentDrawerView
                 showCommentDrawer = true
             }
             
             else if isTyping {
                 // User tapped to create a new annotation
                 let bounds = CGRect(x: tapLocation.x , y: tapLocation.y - 85, width: 200, height: 100)
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
                 freeTextAnnotation.color = .black.withAlphaComponent(0)
                 
                 // Add the annotation to the current page
                 currentPage.addAnnotation(freeTextAnnotation)
                 
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
                 
                 currentPage.addAnnotation(freeTextAnnotation)
                 pdfView.addSubview(annotationLabel)
                 pdfView.addSubview(textField)
                 
                 // Set the selectedAnnotation to the created free text annotation
                 selectedAnnotation = freeTextAnnotation
                 pdfView.becomeFirstResponder()
             }
         }
         
         
         
     }
     
     func sendButtonTapped() {
         guard let pdfView = PDFViewWrapper.pdfView,
               let textField = pdfView.subviews.first(where: { $0 is UITextField }) as? UITextField,
               let selectedAnnotation = selectedAnnotation as? PDFAnnotation else {
             return
         }
         
         selectedAnnotation.contents = textField.text ?? ""
         
         var traits = getFontSymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         
         let currentFontSize = selectedAnnotation.font?.pointSize ?? 16
         let resizedFontDescriptor = selectedAnnotation.font?.fontDescriptor.withSymbolicTraits(traits)
         let resizedFont = UIFont(descriptor: resizedFontDescriptor ?? UIFontDescriptor(), size: currentFontSize)
         
         selectedAnnotation.font = resizedFont
         
         textField.resignFirstResponder() // Hide the keyboard
         textField.removeFromSuperview() // Remove the textField from its superview
         
         if let freeTextAnnotation = selectedAnnotation as? CustomPDFAnnotation {
             saveOnDocumentComment(freeTextAnnotation)
             

         }
         isTyping = false
         showDeleteButton = false
         // Trigger a re-draw of the PDF view to reflect the updated annotation appearance
         pdfView.setNeedsDisplay()
     }
     
     func getFontSymbolicTraits() -> UIFontDescriptor.SymbolicTraits {
         var traits = UIFontDescriptor.SymbolicTraits()
         if isBold {
             traits.insert(.traitBold)
         }
         if isItalic {
             traits.insert(.traitItalic)
         }
         return traits
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
                 
                 // Refresh the PDF view to reflect the changes
                 if let currentPage = pdfView.currentPage {
                     pdfView.go(to: PDFDestination(page: currentPage, at: .zero))
                 }
             }
         }
         
         
         showDeleteButton = false
         //  deselectAnnotation()
     }
     
     func fetchOnDocumentComment() {
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
                     
                     
                     var traits = getFontSymbolicTraits()
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
                     
                     if let currentPage = pdfView.document?.page(at: pageNumber - 1) {
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


     
     
     func saveOnDocumentComment(_ annotation: CustomPDFAnnotation) {
         guard let currentUserEmail = Auth.auth().currentUser?.email else {
             print("User is not signed in.")
             return
         }
         
         guard let pdfView = PDFViewWrapper.pdfView,
               let currentPage = pdfView.currentPage,
               let pageIndex = pdfView.document?.index(for: currentPage) else {
             print("Failed to get current page or index.")
             return
         }
         
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
             "pageNumber": pageIndex + 1, // Add the page number (incremented by 1 since pages are 0-indexed)
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
     


     
     
     
     func saveCommentAnnotation(_ annotation: PDFAnnotation) {
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
     
     
     func fetchCommentAnnotations() {
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

 struct PDFViewWrapper: UIViewRepresentable {
     let url: URL
     let handleTapGesture: (CGPoint) -> Void
     static var pdfView: PDFView? // Static reference to access pdfView
     
     func makeUIView(context: Context) -> PDFView {
         let pdfView = PDFView()
         pdfView.autoScales = true
         pdfView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = pdfView // Assign pdfView to static property
         
         let gestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
         pdfView.addGestureRecognizer(gestureRecognizer)
         
         return pdfView
     }
     
     func updateUIView(_ uiView: PDFView, context: Context) {
         uiView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = uiView // Update the static reference
     }
     
     func makeCoordinator() -> Coordinator {
         Coordinator(self)
     }
     
     class Coordinator: NSObject {
         let pdfViewWrapper: PDFViewWrapper
         
         init(_ pdfViewWrapper: PDFViewWrapper) {
             self.pdfViewWrapper = pdfViewWrapper
         }
         
         @objc func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
             let location = gestureRecognizer.location(in: PDFViewWrapper.pdfView)
             pdfViewWrapper.handleTapGesture(location)
         }
     }
     
     // Function to add an annotation to the current PDFPage
     static func addAnnotationToCurrentPage(annotation: PDFAnnotation) {
         if let currentPage = pdfView?.currentPage {
             currentPage.addAnnotation(annotation)
             pdfView?.setNeedsDisplay()
         }
     }
 }




 struct AnnotationToolbar: View {
     @Binding var selectedAnnotationType: PDFAnnotationSubtype?
     @Binding var isAddingComment: Bool
     @Binding var commentText: String?
     @Binding var showCommentDrawer: Bool
     @Binding var isTyping: Bool
     @Binding var fontColor: Color // Use Color instead of UIColor
     @Binding var showDeleteButton: Bool // Track whether to show the delete button
     @Binding var isBold: Bool // Track whether the text is bold
     @Binding var isItalic: Bool // Track whether the text is italic
     @Binding var fontSize: CGFloat // Track the selected font size
     var deleteAction: () -> Void // Action to delete the annotation
     @State private var isDropdownOpen = false
     let availableFontSizes: [CGFloat]
     let colorButtonSize: CGFloat = 24 // Size of the color buttons
     @Environment(\.colorScheme) var colorScheme

     var body: some View {

         ZStack {
             if !isTyping && !isAddingComment && !showDeleteButton{
                 HStack {
                     Button(action: {
                         selectedAnnotationType = nil
                         isAddingComment.toggle()
                     }) {
                         Image(systemName: "rectangle.and.pencil.and.ellipsis")
                     }
                     .foregroundColor(.primary)
                     
                     Button(action: {
                         selectedAnnotationType = .freeText
                         isTyping.toggle()
                     }) {
                         Image(systemName: "pencil.tip")
                     }
                     .foregroundColor(.primary)
                 }
             }
             else if isAddingComment {
                 Button(action: {
                     selectedAnnotationType = nil
                     isAddingComment.toggle()
                 }) {
                     Image(systemName: "rectangle.and.pencil.and.ellipsis")
                 }
                 .foregroundColor(.blue )
             }
             else if isTyping {
                 HStack(spacing: 0) {
                     Button(action: {
                         isBold.toggle()
                     }) {
                         Image(systemName: isBold ? "bold" : "bold")
                     }
                     .foregroundColor(isBold ? .blue : .primary)
                     
                     Button(action: {
                         isItalic.toggle()
                     }) {
                         Image(systemName: isItalic ? "italic" : "italic")
                     }
                     .foregroundColor(isItalic ? .blue : .primary)
                     
                     //ColorButton(color: .black, isSelected: fontColor == .black, action: { fontColor = .black })
                     ColorButton(color: .red, isSelected: fontColor == .red, action: { fontColor = .red })
                     ColorButton(color: .green, isSelected: fontColor == .green, action: { fontColor = .green })
                     ColorButton(color: .blue, isSelected: fontColor == .blue, action: { fontColor = .blue })
                     
                     Menu {
                         ForEach(availableFontSizes, id: \.self) { size in
                             Button(action: {
                                 fontSize = size
                             }) {
                                 Text("\(Int(size))")
                             }
                         }
                     } label: {
                         HStack {
                             Text("Size: \(Int(fontSize))")
                         }
                     }
                     
                     
                     Button(action: {
                         isTyping.toggle()
                     }) {
                         Image(systemName: "pencil.tip")
                             .foregroundColor(isTyping ? .blue : .primary)
                     }
                 }
                 .frame(maxWidth: .infinity)
                 .padding(.horizontal, 8)
             }
             
             
             else if showDeleteButton {
                 Button(action: deleteAction) {
                     Image(systemName: "trash")
                 }
                 .foregroundColor(.red)
             }
             
             
         }

     }
 }

 struct ColorButton: View {
     var color: Color
     var isSelected: Bool
     var action: () -> Void
     
     var body: some View {
         Button(action: action) {
             ZStack {
                 Circle()
                     .fill(color)
                     .frame(width: 5, height: 5)
                 
                 if isSelected {
                     Image(systemName: "checkmark.circle.fill")
                         .foregroundColor(.white)
                 }
             }
         }
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
