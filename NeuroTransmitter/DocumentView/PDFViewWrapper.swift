//
//  PDFViewWrapper.swift
//  NeuroTransmitter
//
//  Created by Zayeem Zaki on 7/5/23.
//

import SwiftUI
import PDFKit


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
 */





