//
//  DocumentPicker.swift
//  NeuroTransmitter
//
//  Created by Zayeem Zaki on 7/17/23.
//

import SwiftUI
import FirebaseStorage
import FirebaseFirestore
import UIKit


struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var alert: Bool
    @Binding var documents: [Document]
    var completionHandler: (Document, String?) -> Void
    @Binding var selectedFolder: Folder?

    func makeCoordinator() -> DocumentPickerCoordinator {
        return DocumentPickerCoordinator(parent: self, selectedFolder: $selectedFolder)
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<DocumentPicker>) -> UIDocumentPickerViewController {
        let documentPicker = UIDocumentPickerViewController(documentTypes: ["com.adobe.pdf"], in: .import)
        documentPicker.delegate = context.coordinator
        return documentPicker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: UIViewControllerRepresentableContext<DocumentPicker>) {
        // No update needed
    }

    class DocumentPickerCoordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPicker
        @Binding var selectedFolder: Folder?

        init(parent: DocumentPicker, selectedFolder: Binding<Folder?>) {
            self.parent = parent
            self._selectedFolder = selectedFolder
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let fileURL = urls.first else {
                return
            }

            let documentName = fileURL.deletingPathExtension().lastPathComponent

            let db = Firestore.firestore()
            let documentsCollection = db.collection("ResearchPapers")
            let query = documentsCollection.whereField("name", isEqualTo: documentName)

            query.getDocuments { (snapshot, error) in
                if let error = error {
                    print("Error querying documents: \(error.localizedDescription)")
                    return
                }

                if let snapshot = snapshot, !snapshot.isEmpty {
                    // Document with the same name already exists
                    self.parent.alert = true
                    let newDocumentID = UUID()
                    self.parent.completionHandler(Document(id: newDocumentID, name: documentName, url: fileURL, folderID: self.selectedFolder?.id ?? UUID()), "Document already exists")
                    return
                }

                let newDocumentID = UUID()
                var document = Document(id: newDocumentID, name: documentName, url: fileURL, folderID: self.selectedFolder?.id ?? UUID())

                // Set the folderID to the selected folder's ID
                if let selectedFolderID = self.selectedFolder?.id {
                    document.folderID = selectedFolderID
                }

                let storageRef = Storage.storage().reference()
                let fileRef = storageRef.child(fileURL.lastPathComponent)

                fileRef.putFile(from: fileURL, metadata: nil) { (_, error) in
                    if let error = error {
                        print("Upload error: \(error.localizedDescription)")
                        self.parent.completionHandler(document, error.localizedDescription)
                        return
                    }

                    fileRef.downloadURL { (url, error) in
                        if let error = error {
                            print("Error retrieving download URL: \(error.localizedDescription)")
                            self.parent.completionHandler(document, error.localizedDescription)
                            return
                        }

                        if let downloadURL = url {
                            print("Upload success. Download URL: \(downloadURL)")

                            // Include the UUID in the document data
                            let documentData: [String: Any] = [
                                "name": document.name,
                                "url": downloadURL.absoluteString,
                                "folderID": document.folderID.uuidString,
                                "uuid": document.id.uuidString // Storing the document's UUID
                            ]

                            documentsCollection.document(document.id.uuidString).setData(documentData) { error in
                                if let error = error {
                                    print("Error saving document: \(error.localizedDescription)")
                                    self.parent.completionHandler(document, error.localizedDescription)
                                } else {
                                    print("Document saved successfully")
                                    self.parent.completionHandler(document, nil)
                                }
                            }
                        }
                    }
                }

                self.parent.alert = true
            }

        }

    }


}
