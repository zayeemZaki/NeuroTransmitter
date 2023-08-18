//import AVFoundation
//import PDFKit
//
//func textToSpeech(documentURL: URL) {
//    // Check if the URL is valid and initialize the PDFDocument
//    guard let pdfDocument = PDFDocument(url: documentURL) else {
//        return
//    }
//
//    var fullText = ""
//
//    // Extract text from each page of the PDF
//    for pageIndex in 0..<pdfDocument.pageCount {
//        if let page = pdfDocument.page(at: pageIndex), let pageText = page.string {
//            fullText += pageText + "\n"
//        }
//    }
//
//    // Configure the speech synthesizer with the desired speech parameters
//    let speechSynthesizer = AVSpeechSynthesizer()
//    let utterance = AVSpeechUtterance(string: fullText)
//
//    if let defaultVoice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode()) {
//        // Use the default voice for the current device's region if available
//        utterance.voice = defaultVoice
//    } else {
//        // Fallback to any available voice on the device
//        if let fallbackVoice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode()) {
//            utterance.voice = fallbackVoice
//        } else {
//            // If no voices are available, return without speaking
//            return
//        }
//    }
//
//    utterance.rate = 0.5 // Adjust the speech rate to your preference
//
//    // Speak the text
//    speechSynthesizer.speak(utterance)
//}
