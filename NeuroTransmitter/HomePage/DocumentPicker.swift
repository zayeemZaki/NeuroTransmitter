//
//  DocumentPicker.swift
//  NeuroTransmitter
//
//  Created by Zayeem Zaki on 7/17/23.
//

import SwiftUI
import FirebaseStorage
import FirebaseFirestore


struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var alert: Bool
    @Binding var documents: [Document]
    var completionHandler: (Document, String?) -> Void
    @Binding var selectedFolder: Folder?

    func makeCoordinator() -> DocumentPickerCoordinator {
        return DocumentPickerCoordinator(parent: self, selectedFolder: $selectedFolder)
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<DocumentPicker>) -> UIDocumentPickerViewController {
        let documentPicker = UIDocumentPickerViewController(documentTypes: ["public.data"], in: .import)
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

                    self.parent.completionHandler(Document(name: documentName, url: fileURL, folderID: self.selectedFolder?.id ?? UUID()), "Document already exists")
                    return
                }
                
                var document = Document(name: documentName, url: fileURL, folderID: self.selectedFolder?.id ?? UUID())

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

                            let documentData: [String: Any] = [
                                "name": document.name,
                                "url": downloadURL.absoluteString,
                                "folderID": document.folderID.uuidString
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






/*
 import SwiftUI
 import FirebaseStorage
 import FirebaseFirestore

 struct DocumentPicker: UIViewControllerRepresentable {
     @Binding var alert: Bool
     @Binding var documents: [Document]
     var completionHandler: (Document, String?) -> Void
     @Binding var selectedFolder: Folder?

     func makeCoordinator() -> DocumentPickerCoordinator {
         return DocumentPickerCoordinator(parent: self, selectedFolder: $selectedFolder)
     }

     func makeUIViewController(context: UIViewControllerRepresentableContext<DocumentPicker>) -> UIDocumentPickerViewController {
         let documentPicker = UIDocumentPickerViewController(documentTypes: ["public.data"], in: .import)
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

                     self.parent.completionHandler(Document(name: documentName, url: fileURL, folderID: self.selectedFolder?.id ?? UUID()), "Document already exists")
                     return
                 }
                 

                 
                 var document = Document(name: documentName, url: fileURL, folderID: self.selectedFolder?.id ?? UUID())

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

                             let documentData: [String: Any] = [
                                 "name": document.name,
                                 "url": downloadURL.absoluteString,
                                 "folderID": document.folderID.uuidString
                             ]

                             documentsCollection.addDocument(data: documentData) { error in
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
 */





/*
 import SwiftUI
 import FirebaseStorage
 import FirebaseFirestore


 struct DocumentPicker: UIViewControllerRepresentable {
     @Binding var alert: Bool
     @Binding var documents: [Document]
     var completionHandler: (Document, String?) -> Void
     @Binding var selectedFolder: Folder?

     func makeCoordinator() -> DocumentPickerCoordinator {
         return DocumentPickerCoordinator(parent: self, selectedFolder: $selectedFolder)
     }

     func makeUIViewController(context: UIViewControllerRepresentableContext<DocumentPicker>) -> UIDocumentPickerViewController {
         let documentPicker = UIDocumentPickerViewController(documentTypes: ["public.data"], in: .import)
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

                 guard snapshot != nil else {
                     print("No snapshot found")
                     return
                 }
                 print(self.parent.selectedFolder)
                 var document = Document(name: documentName, url: fileURL, folderID: self.selectedFolder?.id ?? UUID())

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

                             let documentData: [String: Any] = [
                                 "name": document.name,
                                 "url": downloadURL.absoluteString,
                                 "folderID": document.folderID.uuidString
                             ]

                             documentsCollection.addDocument(data: documentData) { error in
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
 */







/*
 struct DocumentPicker: UIViewControllerRepresentable {
     @Binding var alert: Bool
     @Binding var documents: [Document]
     var completionHandler: (Document, String?) -> Void
     @Binding var selectedFolder: Folder?

     func makeCoordinator() -> DocumentPickerCoordinator {
         return DocumentPickerCoordinator(parent: self)
     }

     func makeUIViewController(context: UIViewControllerRepresentableContext<DocumentPicker>) -> UIDocumentPickerViewController {
         let documentPicker = UIDocumentPickerViewController(documentTypes: ["public.data"], in: .import)
         documentPicker.delegate = context.coordinator
         return documentPicker
     }

     func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: UIViewControllerRepresentableContext<DocumentPicker>) {
         // No update needed
     }

     class DocumentPickerCoordinator: NSObject, UIDocumentPickerDelegate {
         var parent: DocumentPicker

         init(parent: DocumentPicker) {
             self.parent = parent
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

                 guard snapshot != nil else {
                     print("No snapshot found")
                     return
                 }

                 let document = Document(name: documentName, url: fileURL, folderID: self.parent.selectedFolder?.id ?? UUID())

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

                             let documentData: [String: Any] = [
                                 "name": document.name,
                                 "url": downloadURL.absoluteString,
                                 "folderID": document.folderID.uuidString
                             ]

                             documentsCollection.addDocument(data: documentData) { error in
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
 */













/*
 import SwiftUI
 import FirebaseStorage
 import FirebaseFirestore


 struct DocumentPicker: UIViewControllerRepresentable {
     // MARK: - Binding Properties
     
     @Binding var alert: Bool
     @Binding var documents: [Document]
     var completionHandler: (Document, String?) -> Void
     
     // MARK: - Coordinator
     
     func makeCoordinator() -> DocumentPickerCoordinator {
         return DocumentPickerCoordinator(parent: self)
     }
     
     // MARK: - View Controller Creation
     
     func makeUIViewController(context: UIViewControllerRepresentableContext<DocumentPicker>) -> UIDocumentPickerViewController {
         let documentPicker = UIDocumentPickerViewController(documentTypes: ["public.data"], in: .import)
         documentPicker.delegate = context.coordinator
         return documentPicker
     }
     
     // MARK: - View Controller Update
     
     func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: UIViewControllerRepresentableContext<DocumentPicker>) {
         // No update needed
     }
     
     // MARK: - Coordinator Class
     
     class DocumentPickerCoordinator: NSObject, UIDocumentPickerDelegate {
         var parent: DocumentPicker
         
         init(parent: DocumentPicker) {
             self.parent = parent
         }
         
         // MARK: - Document Picker Delegate
         
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
                 
                 guard let snapshot = snapshot else {
                     print("No snapshot found")
                     return
                 }
                 
                 if !snapshot.isEmpty {
                     let errorMessage = "Document with the name '\(documentName)' already exists."
                     self.parent.completionHandler(Document(name: documentName, url: fileURL), errorMessage)
                     return
                 }
                 
                 let document = Document(name: documentName, url: fileURL)
                 
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
                             
                             documentsCollection.addDocument(data: [
                                 "name": document.name,
                                 "url": downloadURL.absoluteString
                             ]) { error in
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

 */
















/*
 import SwiftUI
 import FirebaseStorage
 import FirebaseFirestore

 struct DocumentPicker: UIViewControllerRepresentable {
     // MARK: - Binding Properties
     
     @Binding var alert: Bool
     @Binding var documents: [Document]
     var completionHandler: (Document, String?) -> Void
     
     // MARK: - Coordinator
     
     func makeCoordinator() -> DocumentPickerCoordinator {
         return DocumentPickerCoordinator(parent: self)
     }
     
     // MARK: - View Controller Creation
     
     func makeUIViewController(context: UIViewControllerRepresentableContext<DocumentPicker>) -> UIDocumentPickerViewController {
         let documentPicker = UIDocumentPickerViewController(documentTypes: ["public.data"], in: .import)
         documentPicker.delegate = context.coordinator
         return documentPicker
     }
     
     // MARK: - View Controller Update
     
     func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: UIViewControllerRepresentableContext<DocumentPicker>) {
         // No update needed
     }
     
     // MARK: - Coordinator Class
     
     class DocumentPickerCoordinator: NSObject, UIDocumentPickerDelegate {
         var parent: DocumentPicker
         
         init(parent: DocumentPicker) {
             self.parent = parent
         }
         
         // MARK: - Document Picker Delegate
         
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
                 
                 guard let snapshot = snapshot else {
                     print("No snapshot found")
                     return
                 }
                 
                 if !snapshot.isEmpty {
                     let errorMessage = "Document with the name '\(documentName)' already exists."
                     self.parent.completionHandler(Document(name: documentName, url: fileURL), errorMessage)
                     return
                 }
                 
                 let document = Document(name: documentName, url: fileURL)
                 
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
                             
                             documentsCollection.addDocument(data: [
                                 "name": document.name,
                                 "url": downloadURL.absoluteString
                             ]) { error in
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

 */
