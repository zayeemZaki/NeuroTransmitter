//
//  CreateHighlightAnnotations.swift
//  NeuroTransmitter
//
//  Created by Zayeem Zaki on 7/16/23.
//

import PDFKit

func createHighlightAnnotation(firstTouchLocation: inout CGPoint?, secondTouchLocation: inout CGPoint?, pdfView: PDFView, documentURL: URL) {
    
    guard let initialFirstTouchLocation = firstTouchLocation,
          let initialSecondTouchLocation = secondTouchLocation,
          let tappedPage = pdfView.page(for: initialFirstTouchLocation, nearest: true)
    else {
        return
    }
    
    var updatedFirstTouchLocation = initialFirstTouchLocation
    var updatedSecondTouchLocation = initialSecondTouchLocation
    
    let convertedFirstLocation = pdfView.convert(updatedFirstTouchLocation, to: tappedPage)
    let convertedSecondLocation = pdfView.convert(updatedSecondTouchLocation, to: tappedPage)
    
    let width: CGFloat
    
    width = abs(convertedSecondLocation.x - convertedFirstLocation.x)
    
    let minY = min(convertedFirstLocation.y, convertedSecondLocation.y)
    let highlightBounds = CGRect(x: convertedFirstLocation.x, y: minY, width: width, height: 10)
    
    let highlightAnnotation = CustomPDFAnnotation(bounds: highlightBounds, forType: .highlight, withProperties: nil)
    tappedPage.addAnnotation(highlightAnnotation)
    
    firstTouchLocation = nil
    secondTouchLocation = nil
    
    let annotationID = UUID().uuidString
    highlightAnnotation.annotationID = annotationID
    
    // Save the highlight annotation to Firestore
    saveHighlightAnnotation(highlightAnnotation, documentURL: documentURL, location: initialFirstTouchLocation)
    //  fetchHighlightAnnotations(documentURL: documentURL)  //check if needed
}
