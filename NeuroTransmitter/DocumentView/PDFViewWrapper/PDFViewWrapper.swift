//
//  PDFViewWrapper.swift
//  NeuroTransmitter
//
//  Created by Zayeem Zaki on 7/5/23.
//
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
