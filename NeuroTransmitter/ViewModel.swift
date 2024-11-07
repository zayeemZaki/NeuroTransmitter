import Foundation
import PDFKit
import FirebaseFirestore
import FirebaseStorage

class ViewModel: ObservableObject {
    @Published var pdfDocumentURL: URL?
    private var isProcessingFile = false // Flag to indicate if a file is currently being processed

    func handleIncomingPDF(url: URL) {
        guard !isProcessingFile else {
            print("A file is already being processed.")
            return
        }

        isProcessingFile = true // Set the flag as file processing begins

        processFile(url: url) { processedURL in
            self.uploadToFirebaseStorage(url: processedURL)
        }
    }

    private func processFile(url: URL, completion: @escaping (URL) -> Void) {
        let fileManager = FileManager.default
        let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destinationURL = documentDirectory.appendingPathComponent(url.lastPathComponent)

        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: url, to: destinationURL)

            DispatchQueue.main.async {
                self.pdfDocumentURL = destinationURL
                completion(destinationURL) // Call completion with the processed URL
            }
        }
        catch {
            print("File processing error: \(error)")
            DispatchQueue.main.async {
                self.isProcessingFile = false // Reset flag on error
            }
        }
    }

    private func uploadToFirebaseStorage(url: URL) {
        let storageRef = Storage.storage().reference().child(url.lastPathComponent)

        storageRef.putFile(from: url, metadata: nil) { metadata, error in
            if let error = error {
                print("Upload error: \(error.localizedDescription)")
                self.isProcessingFile = false // Reset flag on error
                return
            }

            storageRef.downloadURL { (downloadURL, error) in
                self.isProcessingFile = false // Reset flag after processing

                if let downloadURL = downloadURL {
                    self.saveInRecentFolder(at: downloadURL, documentUUID: UUID())
                }
                else if let error = error {
                    print("Error retrieving download URL: \(error.localizedDescription)")
                }
            }
        }
    }

    func saveInRecentFolder(at url: URL, documentUUID: UUID) {
        let db = Firestore.firestore()
        let recentFolderName = "Recent"
        let documentName = url.deletingPathExtension().lastPathComponent

        db.collection("Folders").whereField("name", isEqualTo: recentFolderName).getDocuments { (snapshot, error) in
            if let error = error {
                print("Error querying for the Recent folder: \(error.localizedDescription)")
                return
            }

            if let snapshot = snapshot, let documentSnapshot = snapshot.documents.first {
                let recentFolderID = documentSnapshot.documentID
                
                let documentData: [String: Any] = [
                    "name": documentName,
                    "url": url.absoluteString,
                    "folderID": recentFolderID,
                    "uuid": documentUUID.uuidString
                ]

                // Explicitly set the document ID to match the UUID
                db.collection("ResearchPapers").document(documentUUID.uuidString).setData(documentData) { error in
                    if let error = error {
                        print("Error saving document in the Recent folder: \(error.localizedDescription)")
                    }
                    else {
                        print("Document saved in the Recent folder successfully")
                    }
                }
            }
            else {
                print("Error: The Recent folder was expected to exist.")
            }
        }
    }
}
