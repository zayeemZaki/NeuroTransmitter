import SwiftUI
import PDFKit
import FirebaseFirestore

struct PDFViewWrapper: UIViewRepresentable {
    let url: URL
    let handleTapGesture: (CGPoint) -> Void
    static var pdfView: PDFView?
    @Binding var isHighlighting: Bool
    @Binding var selectedHighlightAnnotation: HighlightPDFAnnotation?
    @Binding var selectedColor: UIColor

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = PDFDocument(url: url)
        pdfView.autoScales = true

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionChanged(_:)),
            name: Notification.Name.PDFViewSelectionChanged,
            object: pdfView
        )

        // Tap gesture recognizer
        let tapGestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
        tapGestureRecognizer.delaysTouchesBegan = true
        pdfView.addGestureRecognizer(tapGestureRecognizer)

        // Long press gesture recognizer
        let longPressGesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPressGesture(_:)))
        longPressGesture.delegate = context.coordinator
        pdfView.addGestureRecognizer(longPressGesture)
        longPressGesture.cancelsTouchesInView = true

        PDFViewWrapper.pdfView = pdfView
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = PDFDocument(url: url)
        PDFViewWrapper.pdfView = uiView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self, documentURL: url, isHighlighting: $isHighlighting, selectedColor: $selectedColor)
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var pdfViewWrapper: PDFViewWrapper
        var documentURL: URL
        var isHighlighting: Binding<Bool>
        var selectedColor: Binding<UIColor>
        var selectedAnnotation: CustomPDFAnnotation?

        private var selectionTimer: Timer?

        init(_ pdfViewWrapper: PDFViewWrapper, documentURL: URL, isHighlighting: Binding<Bool>, selectedColor: Binding<UIColor>) {
            self.pdfViewWrapper = pdfViewWrapper
            self.documentURL = documentURL
            self.isHighlighting = isHighlighting
            self.selectedColor = selectedColor
        }

        @objc func selectionChanged(_ notification: Notification) {
            guard isHighlighting.wrappedValue, let pdfView = notification.object as? PDFView else { return }
            selectionTimer?.invalidate()
            selectionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                guard let self = self, let currentSelection = pdfView.currentSelection else { return }
                self.createHighlightAnnotations(for: currentSelection, in: pdfView)
            }
        }

        func createHighlightAnnotations(for selection: PDFSelection, in pdfView: PDFView) {
            guard let document = pdfView.document, let page = selection.pages.first else { return }
            let selectionsByLine = selection.selectionsByLine()
            var minX = CGFloat.greatestFiniteMagnitude
            var minY = CGFloat.greatestFiniteMagnitude
            var maxX = CGFloat.leastNormalMagnitude
            var maxY = CGFloat.leastNormalMagnitude

            for selection in selectionsByLine {
                let bounds = selection.bounds(for: page)
                if bounds != .zero {
                    minX = min(minX, bounds.minX)
                    minY = min(minY, bounds.minY)
                    maxX = max(maxX, bounds.maxX)
                    maxY = max(maxY, bounds.maxY)
                }
            }

            if minX < CGFloat.greatestFiniteMagnitude && maxX > CGFloat.leastNormalMagnitude {
                let encompassingBounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                let pageIndex = pdfView.document?.index(for: page) ?? 0

                let existingAnnotations = page.annotations.filter { $0.bounds.intersects(encompassingBounds) && $0.isKind(of: HighlightPDFAnnotation.self) }
                if existingAnnotations.isEmpty {
                    let annotation = HighlightPDFAnnotation(bounds: encompassingBounds, forType: .highlight, withProperties: nil)
                    annotation.annotationID = UUID().uuidString
                    annotation.color = selectedColor.wrappedValue.withAlphaComponent(0.5)
                    page.addAnnotation(annotation)
                    // Save or handle the annotation as needed
                    saveHighlightAnnotation(annotation, documentURL: documentURL, pageIndex: pageIndex)

                }
            }
        }

        @objc func handleLongPressGesture(_ gesture: UILongPressGestureRecognizer) {
            guard let pdfView = PDFViewWrapper.pdfView, let page = pdfView.currentPage else { return }
            let location = gesture.location(in: pdfView)
            let convertedLocation = pdfView.convert(location, to: page)

            switch gesture.state {
            case .began:
                if let annotation = page.annotation(at: convertedLocation) as? CustomPDFAnnotation {
                    self.selectedAnnotation = annotation
                }
            case .changed:
                if let annotation = self.selectedAnnotation {
                    let newBounds = CGRect(x: convertedLocation.x - (annotation.bounds.size.width / 2),
                                           y: convertedLocation.y - (annotation.bounds.size.height / 2),
                                           width: annotation.bounds.size.width,
                                           height: annotation.bounds.size.height)
                    annotation.bounds = newBounds
                    pdfView.setNeedsDisplay(newBounds)
                }
            case .ended, .cancelled:
                if let annotation = self.selectedAnnotation {
                    // Update the annotation position in Firestore
                    updateAnnotationPositionInFirestore(annotation, documentURL: documentURL)
                }
                self.selectedAnnotation = nil
            default: break
            }
        }


        @objc func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
            let location = gestureRecognizer.location(in: PDFViewWrapper.pdfView)
            pdfViewWrapper.handleTapGesture(location)
            selectionTimer?.invalidate()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // This can be refined based on your specific needs
            return true
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let pdfView = PDFViewWrapper.pdfView, let page = pdfView.currentPage else { return false }
            let location = touch.location(in: pdfView)
            let convertedLocation = pdfView.convert(location, to: page)
            
            // Check if the touch is within an annotation bounds
            if let annotation = page.annotation(at: convertedLocation) as? CustomPDFAnnotation {
                self.selectedAnnotation = annotation
                return true  // The gesture should receive this touch
            }
            
            return false  // Prevent the gesture from recognizing touches not on annotations
        }
        func updateAnnotationPositionInFirestore(_ annotation: CustomPDFAnnotation, documentURL: URL) {
            guard let annotationID = annotation.annotationID else {
                print("Annotation ID is missing.")
                return
            }
            print(annotationID)
            let db = Firestore.firestore()
            let annotationRef = db.collection("onDocumentComments")
                                   .document(documentURL.lastPathComponent)
                                   .collection("annotations")
                                   .document(annotationID)
            
            let updatedPosition: [String: Any] = [
                "bounds": [
                    "x": annotation.bounds.origin.x,
                    "y": annotation.bounds.origin.y,
                    "width": annotation.bounds.size.width,
                    "height": annotation.bounds.size.height
                ]
            ]
            
            annotationRef.updateData(updatedPosition) { error in
                if let error = error {
                    print("Error updating annotation position: \(error.localizedDescription)")
                } else {
                    print("Annotation position updated successfully")
                }
            }
        }

    }

    static func addAnnotationToCurrentPage(annotation: PDFAnnotation) {
        guard let currentPage = pdfView?.currentPage else { return }
        currentPage.addAnnotation(annotation)
        pdfView?.setNeedsDisplay()
    }

    static func getPageIndexForTouchedLocation(_ location: CGPoint) -> Int? {
        guard let pdfView = pdfView, let page = pdfView.page(for: pdfView.convert(location, to: pdfView.currentPage!), nearest: true) else { return nil }
        return pdfView.document?.index(for: page)
    }
}



/*
 import SwiftUI
 import PDFKit
 import FirebaseFirestore

 struct PDFViewWrapper: UIViewRepresentable {
     let url: URL
     let handleTapGesture: (CGPoint) -> Void
     static var pdfView: PDFView?
     @Binding var isHighlighting: Bool
     @Binding var selectedHighlightAnnotation: HighlightPDFAnnotation?
     @Binding var selectedColor: UIColor

     func makeUIView(context: Context) -> PDFView {
         let pdfView = PDFView()
         pdfView.document = PDFDocument(url: url)
         pdfView.autoScales = true

         NotificationCenter.default.addObserver(
             context.coordinator,
             selector: #selector(Coordinator.selectionChanged(_:)),
             name: Notification.Name.PDFViewSelectionChanged,
             object: pdfView
         )

         // Tap gesture recognizer
         let tapGestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
         tapGestureRecognizer.delaysTouchesBegan = true
         pdfView.addGestureRecognizer(tapGestureRecognizer)

         // Long press gesture recognizer
         let longPressGesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPressGesture(_:)))
         longPressGesture.delegate = context.coordinator
         pdfView.addGestureRecognizer(longPressGesture)
         longPressGesture.cancelsTouchesInView = true

         PDFViewWrapper.pdfView = pdfView
         return pdfView
     }

     func updateUIView(_ uiView: PDFView, context: Context) {
         uiView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = uiView
     }

     func makeCoordinator() -> Coordinator {
         Coordinator(self, documentURL: url, isHighlighting: $isHighlighting, selectedColor: $selectedColor)
     }

     class Coordinator: NSObject, UIGestureRecognizerDelegate {
         var pdfViewWrapper: PDFViewWrapper
         var documentURL: URL
         var isHighlighting: Binding<Bool>
         var selectedColor: Binding<UIColor>
         var selectedAnnotation: CustomPDFAnnotation?

         private var selectionTimer: Timer?

         init(_ pdfViewWrapper: PDFViewWrapper, documentURL: URL, isHighlighting: Binding<Bool>, selectedColor: Binding<UIColor>) {
             self.pdfViewWrapper = pdfViewWrapper
             self.documentURL = documentURL
             self.isHighlighting = isHighlighting
             self.selectedColor = selectedColor
         }

         @objc func selectionChanged(_ notification: Notification) {
             guard isHighlighting.wrappedValue, let pdfView = notification.object as? PDFView else { return }
             selectionTimer?.invalidate()
             selectionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                 guard let self = self, let currentSelection = pdfView.currentSelection else { return }
                 self.createHighlightAnnotations(for: currentSelection, in: pdfView)
             }
         }

         func createHighlightAnnotations(for selection: PDFSelection, in pdfView: PDFView) {
             guard let document = pdfView.document, let page = selection.pages.first else { return }
             let selectionsByLine = selection.selectionsByLine()
             var minX = CGFloat.greatestFiniteMagnitude
             var minY = CGFloat.greatestFiniteMagnitude
             var maxX = CGFloat.leastNormalMagnitude
             var maxY = CGFloat.leastNormalMagnitude

             for selection in selectionsByLine {
                 let bounds = selection.bounds(for: page)
                 if bounds != .zero {
                     minX = min(minX, bounds.minX)
                     minY = min(minY, bounds.minY)
                     maxX = max(maxX, bounds.maxX)
                     maxY = max(maxY, bounds.maxY)
                 }
             }

             if minX < CGFloat.greatestFiniteMagnitude && maxX > CGFloat.leastNormalMagnitude {
                 let encompassingBounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                 let pageIndex = pdfView.document?.index(for: page) ?? 0

                 let existingAnnotations = page.annotations.filter { $0.bounds.intersects(encompassingBounds) && $0.isKind(of: HighlightPDFAnnotation.self) }
                 if existingAnnotations.isEmpty {
                     let annotation = HighlightPDFAnnotation(bounds: encompassingBounds, forType: .highlight, withProperties: nil)
                     annotation.annotationID = UUID().uuidString
                     annotation.color = selectedColor.wrappedValue.withAlphaComponent(0.5)
                     page.addAnnotation(annotation)
                     // Save or handle the annotation as needed
                     saveHighlightAnnotation(annotation, documentURL: documentURL, pageIndex: pageIndex)

                 }
             }
         }

         @objc func handleLongPressGesture(_ gesture: UILongPressGestureRecognizer) {
             guard let pdfView = PDFViewWrapper.pdfView, let page = pdfView.currentPage else { return }
             let location = gesture.location(in: pdfView)
             let convertedLocation = pdfView.convert(location, to: page)

             switch gesture.state {
             case .began:
                 if let annotation = page.annotation(at: convertedLocation) as? CustomPDFAnnotation {
                     self.selectedAnnotation = annotation
                 }
             case .changed:
                 if let annotation = self.selectedAnnotation {
                     let newBounds = CGRect(x: convertedLocation.x - (annotation.bounds.size.width / 2),
                                            y: convertedLocation.y - (annotation.bounds.size.height / 2),
                                            width: annotation.bounds.size.width,
                                            height: annotation.bounds.size.height)
                     annotation.bounds = newBounds
                     pdfView.setNeedsDisplay(newBounds)
                 }
             case .ended, .cancelled:
                 if let annotation = self.selectedAnnotation {
                     // Update the annotation position in Firestore
                     updateAnnotationPositionInFirestore(annotation, documentURL: documentURL)
                 }
                 self.selectedAnnotation = nil
             default: break
             }
         }


         @objc func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
             let location = gestureRecognizer.location(in: PDFViewWrapper.pdfView)
             pdfViewWrapper.handleTapGesture(location)
             selectionTimer?.invalidate()
         }

         func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
             // This can be refined based on your specific needs
             return true
         }
         
         func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
             guard let pdfView = PDFViewWrapper.pdfView, let page = pdfView.currentPage else { return false }
             let location = touch.location(in: pdfView)
             let convertedLocation = pdfView.convert(location, to: page)
             
             // Check if the touch is within an annotation bounds
             if let annotation = page.annotation(at: convertedLocation) as? CustomPDFAnnotation {
                 self.selectedAnnotation = annotation
                 return true  // The gesture should receive this touch
             }
             
             return false  // Prevent the gesture from recognizing touches not on annotations
         }
         func updateAnnotationPositionInFirestore(_ annotation: CustomPDFAnnotation, documentURL: URL) {
             guard let annotationID = annotation.annotationID else {
                 print("Annotation ID is missing.")
                 return
             }
             print(annotationID)
             let db = Firestore.firestore()
             let annotationRef = db.collection("onDocumentComments")
                                    .document(documentURL.lastPathComponent)
                                    .collection("annotations")
                                    .document(annotationID)
             
             let updatedPosition: [String: Any] = [
                 "bounds": [
                     "x": annotation.bounds.origin.x,
                     "y": annotation.bounds.origin.y,
                     "width": annotation.bounds.size.width,
                     "height": annotation.bounds.size.height
                 ]
             ]
             
             annotationRef.updateData(updatedPosition) { error in
                 if let error = error {
                     print("Error updating annotation position: \(error.localizedDescription)")
                 } else {
                     print("Annotation position updated successfully")
                 }
             }
         }

     }

     static func addAnnotationToCurrentPage(annotation: PDFAnnotation) {
         guard let currentPage = pdfView?.currentPage else { return }
         currentPage.addAnnotation(annotation)
         pdfView?.setNeedsDisplay()
     }

     static func getPageIndexForTouchedLocation(_ location: CGPoint) -> Int? {
         guard let pdfView = pdfView, let page = pdfView.page(for: pdfView.convert(location, to: pdfView.currentPage!), nearest: true) else { return nil }
         return pdfView.document?.index(for: page)
     }
 }

 */






/*
 import SwiftUI
 import PDFKit
 import FirebaseFirestore

 struct PDFViewWrapper: UIViewRepresentable {
     let url: URL
     let handleTapGesture: (CGPoint) -> Void
     static var pdfView: PDFView?
     @Binding var isHighlighting: Bool
     @Binding var selectedHighlightAnnotation: HighlightPDFAnnotation?
     @Binding var selectedColor: UIColor

     func makeUIView(context: Context) -> PDFView {
         let pdfView = PDFView()
         pdfView.document = PDFDocument(url: url)
         pdfView.autoScales = true

         NotificationCenter.default.addObserver(
             context.coordinator,
             selector: #selector(Coordinator.selectionChanged(_:)),
             name: Notification.Name.PDFViewSelectionChanged,
             object: pdfView
         )

         // Tap gesture recognizer
         let tapGestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
         tapGestureRecognizer.delaysTouchesBegan = true
         pdfView.addGestureRecognizer(tapGestureRecognizer)

         // Long press gesture recognizer
         let longPressGesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPressGesture(_:)))
         longPressGesture.delegate = context.coordinator
         pdfView.addGestureRecognizer(longPressGesture)
         longPressGesture.cancelsTouchesInView = true

         PDFViewWrapper.pdfView = pdfView
         return pdfView
     }

     func updateUIView(_ uiView: PDFView, context: Context) {
         uiView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = uiView
     }

     func makeCoordinator() -> Coordinator {
         Coordinator(self, documentURL: url, isHighlighting: $isHighlighting, selectedColor: $selectedColor)
     }

     class Coordinator: NSObject, UIGestureRecognizerDelegate {
         var pdfViewWrapper: PDFViewWrapper
         var documentURL: URL
         var isHighlighting: Binding<Bool>
         var selectedColor: Binding<UIColor>
         var selectedAnnotation: CustomPDFAnnotation?

         private var selectionTimer: Timer?

         init(_ pdfViewWrapper: PDFViewWrapper, documentURL: URL, isHighlighting: Binding<Bool>, selectedColor: Binding<UIColor>) {
             self.pdfViewWrapper = pdfViewWrapper
             self.documentURL = documentURL
             self.isHighlighting = isHighlighting
             self.selectedColor = selectedColor
         }

         @objc func selectionChanged(_ notification: Notification) {
             guard isHighlighting.wrappedValue, let pdfView = notification.object as? PDFView else { return }
             selectionTimer?.invalidate()
             selectionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                 guard let self = self, let currentSelection = pdfView.currentSelection else { return }
                 self.createHighlightAnnotations(for: currentSelection, in: pdfView)
             }
         }

         func createHighlightAnnotations(for selection: PDFSelection, in pdfView: PDFView) {
             guard let document = pdfView.document, let page = selection.pages.first else { return }
             let selectionsByLine = selection.selectionsByLine()
             var minX = CGFloat.greatestFiniteMagnitude
             var minY = CGFloat.greatestFiniteMagnitude
             var maxX = CGFloat.leastNormalMagnitude
             var maxY = CGFloat.leastNormalMagnitude

             for selection in selectionsByLine {
                 let bounds = selection.bounds(for: page)
                 if bounds != .zero {
                     minX = min(minX, bounds.minX)
                     minY = min(minY, bounds.minY)
                     maxX = max(maxX, bounds.maxX)
                     maxY = max(maxY, bounds.maxY)
                 }
             }

             if minX < CGFloat.greatestFiniteMagnitude && maxX > CGFloat.leastNormalMagnitude {
                 let encompassingBounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                 let pageIndex = pdfView.document?.index(for: page) ?? 0

                 let existingAnnotations = page.annotations.filter { $0.bounds.intersects(encompassingBounds) && $0.isKind(of: HighlightPDFAnnotation.self) }
                 if existingAnnotations.isEmpty {
                     let annotation = HighlightPDFAnnotation(bounds: encompassingBounds, forType: .highlight, withProperties: nil)
                     annotation.annotationID = UUID().uuidString
                     annotation.color = selectedColor.wrappedValue.withAlphaComponent(0.5)
                     page.addAnnotation(annotation)
                     // Save or handle the annotation as needed
                     saveHighlightAnnotation(annotation, documentURL: documentURL, pageIndex: pageIndex)

                 }
             }
         }

         @objc func handleLongPressGesture(_ gesture: UILongPressGestureRecognizer) {
             guard let pdfView = PDFViewWrapper.pdfView, let page = pdfView.currentPage else { return }
             let location = gesture.location(in: pdfView)
             let convertedLocation = pdfView.convert(location, to: page)

             switch gesture.state {
             case .began:
                 if let annotation = page.annotation(at: convertedLocation) as? CustomPDFAnnotation {
                     self.selectedAnnotation = annotation
                 }
             case .changed:
                 if let annotation = self.selectedAnnotation {
                     let newBounds = CGRect(x: convertedLocation.x - (annotation.bounds.size.width / 2),
                                            y: convertedLocation.y - (annotation.bounds.size.height / 2),
                                            width: annotation.bounds.size.width,
                                            height: annotation.bounds.size.height)
                     annotation.bounds = newBounds
                     pdfView.setNeedsDisplay(newBounds)
                 }
             case .ended, .cancelled:
                 if let annotation = self.selectedAnnotation {
                     // Update the annotation position in Firestore
                     updateAnnotationPositionInFirestore(annotation, documentURL: documentURL)
                 }
                 self.selectedAnnotation = nil
             default: break
             }
         }


         @objc func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
             let location = gestureRecognizer.location(in: PDFViewWrapper.pdfView)
             pdfViewWrapper.handleTapGesture(location)
             selectionTimer?.invalidate()
         }

         func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
             // This can be refined based on your specific needs
             return true
         }
         
         func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
             guard let pdfView = PDFViewWrapper.pdfView, let page = pdfView.currentPage else { return false }
             let location = touch.location(in: pdfView)
             let convertedLocation = pdfView.convert(location, to: page)
             
             // Check if the touch is within an annotation bounds
             if let annotation = page.annotation(at: convertedLocation) as? CustomPDFAnnotation {
                 self.selectedAnnotation = annotation
                 return true  // The gesture should receive this touch
             }
             
             return false  // Prevent the gesture from recognizing touches not on annotations
         }
         func updateAnnotationPositionInFirestore(_ annotation: CustomPDFAnnotation, documentURL: URL) {
             guard let annotationID = annotation.annotationID else {
                 print("Annotation ID is missing.")
                 return
             }
             
             let db = Firestore.firestore()
             let annotationRef = db.collection("onDocumentComments")
                                    .document(documentURL.lastPathComponent)
                                    .collection("annotations")
                                    .document(annotationID)
             
             let updatedPosition: [String: Any] = [
                 "bounds": [
                     "x": annotation.bounds.origin.x,
                     "y": annotation.bounds.origin.y,
                     "width": annotation.bounds.size.width,
                     "height": annotation.bounds.size.height
                 ]
             ]
             
             annotationRef.updateData(updatedPosition) { error in
                 if let error = error {
                     print("Error updating annotation position: \(error.localizedDescription)")
                 } else {
                     print("Annotation position updated successfully")
                 }
             }
         }

     }

     static func addAnnotationToCurrentPage(annotation: PDFAnnotation) {
         guard let currentPage = pdfView?.currentPage else { return }
         currentPage.addAnnotation(annotation)
         pdfView?.setNeedsDisplay()
     }

     static func getPageIndexForTouchedLocation(_ location: CGPoint) -> Int? {
         guard let pdfView = pdfView, let page = pdfView.page(for: pdfView.convert(location, to: pdfView.currentPage!), nearest: true) else { return nil }
         return pdfView.document?.index(for: page)
     }
 }
 */












/*
 import SwiftUI
 import PDFKit

 struct PDFViewWrapper: UIViewRepresentable {
     let url: URL
     let handleTapGesture: (CGPoint) -> Void
     static var pdfView: PDFView?
     @Binding var isHighlighting: Bool
     @Binding var selectedHighlightAnnotation: HighlightPDFAnnotation?
     @Binding var selectedColor: UIColor

     func makeUIView(context: Context) -> PDFView {
         let pdfView = PDFView()
         pdfView.document = PDFDocument(url: url)
         pdfView.autoScales = true

         NotificationCenter.default.addObserver(
             context.coordinator,
             selector: #selector(Coordinator.selectionChanged(_:)),
             name: Notification.Name.PDFViewSelectionChanged,
             object: pdfView
         )

         // Tap gesture recognizer
         let tapGestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
         tapGestureRecognizer.delaysTouchesBegan = true
         pdfView.addGestureRecognizer(tapGestureRecognizer)

         // Long press gesture recognizer
         let longPressGesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPressGesture(_:)))
         longPressGesture.delegate = context.coordinator
         pdfView.addGestureRecognizer(longPressGesture)
         longPressGesture.cancelsTouchesInView = true

         PDFViewWrapper.pdfView = pdfView
         return pdfView
     }

     func updateUIView(_ uiView: PDFView, context: Context) {
         uiView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = uiView
     }

     func makeCoordinator() -> Coordinator {
         Coordinator(self, documentURL: url, isHighlighting: $isHighlighting, selectedColor: $selectedColor)
     }

     class Coordinator: NSObject, UIGestureRecognizerDelegate {
         var pdfViewWrapper: PDFViewWrapper
         var documentURL: URL
         var isHighlighting: Binding<Bool>
         var selectedColor: Binding<UIColor>
         var selectedAnnotation: CustomPDFAnnotation?

         private var selectionTimer: Timer?

         init(_ pdfViewWrapper: PDFViewWrapper, documentURL: URL, isHighlighting: Binding<Bool>, selectedColor: Binding<UIColor>) {
             self.pdfViewWrapper = pdfViewWrapper
             self.documentURL = documentURL
             self.isHighlighting = isHighlighting
             self.selectedColor = selectedColor
         }

         @objc func selectionChanged(_ notification: Notification) {
             guard isHighlighting.wrappedValue, let pdfView = notification.object as? PDFView else { return }
             selectionTimer?.invalidate()
             selectionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                 guard let self = self, let currentSelection = pdfView.currentSelection else { return }
                 self.createHighlightAnnotations(for: currentSelection, in: pdfView)
             }
         }

         func createHighlightAnnotations(for selection: PDFSelection, in pdfView: PDFView) {
             guard let document = pdfView.document, let page = selection.pages.first else { return }
             let selectionsByLine = selection.selectionsByLine()
             var minX = CGFloat.greatestFiniteMagnitude
             var minY = CGFloat.greatestFiniteMagnitude
             var maxX = CGFloat.leastNormalMagnitude
             var maxY = CGFloat.leastNormalMagnitude

             for selection in selectionsByLine {
                 let bounds = selection.bounds(for: page)
                 if bounds != .zero {
                     minX = min(minX, bounds.minX)
                     minY = min(minY, bounds.minY)
                     maxX = max(maxX, bounds.maxX)
                     maxY = max(maxY, bounds.maxY)
                 }
             }

             if minX < CGFloat.greatestFiniteMagnitude && maxX > CGFloat.leastNormalMagnitude {
                 let encompassingBounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                 let pageIndex = pdfView.document?.index(for: page) ?? 0

                 let existingAnnotations = page.annotations.filter { $0.bounds.intersects(encompassingBounds) && $0.isKind(of: HighlightPDFAnnotation.self) }
                 if existingAnnotations.isEmpty {
                     let annotation = HighlightPDFAnnotation(bounds: encompassingBounds, forType: .highlight, withProperties: nil)
                     annotation.annotationID = UUID().uuidString
                     annotation.color = selectedColor.wrappedValue.withAlphaComponent(0.5)
                     page.addAnnotation(annotation)
                     // Save or handle the annotation as needed
                 }
             }
         }

         @objc func handleLongPressGesture(_ gesture: UILongPressGestureRecognizer) {
             guard !isHighlighting.wrappedValue else {
                 gesture.state = .cancelled // Cancel the gesture if highlighting mode is active
                 return
             }
             guard let pdfView = PDFViewWrapper.pdfView, let page = pdfView.currentPage else { return }
             let location = gesture.location(in: pdfView)
             let convertedLocation = pdfView.convert(location, to: page)

             switch gesture.state {
             case .began:
                 if let annotation = page.annotation(at: convertedLocation) as? CustomPDFAnnotation {
                     self.selectedAnnotation = annotation
                 }
             case .changed:
                 if let annotation = self.selectedAnnotation {
                     let newBounds = CGRect(x: convertedLocation.x - (annotation.bounds.size.width / 2),
                                            y: convertedLocation.y - (annotation.bounds.size.height / 2),
                                            width: annotation.bounds.size.width,
                                            height: annotation.bounds.size.height)
                     annotation.bounds = newBounds
                     pdfView.setNeedsDisplay(newBounds)
                 }
             case .ended, .cancelled:
                 self.selectedAnnotation = nil
             default: break
             }
         }

         @objc func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
             let location = gestureRecognizer.location(in: PDFViewWrapper.pdfView)
             pdfViewWrapper.handleTapGesture(location)
             selectionTimer?.invalidate()
         }

         func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
             // This can be refined based on your specific needs
             return true
         }
         
         func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
             guard let pdfView = PDFViewWrapper.pdfView, let page = pdfView.currentPage else { return false }
             let location = touch.location(in: pdfView)
             let convertedLocation = pdfView.convert(location, to: page)
             
             // Check if the touch is within an annotation bounds
             if let annotation = page.annotation(at: convertedLocation) as? CustomPDFAnnotation {
                 self.selectedAnnotation = annotation
                 return true  // The gesture should receive this touch
             }
             
             return false  // Prevent the gesture from recognizing touches not on annotations
         }

     }

     static func addAnnotationToCurrentPage(annotation: PDFAnnotation) {
         guard let currentPage = pdfView?.currentPage else { return }
         currentPage.addAnnotation(annotation)
         pdfView?.setNeedsDisplay()
     }

     static func getPageIndexForTouchedLocation(_ location: CGPoint) -> Int? {
         guard let pdfView = pdfView, let page = pdfView.page(for: pdfView.convert(location, to: pdfView.currentPage!), nearest: true) else { return nil }
         return pdfView.document?.index(for: page)
     }
 }
 */














/*
import SwiftUI
import PDFKit

struct PDFViewWrapper: UIViewRepresentable {
    let url: URL
    let handleTapGesture: (CGPoint) -> Void
    static var pdfView: PDFView?
    @Binding var isHighlighting: Bool
    @Binding var selectedHighlightAnnotation: HighlightPDFAnnotation?
    @Binding var selectedColor: UIColor

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = PDFDocument(url: url)
        pdfView.autoScales = true

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionChanged(_:)),
            name: Notification.Name.PDFViewSelectionChanged,
            object: pdfView
        )

        let gestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
        gestureRecognizer.delaysTouchesBegan = true
        pdfView.addGestureRecognizer(gestureRecognizer)
        
        // Add gesture recognizers
        let longPressGesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleLongPressGesture(_:)))
        pdfView.addGestureRecognizer(longPressGesture)


        PDFViewWrapper.pdfView = pdfView
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = PDFDocument(url: url)
        PDFViewWrapper.pdfView = uiView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self, documentURL: url, isHighlighting: $isHighlighting, selectedColor: $selectedColor)
    }

    class Coordinator: NSObject {
        var pdfViewWrapper: PDFViewWrapper
        var documentURL: URL
        var isHighlighting: Binding<Bool>
        var selectedColor: Binding<UIColor>
        var selectedAnnotation: PDFAnnotation?

        private var selectionTimer: Timer?

        
        
        init(_ pdfViewWrapper: PDFViewWrapper, documentURL: URL, isHighlighting: Binding<Bool>, selectedColor: Binding<UIColor>) {
            self.pdfViewWrapper = pdfViewWrapper
            self.documentURL = documentURL
            self.isHighlighting = isHighlighting
            self.selectedColor = selectedColor
        }

        @objc func selectionChanged(_ notification: Notification) {
            guard isHighlighting.wrappedValue, let pdfView = notification.object as? PDFView else { return }

            // Invalidate and nullify the existing timer to start fresh
            selectionTimer?.invalidate()
            selectionTimer = nil

            // Start a new timer to check if the selection persists for more than 1 second
            selectionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                guard let self = self, let currentSelection = pdfView.currentSelection else { return }
                // Proceed to create highlight annotations since the selection persisted for more than 1 second
                self.createHighlightAnnotations(for: currentSelection, in: pdfView)
            }
        }

        func createHighlightAnnotations(for selection: PDFSelection, in pdfView: PDFView) {
            guard let document = pdfView.document, let page = selection.pages.first else { return }

            // Get the selections by line and calculate the encompassing bounds
            let selectionsByLine = selection.selectionsByLine()
            var minX = CGFloat.greatestFiniteMagnitude
            var minY = CGFloat.greatestFiniteMagnitude
            var maxX = CGFloat.leastNormalMagnitude
            var maxY = CGFloat.leastNormalMagnitude

            for selection in selectionsByLine {
                let bounds = selection.bounds(for: page)
                if bounds != .zero {
                    minX = min(minX, bounds.minX)
                    minY = min(minY, bounds.minY)
                    maxX = max(maxX, bounds.maxX)
                    maxY = max(maxY, bounds.maxY)
                }
            }
            

            // Check if we have a valid rectangle
            if minX < CGFloat.greatestFiniteMagnitude && maxX > CGFloat.leastNormalMagnitude {
                let encompassingBounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                let pageIndex = (pdfView.document?.index(for: page))!

                // Check for existing annotations in this area to avoid duplicates
                let existingAnnotations = page.annotations.filter { $0.bounds.intersects(encompassingBounds) && $0.isKind(of: HighlightPDFAnnotation.self) }
                if existingAnnotations.isEmpty {
                    // Create a single annotation for the entire selection
                    let annotation = HighlightPDFAnnotation(bounds: encompassingBounds, forType: .highlight, withProperties: nil)
                    annotation.annotationID = UUID().uuidString
                    annotation.color = selectedColor.wrappedValue.withAlphaComponent(0.5)
                    page.addAnnotation(annotation)
                    saveHighlightAnnotation(annotation, documentURL: documentURL, pageIndex: pageIndex)

                }
            }
        }
        
        @objc func handleLongPressGesture(_ gesture: UILongPressGestureRecognizer) {
            guard let pdfView = PDFViewWrapper.pdfView else { return }
            let location = gesture.location(in: pdfView)
            
            switch gesture.state {
            case .began:
                // Check if an annotation exists at the location of the long press
                if let annotation = pdfView.currentPage?.annotation(at: pdfView.convert(location, to: pdfView.currentPage!)) as? CustomPDFAnnotation {
                    self.selectedAnnotation = annotation
                }
            case .changed:
                // If an annotation is selected, calculate its new position based on the gesture's location
                guard let selectedAnnotation = self.selectedAnnotation else { return }
                let newLocation = pdfView.convert(location, to: pdfView.currentPage!)
                
                // Calculate new bounds. This will center the annotation on the finger's position.
                let newBounds = CGRect(x: newLocation.x - (selectedAnnotation.bounds.size.width / 2),
                                       y: newLocation.y - (selectedAnnotation.bounds.size.height / 2),
                                       width: selectedAnnotation.bounds.size.width,
                                       height: selectedAnnotation.bounds.size.height)
                selectedAnnotation.bounds = newBounds
                
                pdfView.setNeedsDisplay(newBounds)
            case .ended, .cancelled:
                // Clear the selected annotation when the gesture ends or is cancelled
                self.selectedAnnotation = nil
            default:
                break
            }
            
        }

        
        @objc func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
            let location = gestureRecognizer.location(in: PDFViewWrapper.pdfView)
            pdfViewWrapper.handleTapGesture(location)
            // Optionally, invalidate the selection timer if a tap gesture should cancel the pending selection highlight
            selectionTimer?.invalidate()
            selectionTimer = nil
        }
    }

    static func addAnnotationToCurrentPage(annotation: PDFAnnotation) {
        if let currentPage = pdfView?.currentPage {
                currentPage.addAnnotation(annotation)
            pdfView?.setNeedsDisplay()
        }
    }

    static func getPageIndexForTouchedLocation(_ location: CGPoint) -> Int? {
        guard let pdfView = pdfView else {
            return nil
        }

        let touchedPoint = pdfView.convert(location, to: pdfView.currentPage!)
        if let page = pdfView.page(for: touchedPoint, nearest: true) {
            return pdfView.document?.index(for: page)
        }

        return nil
    }
}
 


*/













/*
 import SwiftUI
 import PDFKit

 struct PDFViewWrapper: UIViewRepresentable {
     let url: URL
     let handleTapGesture: (CGPoint) -> Void
     static var pdfView: PDFView?
     @Binding var isHighlighting: Bool
     @Binding var selectedHighlightAnnotation: HighlightPDFAnnotation?
     @Binding var selectedColor: UIColor

     func makeUIView(context: Context) -> PDFView {
         let pdfView = PDFView()
         pdfView.document = PDFDocument(url: url)
         pdfView.autoScales = true

         NotificationCenter.default.addObserver(
             context.coordinator,
             selector: #selector(Coordinator.selectionChanged(_:)),
             name: Notification.Name.PDFViewSelectionChanged,
             object: pdfView
         )

         let gestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
         gestureRecognizer.delaysTouchesBegan = true
         pdfView.addGestureRecognizer(gestureRecognizer)
         
         // Add gesture recognizers
         let longPressGesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleLongPressGesture(_:)))
         pdfView.addGestureRecognizer(longPressGesture)


         PDFViewWrapper.pdfView = pdfView
         return pdfView
     }

     func updateUIView(_ uiView: PDFView, context: Context) {
         uiView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = uiView
     }

     func makeCoordinator() -> Coordinator {
         Coordinator(self, documentURL: url, isHighlighting: $isHighlighting, selectedColor: $selectedColor)
     }

     class Coordinator: NSObject {
         var pdfViewWrapper: PDFViewWrapper
         var documentURL: URL
         var isHighlighting: Binding<Bool>
         var selectedColor: Binding<UIColor>
         var selectedAnnotation: PDFAnnotation?

         private var selectionTimer: Timer?

         init(_ pdfViewWrapper: PDFViewWrapper, documentURL: URL, isHighlighting: Binding<Bool>, selectedColor: Binding<UIColor>) {
             self.pdfViewWrapper = pdfViewWrapper
             self.documentURL = documentURL
             self.isHighlighting = isHighlighting
             self.selectedColor = selectedColor
         }

         @objc func selectionChanged(_ notification: Notification) {
             guard isHighlighting.wrappedValue, let pdfView = notification.object as? PDFView else { return }

             // Invalidate and nullify the existing timer to start fresh
             selectionTimer?.invalidate()
             selectionTimer = nil

             // Start a new timer to check if the selection persists for more than 1 second
             selectionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                 guard let self = self, let currentSelection = pdfView.currentSelection else { return }
                 // Proceed to create highlight annotations since the selection persisted for more than 1 second
                 self.createHighlightAnnotations(for: currentSelection, in: pdfView)
             }
         }

         func createHighlightAnnotations(for selection: PDFSelection, in pdfView: PDFView) {
             guard let document = pdfView.document, let page = selection.pages.first else { return }

             // Get the selections by line and calculate the encompassing bounds
             let selectionsByLine = selection.selectionsByLine()
             var minX = CGFloat.greatestFiniteMagnitude
             var minY = CGFloat.greatestFiniteMagnitude
             var maxX = CGFloat.leastNormalMagnitude
             var maxY = CGFloat.leastNormalMagnitude

             for selection in selectionsByLine {
                 let bounds = selection.bounds(for: page)
                 if bounds != .zero {
                     minX = min(minX, bounds.minX)
                     minY = min(minY, bounds.minY)
                     maxX = max(maxX, bounds.maxX)
                     maxY = max(maxY, bounds.maxY)
                 }
             }
             

             // Check if we have a valid rectangle
             if minX < CGFloat.greatestFiniteMagnitude && maxX > CGFloat.leastNormalMagnitude {
                 let encompassingBounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                 let pageIndex = (pdfView.document?.index(for: page))!

                 // Check for existing annotations in this area to avoid duplicates
                 let existingAnnotations = page.annotations.filter { $0.bounds.intersects(encompassingBounds) && $0.isKind(of: HighlightPDFAnnotation.self) }
                 if existingAnnotations.isEmpty {
                     // Create a single annotation for the entire selection
                     let annotation = HighlightPDFAnnotation(bounds: encompassingBounds, forType: .highlight, withProperties: nil)
                     annotation.annotationID = UUID().uuidString
                     annotation.color = selectedColor.wrappedValue.withAlphaComponent(0.5)
                     page.addAnnotation(annotation)
                     saveHighlightAnnotation(annotation, documentURL: documentURL, pageIndex: pageIndex)

                 }
             }
         }
         
         @objc func handleLongPressGesture(_ gesture: UILongPressGestureRecognizer) {
             guard let pdfView = PDFViewWrapper.pdfView else { return }
             let location = gesture.location(in: pdfView)
             
             switch gesture.state {
             case .began:
                 // Check if an annotation exists at the location of the long press
                 if let annotation = pdfView.currentPage?.annotation(at: pdfView.convert(location, to: pdfView.currentPage!)) as? CustomPDFAnnotation {
                     self.selectedAnnotation = annotation
                 }
             case .changed:
                 // If an annotation is selected, calculate its new position based on the gesture's location
                 guard let selectedAnnotation = self.selectedAnnotation else { return }
                 let newLocation = pdfView.convert(location, to: pdfView.currentPage!)
                 
                 // Calculate new bounds. This will center the annotation on the finger's position.
                 let newBounds = CGRect(x: newLocation.x - (selectedAnnotation.bounds.size.width / 2),
                                        y: newLocation.y - (selectedAnnotation.bounds.size.height / 2),
                                        width: selectedAnnotation.bounds.size.width,
                                        height: selectedAnnotation.bounds.size.height)
                 selectedAnnotation.bounds = newBounds
                 
                 pdfView.setNeedsDisplay(newBounds)
             case .ended, .cancelled:
                 // Clear the selected annotation when the gesture ends or is cancelled
                 self.selectedAnnotation = nil
             default:
                 break
             }
             
         }

         
         @objc func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
             let location = gestureRecognizer.location(in: PDFViewWrapper.pdfView)
             pdfViewWrapper.handleTapGesture(location)
             // Optionally, invalidate the selection timer if a tap gesture should cancel the pending selection highlight
             selectionTimer?.invalidate()
             selectionTimer = nil
         }
     }

     static func addAnnotationToCurrentPage(annotation: PDFAnnotation) {
         if let currentPage = pdfView?.currentPage {
                 currentPage.addAnnotation(annotation)
             pdfView?.setNeedsDisplay()
         }
     }

     static func getPageIndexForTouchedLocation(_ location: CGPoint) -> Int? {
         guard let pdfView = pdfView else {
             return nil
         }

         let touchedPoint = pdfView.convert(location, to: pdfView.currentPage!)
         if let page = pdfView.page(for: touchedPoint, nearest: true) {
             return pdfView.document?.index(for: page)
         }

         return nil
     }
 }
 


*/



/*
 
 import SwiftUI
 import PDFKit

 struct PDFViewWrapper: UIViewRepresentable {
     let url: URL
     let handleTapGesture: (CGPoint) -> Void
     static var pdfView: PDFView?
     @Binding var isHighlighting: Bool
     @Binding var selectedHighlightAnnotation: HighlightPDFAnnotation?
     @Binding var selectedColor: UIColor

     func makeUIView(context: Context) -> PDFView {
         let pdfView = PDFView()
         pdfView.document = PDFDocument(url: url)
         pdfView.autoScales = true

         NotificationCenter.default.addObserver(
             context.coordinator,
             selector: #selector(Coordinator.selectionChanged(_:)),
             name: Notification.Name.PDFViewSelectionChanged,
             object: pdfView
         )

         let gestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
         gestureRecognizer.delaysTouchesBegan = true
         pdfView.addGestureRecognizer(gestureRecognizer)
         
         // Add gesture recognizers
         let longPressGesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleLongPressGesture(_:)))
         pdfView.addGestureRecognizer(longPressGesture)


         PDFViewWrapper.pdfView = pdfView
         return pdfView
     }

     func updateUIView(_ uiView: PDFView, context: Context) {
         uiView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = uiView
     }

     func makeCoordinator() -> Coordinator {
         Coordinator(self, documentURL: url, isHighlighting: $isHighlighting, selectedColor: $selectedColor)
     }

     class Coordinator: NSObject {
         var pdfViewWrapper: PDFViewWrapper
         var documentURL: URL
         var isHighlighting: Binding<Bool>
         var selectedColor: Binding<UIColor>
         var selectedAnnotation: PDFAnnotation?

         private var selectionTimer: Timer?

         init(_ pdfViewWrapper: PDFViewWrapper, documentURL: URL, isHighlighting: Binding<Bool>, selectedColor: Binding<UIColor>) {
             self.pdfViewWrapper = pdfViewWrapper
             self.documentURL = documentURL
             self.isHighlighting = isHighlighting
             self.selectedColor = selectedColor
         }

         @objc func selectionChanged(_ notification: Notification) {
             guard isHighlighting.wrappedValue, let pdfView = notification.object as? PDFView else { return }

             // Invalidate and nullify the existing timer to start fresh
             selectionTimer?.invalidate()
             selectionTimer = nil

             // Start a new timer to check if the selection persists for more than 1 second
             selectionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                 guard let self = self, let currentSelection = pdfView.currentSelection else { return }
                 // Proceed to create highlight annotations since the selection persisted for more than 1 second
                 self.createHighlightAnnotations(for: currentSelection, in: pdfView)
             }
         }

         func createHighlightAnnotations(for selection: PDFSelection, in pdfView: PDFView) {
             guard let document = pdfView.document, let page = selection.pages.first else { return }

             // Get the selections by line and calculate the encompassing bounds
             let selectionsByLine = selection.selectionsByLine()
             var minX = CGFloat.greatestFiniteMagnitude
             var minY = CGFloat.greatestFiniteMagnitude
             var maxX = CGFloat.leastNormalMagnitude
             var maxY = CGFloat.leastNormalMagnitude

             for selection in selectionsByLine {
                 let bounds = selection.bounds(for: page)
                 if bounds != .zero {
                     minX = min(minX, bounds.minX)
                     minY = min(minY, bounds.minY)
                     maxX = max(maxX, bounds.maxX)
                     maxY = max(maxY, bounds.maxY)
                 }
             }
             

             // Check if we have a valid rectangle
             if minX < CGFloat.greatestFiniteMagnitude && maxX > CGFloat.leastNormalMagnitude {
                 let encompassingBounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                 let pageIndex = (pdfView.document?.index(for: page))!

                 // Check for existing annotations in this area to avoid duplicates
                 let existingAnnotations = page.annotations.filter { $0.bounds.intersects(encompassingBounds) && $0.isKind(of: HighlightPDFAnnotation.self) }
                 if existingAnnotations.isEmpty {
                     // Create a single annotation for the entire selection
                     let annotation = HighlightPDFAnnotation(bounds: encompassingBounds, forType: .highlight, withProperties: nil)
                     annotation.annotationID = UUID().uuidString
                     annotation.color = selectedColor.wrappedValue.withAlphaComponent(0.5)
                     page.addAnnotation(annotation)
                     saveHighlightAnnotation(annotation, documentURL: documentURL, pageIndex: pageIndex)

                 }
             }
         }
         
         @objc func handleLongPressGesture(_ gesture: UILongPressGestureRecognizer) {
             guard let pdfView = PDFViewWrapper.pdfView else { return }
             let location = gesture.location(in: pdfView)
             
             switch gesture.state {
             case .began:
                 // Check if an annotation exists at the location of the long press
                 if let annotation = pdfView.currentPage?.annotation(at: pdfView.convert(location, to: pdfView.currentPage!)) as? CustomPDFAnnotation {
                     self.selectedAnnotation = annotation
                 }
             case .changed:
                 // If an annotation is selected, calculate its new position based on the gesture's location
                 guard let selectedAnnotation = self.selectedAnnotation else { return }
                 let newLocation = pdfView.convert(location, to: pdfView.currentPage!)
                 
                 // Calculate new bounds. This will center the annotation on the finger's position.
                 let newBounds = CGRect(x: newLocation.x - (selectedAnnotation.bounds.size.width / 2),
                                        y: newLocation.y - (selectedAnnotation.bounds.size.height / 2),
                                        width: selectedAnnotation.bounds.size.width,
                                        height: selectedAnnotation.bounds.size.height)
                 selectedAnnotation.bounds = newBounds
                 
                 pdfView.setNeedsDisplay(newBounds)
             case .ended, .cancelled:
                 // Clear the selected annotation when the gesture ends or is cancelled
                 self.selectedAnnotation = nil
             default:
                 break
             }
             
         }

         
         @objc func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
             let location = gestureRecognizer.location(in: PDFViewWrapper.pdfView)
             pdfViewWrapper.handleTapGesture(location)
             // Optionally, invalidate the selection timer if a tap gesture should cancel the pending selection highlight
             selectionTimer?.invalidate()
             selectionTimer = nil
         }
     }

     static func addAnnotationToCurrentPage(annotation: PDFAnnotation) {
         if let currentPage = pdfView?.currentPage {
                 currentPage.addAnnotation(annotation)
             pdfView?.setNeedsDisplay()
         }
     }

     static func getPageIndexForTouchedLocation(_ location: CGPoint) -> Int? {
         guard let pdfView = pdfView else {
             return nil
         }

         let touchedPoint = pdfView.convert(location, to: pdfView.currentPage!)
         if let page = pdfView.page(for: touchedPoint, nearest: true) {
             return pdfView.document?.index(for: page)
         }

         return nil
     }
 }
 */







/*

 
 import SwiftUI
 import PDFKit

 struct PDFViewWrapper: UIViewRepresentable {
     let url: URL
     let handleTapGesture: (CGPoint) -> Void
     static var pdfView: PDFView?
     @Binding var isHighlighting: Bool
     @Binding var selectedOnDocumentAnnotation: CustomPDFAnnotation?
     @Binding var selectedColor: UIColor

     func makeUIView(context: Context) -> PDFView {
         let pdfView = PDFView()
         pdfView.document = PDFDocument(url: url)
         pdfView.autoScales = true

         NotificationCenter.default.addObserver(
             context.coordinator,
             selector: #selector(Coordinator.selectionChanged(_:)),
             name: Notification.Name.PDFViewSelectionChanged,
             object: pdfView
         )

         let gestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
         gestureRecognizer.delaysTouchesBegan = true
         pdfView.addGestureRecognizer(gestureRecognizer)

         PDFViewWrapper.pdfView = pdfView
         return pdfView
     }

     func updateUIView(_ uiView: PDFView, context: Context) {
         uiView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = uiView
     }

     func makeCoordinator() -> Coordinator {
         Coordinator(self, documentURL: url, isHighlighting: $isHighlighting, selectedColor: $selectedColor)
     }

     class Coordinator: NSObject {
         var pdfViewWrapper: PDFViewWrapper
         var documentURL: URL
         var isHighlighting: Binding<Bool>
         var selectedColor: Binding<UIColor>

         private var selectionTimer: Timer?

         init(_ pdfViewWrapper: PDFViewWrapper, documentURL: URL, isHighlighting: Binding<Bool>, selectedColor: Binding<UIColor>) {
             self.pdfViewWrapper = pdfViewWrapper
             self.documentURL = documentURL
             self.isHighlighting = isHighlighting
             self.selectedColor = selectedColor
         }

         @objc func selectionChanged(_ notification: Notification) {
             guard isHighlighting.wrappedValue, let pdfView = notification.object as? PDFView else { return }

             // Invalidate and nullify the existing timer to start fresh
             selectionTimer?.invalidate()
             selectionTimer = nil

             // Start a new timer to check if the selection persists for more than 1 second
             selectionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                 guard let self = self, let currentSelection = pdfView.currentSelection else { return }
                 // Proceed to create highlight annotations since the selection persisted for more than 1 second
                 self.createHighlightAnnotations(for: currentSelection, in: pdfView)
             }
         }

         func createHighlightAnnotations(for selection: PDFSelection, in pdfView: PDFView) {
             guard let document = pdfView.document, let page = selection.pages.first else { return }

             // Get the selections by line and calculate the encompassing bounds
             let selectionsByLine = selection.selectionsByLine()
             var minX = CGFloat.greatestFiniteMagnitude
             var minY = CGFloat.greatestFiniteMagnitude
             var maxX = CGFloat.leastNormalMagnitude
             var maxY = CGFloat.leastNormalMagnitude

             for selection in selectionsByLine {
                 let bounds = selection.bounds(for: page)
                 if bounds != .zero {
                     minX = min(minX, bounds.minX)
                     minY = min(minY, bounds.minY)
                     maxX = max(maxX, bounds.maxX)
                     maxY = max(maxY, bounds.maxY)
                 }
             }

             // Check if we have a valid rectangle
             if minX < CGFloat.greatestFiniteMagnitude && maxX > CGFloat.leastNormalMagnitude {
                 let encompassingBounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

                 // Check for existing annotations in this area to avoid duplicates
                 let existingAnnotations = page.annotations.filter { $0.bounds.intersects(encompassingBounds) && $0.isKind(of: CustomPDFAnnotation.self) }
                 if existingAnnotations.isEmpty {
                     // Create a single annotation for the entire selection
                     let annotation = CustomPDFAnnotation(bounds: encompassingBounds, forType: .highlight, withProperties: nil)
                     annotation.annotationID = UUID().uuidString
                     annotation.color = selectedColor.wrappedValue.withAlphaComponent(0.5)
                     page.addAnnotation(annotation)
                 }
             }
         }


         @objc func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
             let location = gestureRecognizer.location(in: PDFViewWrapper.pdfView)
             pdfViewWrapper.handleTapGesture(location)
             // Optionally, invalidate the selection timer if a tap gesture should cancel the pending selection highlight
             selectionTimer?.invalidate()
             selectionTimer = nil
         }
     }

     static func addAnnotationToCurrentPage(annotation: PDFAnnotation) {
         if let currentPage = pdfView?.currentPage {
             currentPage.addAnnotation(annotation)
             pdfView?.setNeedsDisplay()
         }
     }

     static func getPageIndexForTouchedLocation(_ location: CGPoint) -> Int? {
         guard let pdfView = pdfView else {
             return nil
         }

         let touchedPoint = pdfView.convert(location, to: pdfView.currentPage!)
         if let page = pdfView.page(for: touchedPoint, nearest: true) {
             return pdfView.document?.index(for: page)
         }

         return nil
     }
 }
 */












/*

import SwiftUI
import PDFKit

struct PDFViewWrapper: UIViewRepresentable {
    let url: URL
    let handleTapGesture: (CGPoint) -> Void
    static var pdfView: PDFView?
    @Binding var isHighlighting: Bool
    @Binding var selectedOnDocumentAnnotation: CustomPDFAnnotation?
    // Add a binding for the selected color
    @Binding var selectedColor: UIColor

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = PDFDocument(url: url)
        pdfView.autoScales = true

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionChanged(_:)),
            name: Notification.Name.PDFViewSelectionChanged,
            object: pdfView
        )

        let gestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
        pdfView.addGestureRecognizer(gestureRecognizer)

        PDFViewWrapper.pdfView = pdfView
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = PDFDocument(url: url)
        PDFViewWrapper.pdfView = uiView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self, documentURL: url, isHighlighting: $isHighlighting, selectedColor: $selectedColor) // Pass the current value of selectedColor
    }


    class Coordinator: NSObject {
        let pdfViewWrapper: PDFViewWrapper
        let documentURL: URL
        var isHighlighting: Binding<Bool>
        var selectedColor: Binding<UIColor> // Changed from Binding<UIColor> to UIColor

        init(_ pdfViewWrapper: PDFViewWrapper, documentURL: URL, isHighlighting: Binding<Bool>, selectedColor: Binding<UIColor>) { // Adjusted to accept UIColor directly
            self.pdfViewWrapper = pdfViewWrapper
            self.documentURL = documentURL
            self.isHighlighting = isHighlighting
            self.selectedColor = selectedColor
        }

        @objc func selectionChanged(_ notification: Notification) {
            guard isHighlighting.wrappedValue,
                  let pdfView = notification.object as? PDFView,
                  let currentSelection = pdfView.currentSelection else { return }

            createHighlightAnnotations(for: currentSelection, in: pdfView)
        }

        func createHighlightAnnotations(for selection: PDFSelection, in pdfView: PDFView) {
            let selections = selection.selectionsByLine()
            for selection in selections {
                guard let page = selection.pages.first,
                      let pageIndex = pdfView.document?.index(for: page) else { continue }

                let existingAnnotations = page.annotations.filter { $0.bounds.origin == selection.bounds(for: page).origin }

                if existingAnnotations.isEmpty {
                    let annotation = CustomPDFAnnotation(bounds: selection.bounds(for: page), forType: .highlight, withProperties: nil)
                    annotation.annotationID = UUID().uuidString
                    // Use the selected color for the annotation
                    annotation.color = pdfViewWrapper.selectedColor.withAlphaComponent(0.5)
                    page.addAnnotation(annotation)
                    saveHighlightAnnotation(annotation, documentURL: documentURL, pageIndex: pageIndex)
                }
            }
        }


        @objc func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
            let location = gestureRecognizer.location(in: PDFViewWrapper.pdfView)
            pdfViewWrapper.handleTapGesture(location)
        }


    }

    static func addAnnotationToCurrentPage(annotation: PDFAnnotation) {
        if let currentPage = pdfView?.currentPage {
            currentPage.addAnnotation(annotation)
            pdfView?.setNeedsDisplay()
        }
    }

    static func getPageIndexForTouchedLocation(_ location: CGPoint) -> Int? {
        guard let pdfView = pdfView else {
            return nil
        }

        let touchedPoint = pdfView.convert(location, to: pdfView.currentPage!)
        if let page = pdfView.page(for: touchedPoint, nearest: true) {
            return pdfView.document?.index(for: page)
        }

        return nil
    }
}

*/










/*
 
 import SwiftUI
 import PDFKit

 struct PDFViewWrapper: UIViewRepresentable {
     let url: URL
     let handleTapGesture: (CGPoint) -> Void
     static var pdfView: PDFView?
     @Binding var isHighlighting: Bool
     @Binding var selectedOnDocumentAnnotation: CustomPDFAnnotation?

     func makeUIView(context: Context) -> PDFView {
         let pdfView = PDFView()
         pdfView.document = PDFDocument(url: url)
         pdfView.autoScales = true

         NotificationCenter.default.addObserver(
             context.coordinator,
             selector: #selector(Coordinator.selectionChanged(_:)),
             name: Notification.Name.PDFViewSelectionChanged,
             object: pdfView
         )

         let gestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
         pdfView.addGestureRecognizer(gestureRecognizer)

         PDFViewWrapper.pdfView = pdfView
         return pdfView
     }

     func updateUIView(_ uiView: PDFView, context: Context) {
         uiView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = uiView
     }

     func makeCoordinator() -> Coordinator {
         Coordinator(self, documentURL: url, isHighlighting: $isHighlighting)
     }

     class Coordinator: NSObject {
         let pdfViewWrapper: PDFViewWrapper
         let documentURL: URL
         var isHighlighting: Binding<Bool>

         init(_ pdfViewWrapper: PDFViewWrapper, documentURL: URL, isHighlighting: Binding<Bool>) {
             self.pdfViewWrapper = pdfViewWrapper
             self.documentURL = documentURL
             self.isHighlighting = isHighlighting
         }

         @objc func selectionChanged(_ notification: Notification) {
             guard isHighlighting.wrappedValue,
                   let pdfView = notification.object as? PDFView,
                   let currentSelection = pdfView.currentSelection else { return }

             createHighlightAnnotations(for: currentSelection, in: pdfView)
         }

         func createHighlightAnnotations(for selection: PDFSelection, in pdfView: PDFView) {
             let selections = selection.selectionsByLine()
             for selection in selections {
                 guard let page = selection.pages.first,
                       let pageIndex = pdfView.document?.index(for: page) else { continue }

                 let existingAnnotations = page.annotations.filter { $0.bounds.origin == selection.bounds(for: page).origin }

                 if existingAnnotations.isEmpty {
                     let annotation = CustomPDFAnnotation(bounds: selection.bounds(for: page), forType: .highlight, withProperties: nil)
                     annotation.annotationID = UUID().uuidString
                     annotation.color = UIColor.yellow.withAlphaComponent(0.5)
                     page.addAnnotation(annotation)
                     saveHighlightAnnotation(annotation, documentURL: documentURL, pageIndex: pageIndex)
                 }
             }
         }

         @objc func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
             let location = gestureRecognizer.location(in: PDFViewWrapper.pdfView)
             pdfViewWrapper.handleTapGesture(location)
         }


     }

     static func addAnnotationToCurrentPage(annotation: PDFAnnotation) {
         if let currentPage = pdfView?.currentPage {
             currentPage.addAnnotation(annotation)
             pdfView?.setNeedsDisplay()
         }
     }

     static func getPageIndexForTouchedLocation(_ location: CGPoint) -> Int? {
         guard let pdfView = pdfView else {
             return nil
         }

         let touchedPoint = pdfView.convert(location, to: pdfView.currentPage!)
         if let page = pdfView.page(for: touchedPoint, nearest: true) {
             return pdfView.document?.index(for: page)
         }

         return nil
     }
 }
 
 */










/*
 import SwiftUI
 import PDFKit
 import AVFoundation

 struct PDFViewWrapper: UIViewRepresentable {
     let url: URL
     let handleTapGesture: (CGPoint) -> Void
     static var pdfView: PDFView?
     @Binding var isHighlighting: Bool  // Binding variable to control highlighting
     @Binding var selectedOnDocumentAnnotation: CustomPDFAnnotation?

     func makeUIView(context: Context) -> PDFView {
         let pdfView = PDFView()
         pdfView.document = PDFDocument(url: url)
         pdfView.autoScales = true

         NotificationCenter.default.addObserver(
             context.coordinator,
             selector: #selector(Coordinator.selectionChanged(_:)),
             name: Notification.Name.PDFViewSelectionChanged,
             object: pdfView
         )

         let gestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
         pdfView.addGestureRecognizer(gestureRecognizer)

         PDFViewWrapper.pdfView = pdfView
         return pdfView
     }

     func updateUIView(_ uiView: PDFView, context: Context) {
         uiView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = uiView
     }

     func makeCoordinator() -> Coordinator {
         Coordinator(self, documentURL: url, isHighlighting: $isHighlighting)
     }

     class Coordinator: NSObject {
         let pdfViewWrapper: PDFViewWrapper
         let documentURL: URL // Add this line
         var isHighlighting: Binding<Bool>  // Binding variable to control highlighting

         init(_ pdfViewWrapper: PDFViewWrapper, documentURL: URL, isHighlighting: Binding<Bool>) {
             self.pdfViewWrapper = pdfViewWrapper
             self.documentURL = documentURL // And this line
             self.isHighlighting = isHighlighting

         }
         
         @objc func selectionChanged(_ notification: Notification) {
             guard isHighlighting.wrappedValue,
                   let pdfView = notification.object as? PDFView,
                   let currentSelection = pdfView.currentSelection else { return }

             let selections = currentSelection.selectionsByLine()
             for selection in selections {
                 guard let page = selection.pages.first,
                       let pageIndex = pdfView.document?.index(for: page) else { continue }

                 // Check for existing annotations at the same location
                 let existingAnnotations = page.annotations.filter { $0.bounds.origin == selection.bounds(for: page).origin }

                 if let existingAnnotation = existingAnnotations.first {
                     // Update existing annotation's size
                     existingAnnotation.bounds.size = selection.bounds(for: page).size
                     page.addAnnotation(existingAnnotation)
                     
                     

                 }
                 else {
                     // Example modification for creating a highlight annotation with a unique identifier
                     for selection in selections {
                         let annotation = CustomPDFAnnotation(bounds: selection.bounds(for: page), forType: .highlight, withProperties: nil)
                         annotation.annotationID = UUID().uuidString  // Assign a unique identifier
                         annotation.color = UIColor.yellow.withAlphaComponent(0.5)
                         page.addAnnotation(annotation)
                         saveHighlightAnnotation(annotation, documentURL: documentURL, pageIndex: pageIndex)
                     }

                 }
             }
         }

         @objc func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
             
             let location = gestureRecognizer.location(in: PDFViewWrapper.pdfView)
             pdfViewWrapper.handleTapGesture(location)
         }
     }

     static func addAnnotationToCurrentPage(annotation: PDFAnnotation) {
         if let currentPage = pdfView?.currentPage {
             currentPage.addAnnotation(annotation)
             pdfView?.setNeedsDisplay()
         }
     }
     

     static func getPageIndexForTouchedLocation(_ location: CGPoint) -> Int? {
         guard let pdfView = pdfView else {
             return nil
         }

         let touchedPoint = pdfView.convert(location, to: pdfView.currentPage!)

         if let page = pdfView.page(for: touchedPoint, nearest: true) {
             return pdfView.document?.index(for: page)
         }

         return nil
     }
 }

 */




















/*
 import SwiftUI
 import PDFKit
 import AVFoundation

 struct PDFViewWrapper: UIViewRepresentable {
     let url: URL
     let handleTapGesture: (CGPoint) -> Void
     static var pdfView: PDFView?
     @Binding var isHighlighting: Bool  // Binding variable to control highlighting

     func makeUIView(context: Context) -> PDFView {
         let pdfView = PDFView()
         pdfView.document = PDFDocument(url: url)
         pdfView.autoScales = true

         NotificationCenter.default.addObserver(
             context.coordinator,
             selector: #selector(Coordinator.selectionChanged(_:)),
             name: Notification.Name.PDFViewSelectionChanged,
             object: pdfView
         )

         let gestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
         pdfView.addGestureRecognizer(gestureRecognizer)

         PDFViewWrapper.pdfView = pdfView
         return pdfView
     }

     func updateUIView(_ uiView: PDFView, context: Context) {
         uiView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = uiView
     }

     func makeCoordinator() -> Coordinator {
         Coordinator(self, documentURL: url, isHighlighting: $isHighlighting)
     }

     class Coordinator: NSObject {
         let pdfViewWrapper: PDFViewWrapper
         let documentURL: URL // Add this line
         var isHighlighting: Binding<Bool>  // Binding variable to control highlighting

         init(_ pdfViewWrapper: PDFViewWrapper, documentURL: URL, isHighlighting: Binding<Bool>) {
             self.pdfViewWrapper = pdfViewWrapper
             self.documentURL = documentURL // And this line
             self.isHighlighting = isHighlighting

         }
         
         @objc func selectionChanged(_ notification: Notification) {
             guard isHighlighting.wrappedValue, // Check if highlighting is enabled
                   let pdfView = notification.object as? PDFView,
                   let currentSelection = pdfView.currentSelection else { return }

             let selections = currentSelection.selectionsByLine()
             for selection in selections {
                 guard let page = selection.pages.first,
                       let pageIndex = pdfView.document?.index(for: page) else { continue }

                 let annotation = CustomPDFAnnotation(bounds: selection.bounds(for: page), forType: .highlight, withProperties: nil)
                 annotation.color = UIColor.yellow.withAlphaComponent(0.5)
                 page.addAnnotation(annotation)

                 // Assuming you have the document URL available here as documentURL
                 saveHighlightAnnotation(annotation, documentURL: documentURL, pageIndex: pageIndex)
             }
         }

         @objc func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
             let location = gestureRecognizer.location(in: PDFViewWrapper.pdfView)
             pdfViewWrapper.handleTapGesture(location)
         }
     }

     static func addAnnotationToCurrentPage(annotation: PDFAnnotation) {
         if let currentPage = pdfView?.currentPage {
             currentPage.addAnnotation(annotation)
             pdfView?.setNeedsDisplay()
         }
     }

     static func getPageIndexForTouchedLocation(_ location: CGPoint) -> Int? {
         guard let pdfView = pdfView else {
             return nil
         }

         let touchedPoint = pdfView.convert(location, to: pdfView.currentPage!)

         if let page = pdfView.page(for: touchedPoint, nearest: true) {
             return pdfView.document?.index(for: page)
         }

         return nil
     }
 }
 */




/*
 import SwiftUI
 import PDFKit
 import AVFoundation

 struct PDFViewWrapper: UIViewRepresentable {
     let url: URL
     let handleTapGesture: (CGPoint) -> Void
     static var pdfView: PDFView?

     func makeUIView(context: Context) -> PDFView {
         let pdfView = PDFView()
         pdfView.document = PDFDocument(url: url)
         pdfView.autoScales = true

         NotificationCenter.default.addObserver(
             context.coordinator,
             selector: #selector(Coordinator.selectionChanged(_:)),
             name: Notification.Name.PDFViewSelectionChanged,
             object: pdfView
         )

         let gestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
         pdfView.addGestureRecognizer(gestureRecognizer)

         PDFViewWrapper.pdfView = pdfView
         return pdfView
     }

     func updateUIView(_ uiView: PDFView, context: Context) {
         uiView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = uiView
     }

     func makeCoordinator() -> Coordinator {
         Coordinator(self)
     }

     class Coordinator: NSObject {
         let pdfViewWrapper: PDFViewWrapper

         init(_ pdfViewWrapper: PDFViewWrapper) {
             self.pdfViewWrapper = pdfViewWrapper
         }

         @objc func selectionChanged(_ notification: Notification) {
             guard let pdfView = notification.object as? PDFView, let currentSelection = pdfView.currentSelection else { return }

             let selections = currentSelection.selectionsByLine()
             for selection in selections {
                 guard let page = selection.pages.first else { continue }

                 let annotation = PDFAnnotation(bounds: selection.bounds(for: page), forType: .highlight, withProperties: nil)
                 annotation.color = UIColor.yellow.withAlphaComponent(0.5)
                 page.addAnnotation(annotation)
             }
         }

         @objc func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
             let location = gestureRecognizer.location(in: PDFViewWrapper.pdfView)
             pdfViewWrapper.handleTapGesture(location)
         }
     }

     static func addAnnotationToCurrentPage(annotation: PDFAnnotation) {
         if let currentPage = pdfView?.currentPage {
             currentPage.addAnnotation(annotation)
             pdfView?.setNeedsDisplay()
         }
     }

     static func getPageIndexForTouchedLocation(_ location: CGPoint) -> Int? {
         guard let pdfView = pdfView else {
             return nil
         }

         let touchedPoint = pdfView.convert(location, to: pdfView.currentPage!)

         if let page = pdfView.page(for: touchedPoint, nearest: true) {
             return pdfView.document?.index(for: page)
         }

         return nil
     }
 }

 */






/*
 import SwiftUI
 import PDFKit
 import AVFoundation

 struct PDFViewWrapper: UIViewRepresentable {
     let url: URL
     let handleTapGesture: (CGPoint) -> Void
     static var pdfView: PDFView?
     
   //  let speechSynthesizer = AVSpeechSynthesizer() // Create an instance of AVSpeechSynthesizer
     
     func makeUIView(context: Context) -> PDFView {
         let pdfView = PDFView()
         pdfView.autoScales = true // Enable auto scaling to best fit the screen
         pdfView.displayMode = .singlePageContinuous // Show one page at a time with continuous scrolling
         pdfView.displayDirection = .vertical // Enable vertical scrolling
         pdfView.usePageViewController(true, withViewOptions: nil) // Enable scrolling using page view controller
         pdfView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = pdfView
         
         let gestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
         pdfView.addGestureRecognizer(gestureRecognizer)
         
         
         
         return pdfView
     }

     
     func updateUIView(_ uiView: PDFView, context: Context) {
         uiView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = uiView
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
     
     
     static func addAnnotationToCurrentPage(annotation: PDFAnnotation) {
         if let currentPage = pdfView?.currentPage {
             currentPage.addAnnotation(annotation)
             pdfView?.setNeedsDisplay()
         }
     }
     
     // Function to get the page index of PDFPage based on the touched location
     static func getPageIndexForTouchedLocation(_ location: CGPoint) -> Int? {
         guard let pdfView = pdfView else {
             return nil
         }
         
         let touchedPoint = pdfView.convert(location, to: pdfView.currentPage!)
         
         if let page = pdfView.page(for: touchedPoint, nearest: true) {
             return pdfView.document?.index(for: page)
         }
         
         return nil
     }
 }

 */











/*
 import SwiftUI
 import PDFKit


 struct PDFViewWrapper: UIViewRepresentable {
     let url: URL
     let handleTapGesture: (CGPoint) -> Void
     static var pdfView: PDFView?
     
     func makeUIView(context: Context) -> PDFView {
         let pdfView = PDFView()
         pdfView.autoScales = true // Enable auto scaling to best fit the screen
         pdfView.displayMode = .singlePageContinuous // Show one page at a time with continuous scrolling
         pdfView.displayDirection = .vertical // Enable vertical scrolling
         pdfView.usePageViewController(true, withViewOptions: nil) // Enable scrolling using page view controller
         pdfView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = pdfView
         
         let gestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
         pdfView.addGestureRecognizer(gestureRecognizer)
         
         return pdfView
     }
     
     func updateUIView(_ uiView: PDFView, context: Context) {
         uiView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = uiView
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
     
     static func addAnnotationToCurrentPage(annotation: PDFAnnotation) {
         if let currentPage = pdfView?.currentPage {
             currentPage.addAnnotation(annotation)
             pdfView?.setNeedsDisplay()
         }
     }
     
     // Function to get the page index of PDFPage based on the touched location
     static func getPageIndexForTouchedLocation(_ location: CGPoint) -> Int? {
         guard let pdfView = pdfView else {
             return nil
         }
         
         let touchedPoint = pdfView.convert(location, to: pdfView.currentPage!)
         
         if let page = pdfView.page(for: touchedPoint, nearest: true) {
             return pdfView.document?.index(for: page)
         }
         
         return nil
     }

     
 }
 

 */






/*
 import SwiftUI
 import PDFKit
 import AVFoundation

 struct PDFViewWrapper: UIViewRepresentable {
     let url: URL
     let handleTapGesture: (CGPoint) -> Void
     @State var speechSynthesizer = AVSpeechSynthesizer() // Create an instance of AVSpeechSynthesizer
     static var pdfView: PDFView?
     
     
     func makeUIView(context: Context) -> PDFView {
         let pdfView = PDFView()
         pdfView.autoScales = true // Enable auto scaling to best fit the screen
         pdfView.displayMode = .singlePageContinuous // Show one page at a time with continuous scrolling
         pdfView.displayDirection = .vertical // Enable vertical scrolling
         pdfView.usePageViewController(true, withViewOptions: nil) // Enable scrolling using page view controller
         pdfView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = pdfView
         
         let gestureRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
         pdfView.addGestureRecognizer(gestureRecognizer)
         
         let longPressGestureRecognizer = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPressGesture(_:)))
         pdfView.addGestureRecognizer(longPressGestureRecognizer)
         
         return pdfView
     }
     
     func updateUIView(_ uiView: PDFView, context: Context) {
         uiView.document = PDFDocument(url: url)
         PDFViewWrapper.pdfView = uiView
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
         
         @objc func handleLongPressGesture(_ gestureRecognizer: UILongPressGestureRecognizer) {
             if gestureRecognizer.state == .began {
                 pdfViewWrapper.readCurrentPage()
             }
         }
     }
     
     func readCurrentPage() {
         guard let currentPage = PDFViewWrapper.pdfView?.currentPage,
               let text = currentPage.string else {
             return
         }
         
         let utterance = AVSpeechUtterance(string: text)
         speechSynthesizer.speak(utterance)
     }
     
     static func addAnnotationToCurrentPage(annotation: PDFAnnotation) {
         if let currentPage = pdfView?.currentPage {
             currentPage.addAnnotation(annotation)
             pdfView?.setNeedsDisplay()
         }
     }
     
     static func getPageIndexForTouchedLocation(_ location: CGPoint) -> Int? {
         guard let pdfView = pdfView else {
             return nil
         }
         
         let touchedPoint = pdfView.convert(location, to: pdfView.currentPage!)
         
         if let page = pdfView.page(for: touchedPoint, nearest: true) {
             return pdfView.document?.index(for: page)
         }
         
         return nil
     }
 }
 */
