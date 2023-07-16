//
//  AnnotationToolbar.swift
//  NeuroTransmitter
//
//  Created by Zayeem Zaki on 7/5/23.
//

import Foundation
import SwiftUI
import PDFKit

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
    var deleteAction: () -> Void // Modify the deleteAction binding
    @State private var isDropdownOpen = false
    let availableFontSizes: [CGFloat]
    let colorButtonSize: CGFloat = 24 // Size of the color buttons
    @Environment(\.colorScheme) var colorScheme
    @Binding var isHighlighting: Bool
    
    @State private var selectedOnDocumentAnnotation: CustomPDFAnnotation? // Store the selected annotation
    let documentURL: URL
    
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
                    ColorButton(color: .black, isSelected: fontColor == .black, action: { fontColor = .black })
                    ColorButton(color: .yellow, isSelected: fontColor == .yellow, action: { fontColor = .yellow })
                    
                    
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
                Button(action: {
                    deleteAction() // Pass the required arguments
                    
                }) {
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
                    .frame(width: 6, height: 6)
                
                if isSelected {
                    Image(systemName: "circle.fill")
                        .foregroundColor(color)
                }
            }
        }
    }
}
