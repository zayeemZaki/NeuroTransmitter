//
//  AnnotationToolbar.swift
//  NeuroTransmitter
//
//  Created by Zayeem Zaki on 7/5/23.
//

import Foundation
import SwiftUI
import PDFKit
import AVFoundation



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
    
    @State private var isPaused: Bool = false
    @State private var isPlaying: Bool = false
    @State private var isReading: Bool = false
    let speechSynthesizer = AVSpeechSynthesizer() // Create an instance of AVSpeechSynthesizer


    
    var body: some View {
        
        ZStack {
            if !isTyping && !isAddingComment && !showDeleteButton && !isHighlighting && !isReading{
                HStack {
                    Button(action: {
                        readCurrentPage()
                        isReading.toggle()
                        isPlaying.toggle()
                    }) {
                        Image(systemName: "speaker")
                    }
                    .foregroundColor(.primary)
                    
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
            else if isReading {
                HStack {
                    Button(action: {
                        isReading = false
                        isPlaying = false
                        isPaused = false
                        speechSynthesizer.stopSpeaking(at: .immediate) // Stop the speech synthesis
                    }) {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                    .foregroundColor(.blue)
                    
                    Button(action: {
                     //   speechSynthesizer.stopSpeaking(at: .immediate) // Stop the speech synthesis
                    }) {
                        Image(systemName: "gobackward.10")
                    }
                    .foregroundColor(.blue)
                    
                    if isPlaying && !isPaused {
                        Button(action: {
                            isPaused.toggle()
                            isPlaying.toggle()
                            speechSynthesizer.pauseSpeaking(at: .immediate) // Pause the speech synthesis
                        }) {
                            Image(systemName: "pause")
                        }
                        .foregroundColor(isPaused ? .blue : .black)
                    }
                    if isPaused && !isPlaying {
                        Button(action: {
                            isPlaying.toggle()
                            isPaused.toggle()
                            speechSynthesizer.continueSpeaking() // Continue the speech synthesis from where it was paused
                        }) {
                            Image(systemName: "play")
                        }
                        .foregroundColor(isPlaying ? .blue : .black)
                    }
                    Button(action: {
                        fastForwardAndPlay() // Stop the speech synthesis
                    }) {
                        Image(systemName: "goforward.10")
                    }
                    .foregroundColor(.blue)
                }
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
    
    @Binding var lastSynthesisPosition: Int // Binding to hold the last synthesis position

    func fastForwardAndPlay() {
        if let currentPage = PDFViewWrapper.pdfView?.currentPage,
           let text = currentPage.string {
            
            // Calculate the target position to skip ahead (e.g., 10 words)
            let skipWords: Int = 10
            
            // Split the text into an array of words
            let words = text.components(separatedBy: .whitespacesAndNewlines)
            
            // Calculate the new position in the text
            let newPosition = min(lastSynthesisPosition + skipWords, words.count)
            
            // Create a new utterance starting from the new position
            let utteranceText = words[newPosition..<words.count].joined(separator: " ")
            let utterance = AVSpeechUtterance(string: utteranceText)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US") // Set the appropriate voice if needed
            
            // Stop the current speech synthesis
            speechSynthesizer.stopSpeaking(at: .immediate)
            
            // Speak the new utterance to start playing from the skipped position
            speechSynthesizer.speak(utterance)
            
            // Update the lastSynthesisPosition
            self.lastSynthesisPosition = newPosition

            // Update the states to indicate that speech synthesis is now playing
            isPlaying = true
            isPaused = false
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





/*
 import Foundation
 import SwiftUI
 import PDFKit
 import AVFoundation



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
     
     @State private var isPaused: Bool = false
     @State private var isPlaying: Bool = false
     @State private var isReading: Bool = false
     let speechSynthesizer = AVSpeechSynthesizer() // Create an instance of AVSpeechSynthesizer


     
     var body: some View {
         
         ZStack {
             if !isTyping && !isAddingComment && !showDeleteButton && !isHighlighting && !isReading{
                 HStack {
                     Button(action: {
                         readCurrentPage()
                         isReading.toggle()
                         isPlaying.toggle()
                     }) {
                         Image(systemName: "speaker")
                     }
                     .foregroundColor(.primary)
                     
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
             else if isReading {
                 HStack {
                     Button(action: {
                         isReading = false
                         isPlaying = false
                         isPaused = false
                         speechSynthesizer.stopSpeaking(at: .immediate) // Stop the speech synthesis
                     }) {
                         Image(systemName: "speaker.wave.2.fill")
                     }
                     .foregroundColor(.blue)
                     
                     Button(action: {
                      //   speechSynthesizer.stopSpeaking(at: .immediate) // Stop the speech synthesis
                     }) {
                         Image(systemName: "gobackward.10")
                     }
                     .foregroundColor(.blue)
                     
                     if isPlaying && !isPaused {
                         Button(action: {
                             isPaused.toggle()
                             isPlaying.toggle()
                             speechSynthesizer.pauseSpeaking(at: .immediate) // Pause the speech synthesis
                         }) {
                             Image(systemName: "pause")
                         }
                         .foregroundColor(isPaused ? .blue : .black)
                     }
                     if isPaused && !isPlaying {
                         Button(action: {
                             isPlaying.toggle()
                             isPaused.toggle()
                             speechSynthesizer.continueSpeaking() // Continue the speech synthesis from where it was paused
                         }) {
                             Image(systemName: "play")
                         }
                         .foregroundColor(isPlaying ? .blue : .black)
                     }
                     Button(action: {
                         fastForwardAndPlay() // Stop the speech synthesis
                     }) {
                         Image(systemName: "goforward.10")
                     }
                     .foregroundColor(.blue)
                 }
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
     
     @Binding var lastSynthesisPosition: Int // Binding to hold the last synthesis position

     func fastForwardAndPlay() {
         if let currentPage = PDFViewWrapper.pdfView?.currentPage,
            let text = currentPage.string {
             
             // Calculate the target position to skip ahead (e.g., 10 words)
             let skipWords: Int = 10
             
             // Split the text into an array of words
             let words = text.components(separatedBy: .whitespacesAndNewlines)
             
             // Calculate the new position in the text
             let newPosition = min(lastSynthesisPosition + skipWords, words.count)
             
             // Create a new utterance starting from the new position
             let utteranceText = words[newPosition..<words.count].joined(separator: " ")
             let utterance = AVSpeechUtterance(string: utteranceText)
             utterance.voice = AVSpeechSynthesisVoice(language: "en-US") // Set the appropriate voice if needed
             
             // Stop the current speech synthesis
             speechSynthesizer.stopSpeaking(at: .immediate)
             
             // Speak the new utterance to start playing from the skipped position
             speechSynthesizer.speak(utterance)
             
             // Update the lastSynthesisPosition
             self.lastSynthesisPosition = newPosition

             // Update the states to indicate that speech synthesis is now playing
             isPlaying = true
             isPaused = false
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
 */







/*
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

 */
