
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
 
