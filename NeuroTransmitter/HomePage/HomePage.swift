import SwiftUI
import MobileCoreServices
import FirebaseStorage
import UniformTypeIdentifiers
import FirebaseFirestore

struct Document: Identifiable {
   let id: UUID
   let name: String
   let url: URL
   var folderID: UUID

   init(id: UUID, name: String, url: URL, folderID: UUID) {
       self.id = id
       self.name = name
       self.url = url
       self.folderID = folderID
   }
}

struct ChatThread: Identifiable {
    let id = UUID()
    var document: Document
    var chatMessages: [ChatMessage]
}



struct HomePage: View {
    
    @State private var alert = false
    @State private var chatThreads: [ChatThread] = []
    @State private var documents: [Document] = []
    @State private var errorMessage = ""
    @State private var isLoading = true // New state to manage loading state
    @State private var showDocumentPicker = false
    @State private var searchText = ""
    @State var didFetch = false
    @Binding var selectedFolder: Folder?
    @State private var showMoveDocumentView = false
    @State private var selectedDocument: Document?
    @State private var selectedMoveFolder: Folder?
    @Binding var folders: [Folder]
    @State private var selectedThread: ChatThread?
    @State private var longPressedDocument: Document?
    @State private var isLongPressActive = false // New state for long-press
    @State private var showDeleteConfirmationAlert = false
    @State private var selectedFolderIndex: Int = 0 // Initialize with default selected index
    @State private var isLoadingDocument = false
    @State private var showSuccessMessage = false  // State to manage success message
    var onDocumentMove: (() -> Void)?

    var filteredChatThreads: [ChatThread] {
        searchText.isEmpty ? chatThreads : chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack {
            
            if let folderName = selectedFolder?.name {
                Text(folderName)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top)
            }

            SearchBar(text: $searchText)  // Custom SearchBar component

            List(filteredChatThreads) { thread in
                NavigationLink(destination: DocumentView(documentURL: thread.document.url)) {
                    ChatThreadRow(thread: thread,
                                  onDelete: {
                                      self.selectedDocument = thread.document
                                      self.deleteSelectedDocument()
                                  },
                                  onMove: {
                                      self.selectedDocument = thread.document
                                      self.showMoveDocumentView = true
                                  })
                }
            }
            .listStyle(PlainListStyle())
        }
        .padding(.horizontal)
        .navigationBarTitle("Documents", displayMode: .inline)
        .navigationBarItems(trailing: Button(action: {
            showDocumentPicker.toggle()
        }) {
            Image(systemName: "plus")
                .imageScale(.large)
        })

        .onAppear {
            fetchDocuments()
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker(
               alert: self.$alert,
               documents: self.$documents,
               completionHandler: { document, errorMessage in
                   if let errorMessage = errorMessage {
                       self.errorMessage = errorMessage
                   }
                   else {
                       // Handle successful document upload if needed
                       
                       let newThread = ChatThread(document: document, chatMessages: [])
                       self.chatThreads.append(newThread)
                       self.chatThreads.sort { $0.document.name.localizedCaseInsensitiveCompare($1.document.name) == .orderedAscending }
                   }
               }, selectedFolder: self.$selectedFolder
           )
       }
       .alert(isPresented: $alert) {
           if !errorMessage.isEmpty {
               return Alert(
                   title: Text("Error"),
                   message: Text(errorMessage),
                   dismissButton: .default(Text("Ok")) {
                       errorMessage = ""
                   }
               )
           }
           else {
               return Alert(
               title: Text("Message"),
               message: Text("Uploaded Successfully"),
               dismissButton: .default(Text("Ok"))
               )
           }
       }
       .sheet(isPresented: $showMoveDocumentView, onDismiss: {
           selectedMoveFolder = nil
       }) {
           if let selectedDocument = selectedDocument {
               MoveDocumentView(
                   showMoveDocumentView: $showMoveDocumentView,
                   document: selectedDocument,
                   availableFolders: folders,
                   selectedFolder: $selectedMoveFolder,
                   moveAction: { folder in
                       moveSelectedDocument(document: selectedDocument, to: folder)
                       showMoveDocumentView = false
                   },
                   selectedFolderIndex: $selectedFolderIndex
               )
           }
       }
    }
    


    func deleteCollection(collectionPath: String, completion: @escaping (Error?) -> Void) {
        let db = Firestore.firestore()
        db.collection(collectionPath).getDocuments { (snapshot, error) in
            guard let documents = snapshot?.documents else {
                print("Error fetching documents: \(error?.localizedDescription ?? "Unknown error")")
                completion(error)
                return
            }
            
            let dispatchGroup = DispatchGroup()
            
            for document in documents {
                dispatchGroup.enter()
                db.collection(collectionPath).document(document.documentID).delete { error in
                    if let error = error {
                        print("Error deleting document: \(error.localizedDescription)")
                    }
                    dispatchGroup.leave()
                }
            }
            
            dispatchGroup.notify(queue: .main) {
                completion(nil)
            }
        }
    }
    func deleteAllRelatedDataForDocument(documentURL: URL, completion: @escaping () -> Void) {
        let documentID = documentURL.lastPathComponent
        let annotationPaths = [
            "onDocumentComments/\(documentID)/annotations",
            "highlightAnnotations/\(documentID)/annotations",
            "commentAnnotations/\(documentID)/annotations",
            "popUpAnnotations/\(documentID)/annotations"

        ]
        
        let chatMessagesPath = "messages/\(documentID)/chats"
        
        let dispatchGroup = DispatchGroup()
        
        for path in annotationPaths {
            dispatchGroup.enter()
            deleteCollection(collectionPath: path) { error in
                if let error = error {
                    print("Failed to delete annotations from \(path): \(error.localizedDescription)")
                }
                dispatchGroup.leave()
            }
        }
        
        // Delete chat messages
        dispatchGroup.enter()
        deleteCollection(collectionPath: chatMessagesPath) { error in
            if let error = error {
                print("Failed to delete chat messages: \(error.localizedDescription)")
            }
            dispatchGroup.leave()
        }
        
        // Notify when all deletions are complete
        dispatchGroup.notify(queue: .main) {
            completion()
        }
    }
    func deleteSelectedDocument() {
        guard let document = selectedDocument else {
            print("No document selected for deletion.")
            return
        }

        // Start by deleting all related data (annotations, chat messages)
        deleteAllRelatedDataForDocument(documentURL: document.url) {
            // Once all related data is deleted, proceed to delete the document itself
            // Your existing document deletion code goes here
            guard let document = selectedDocument else {
                print("No document selected for deletion.")
                return
            }

            let db = Firestore.firestore()
            let storageRef = Storage.storage().reference()

            // Delete from Firestore
            db.collection("ResearchPapers").document(document.id.uuidString).delete { error in
                if let error = error {
                    print("Error deleting document from Firestore: \(error)")
                    return
                }
                print("Document successfully deleted from Firestore.")

                // Delete from Firebase Storage
                let fileRef = storageRef.child(document.url.lastPathComponent)
                fileRef.delete { error in
                    if let error = error {
                        print("Error deleting document from Firebase Storage: \(error)")
                    } else {
                        // Document successfully deleted from Firestore and Firebase Storage
                        // Remove it from the chatThreads array
                        DispatchQueue.main.async {
                            self.chatThreads.removeAll { $0.document.id == document.id }
                        }
                    }
                }
            }
        }
    }


    func fetchDocuments() {
        if !didFetch {
            let db = Firestore.firestore()
            db.collection("ResearchPapers").getDocuments { (querySnapshot, error) in
                if let error = error {
                    print("Error getting documents: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = querySnapshot?.documents else {
                    print("No documents found")
                    return
                }
                
                let fetchedDocuments = documents.compactMap { documentSnapshot -> Document? in
                    let data = documentSnapshot.data()
                    guard let name = data["name"] as? String,
                          let urlString = data["url"] as? String,
                          let url = URL(string: urlString),
                          let folderIDString = data["folderID"] as? String,
                          let folderID = UUID(uuidString: folderIDString),
                          let uuidString = data["uuid"] as? String,
                          let uuid = UUID(uuidString: uuidString)
                    else {
                        return nil
                    }
                    return Document(id: uuid, name: name, url: url, folderID: folderID)
                }
                
                self.updateChatThreads(with: fetchedDocuments)
            }
            didFetch = true
        }
    }

    func updateChatThreads(with documents: [Document]) {
        var updatedThreads: [ChatThread] = chatThreads

        for document in documents {
            if document.folderID == selectedFolder?.id {
                if let existingThreadIndex = updatedThreads.firstIndex(where: { $0.document.id == document.id }) {
                    // Update the existing thread
                    updatedThreads[existingThreadIndex].document = document
                }
                else {
                    // Create a new thread only if it doesn't already exist
                    let newThread = ChatThread(document: document, chatMessages: [])
                    updatedThreads.append(newThread)
                }
            }
        }

        // Sort the updatedThreads array based on the name of the documents
        updatedThreads.sort { $0.document.name.localizedCaseInsensitiveCompare($1.document.name) == .orderedAscending }

        chatThreads = updatedThreads
    }
 
    func moveSelectedDocument(document: Document, to folder: Folder) {
        let db = Firestore.firestore()

        db.collection("ResearchPapers").document(document.id.uuidString).updateData([
            "folderID": folder.id.uuidString
        ]) { error in
            if let error = error {
                print("Error updating folderID in Firestore: \(error)")
            } 
            else {
                if let threadIndex = self.chatThreads.firstIndex(where: { $0.document.id == document.id }) {
                    if self.selectedFolder?.id != folder.id {
                        // Remove the document from chatThreads if it's moved out of the current folder
                        DispatchQueue.main.async {
                            self.chatThreads.remove(at: threadIndex)
                        }
                    } else {
                        // Update folderID if it's moved within the current folder
                        self.chatThreads[threadIndex].document.folderID = folder.id
                    }
                }
            }
        }
    }
}



struct ChatThreadRow: View {
   let thread: ChatThread
   var onDelete: () -> Void
   var onMove: () -> Void

   var body: some View {
       HStack {
           Image(systemName: "doc.text")
               .foregroundColor(.blue)
           VStack(alignment: .leading) {
               Text(thread.document.name)
                   .font(.headline).padding(10)
//               Text("Last message: \(thread.chatMessages.last?.content ?? "No messages")")
//                   .font(.subheadline)
//                   .foregroundColor(.gray)
           }
       }
       .contextMenu {
           Button(action: onDelete) {
               Text("Delete")
               Image(systemName: "trash")
           }
           Button(action: onMove) {
               Text("Move")
               Image(systemName: "folder")
           }
       }
   }
}

// Custom SearchBar component
struct SearchBar: View {
   @Binding var text: String

   var body: some View {
       TextField("Search...", text: $text)
           .padding(7)
           .background(Color(.systemGray6))
           .cornerRadius(10)
           .padding(.horizontal)
   }
}












/*
 import SwiftUI
 import MobileCoreServices
 import FirebaseStorage
 import UniformTypeIdentifiers
 import FirebaseFirestore

 struct Document: Identifiable {
    let id: UUID
    let name: String
    let url: URL
    var folderID: UUID

    init(id: UUID, name: String, url: URL, folderID: UUID) {
        self.id = id
        self.name = name
        self.url = url
        self.folderID = folderID
    }
 }

 struct ChatThread: Identifiable {
     let id = UUID()
     var document: Document
     var chatMessages: [ChatMessage]
 }



 struct HomePage: View {
     
     @State private var alert = false
     @State private var chatThreads: [ChatThread] = []
     @State private var documents: [Document] = []
     @State private var errorMessage = ""
     @State private var isLoading = true // New state to manage loading state
     @State private var showDocumentPicker = false
     @State private var searchText = ""
     @State var didFetch = false
     @Binding var selectedFolder: Folder?
     @State private var showMoveDocumentView = false
     @State private var selectedDocument: Document?
     @State private var selectedMoveFolder: Folder?
     @Binding var folders: [Folder]
     @State private var selectedThread: ChatThread?
     @State private var longPressedDocument: Document?
     @State private var isLongPressActive = false // New state for long-press
     @State private var showDeleteConfirmationAlert = false
     @State private var selectedFolderIndex: Int = 0 // Initialize with default selected index
     @State private var isLoadingDocument = false
     @State private var showSuccessMessage = false  // State to manage success message
     var onDocumentMove: (() -> Void)?

     var filteredChatThreads: [ChatThread] {
         searchText.isEmpty ? chatThreads : chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
     }

     var body: some View {
         VStack {
             
             if let folderName = selectedFolder?.name {
                 Text(folderName)
                     .font(.largeTitle)
                     .fontWeight(.bold)
                     .padding(.top)
             }

             SearchBar(text: $searchText)  // Custom SearchBar component

             List(filteredChatThreads) { thread in
                 NavigationLink(destination: DocumentView(documentURL: thread.document.url)) {
                     ChatThreadRow(thread: thread,
                                   onDelete: {
                                       self.selectedDocument = thread.document
                                       self.deleteSelectedDocument()
                                   },
                                   onMove: {
                                       self.selectedDocument = thread.document
                                       self.showMoveDocumentView = true
                                   })
                 }
             }
             .listStyle(PlainListStyle())
         }
         .padding(.horizontal)
         .navigationBarTitle("Documents", displayMode: .inline)
         .navigationBarItems(trailing: Button(action: {
             showDocumentPicker.toggle()
         }) {
             Image(systemName: "plus")
                 .imageScale(.large)
         })

         .onAppear {
             fetchDocuments()
         }
         .sheet(isPresented: $showDocumentPicker) {
             DocumentPicker(
                alert: self.$alert,
                documents: self.$documents,
                completionHandler: { document, errorMessage in
                    if let errorMessage = errorMessage {
                        self.errorMessage = errorMessage
                    }
                    else {
                        // Handle successful document upload if needed
                        
                        let newThread = ChatThread(document: document, chatMessages: [])
                        self.chatThreads.append(newThread)
                        self.chatThreads.sort { $0.document.name.localizedCaseInsensitiveCompare($1.document.name) == .orderedAscending }
                    }
                }, selectedFolder: self.$selectedFolder
            )
        }
        .alert(isPresented: $alert) {
            if !errorMessage.isEmpty {
                return Alert(
                    title: Text("Error"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("Ok")) {
                        errorMessage = ""
                    }
                )
            }
            else {
                return Alert(
                title: Text("Message"),
                message: Text("Uploaded Successfully"),
                dismissButton: .default(Text("Ok"))
                )
            }
        }
        .sheet(isPresented: $showMoveDocumentView, onDismiss: {
            selectedMoveFolder = nil
        }) {
            if let selectedDocument = selectedDocument {
                MoveDocumentView(
                    showMoveDocumentView: $showMoveDocumentView,
                    document: selectedDocument,
                    availableFolders: folders,
                    selectedFolder: $selectedMoveFolder,
                    moveAction: { folder in
                        moveSelectedDocument(document: selectedDocument, to: folder)
                        showMoveDocumentView = false
                    },
                    selectedFolderIndex: $selectedFolderIndex
                )
            }
        }
     }
     


     func deleteSelectedDocument() {
         guard let document = selectedDocument else {
             print("No document selected for deletion.")
             return
         }

         let db = Firestore.firestore()
         let storageRef = Storage.storage().reference()

         // Delete from Firestore
         db.collection("ResearchPapers").document(document.id.uuidString).delete { error in
             if let error = error {
                 print("Error deleting document from Firestore: \(error)")
                 return
             }
             print("Document successfully deleted from Firestore.")

             // Delete from Firebase Storage
             let fileRef = storageRef.child(document.url.lastPathComponent)
             fileRef.delete { error in
                 if let error = error {
                     print("Error deleting document from Firebase Storage: \(error)")
                 } else {
                     // Document successfully deleted from Firestore and Firebase Storage
                     // Remove it from the chatThreads array
                     DispatchQueue.main.async {
                         self.chatThreads.removeAll { $0.document.id == document.id }
                     }
                 }
             }
         }
     }
     
     func fetchDocuments() {
         if !didFetch {
             let db = Firestore.firestore()
             db.collection("ResearchPapers").getDocuments { (querySnapshot, error) in
                 if let error = error {
                     print("Error getting documents: \(error.localizedDescription)")
                     return
                 }
                 
                 guard let documents = querySnapshot?.documents else {
                     print("No documents found")
                     return
                 }
                 
                 let fetchedDocuments = documents.compactMap { documentSnapshot -> Document? in
                     let data = documentSnapshot.data()
                     guard let name = data["name"] as? String,
                           let urlString = data["url"] as? String,
                           let url = URL(string: urlString),
                           let folderIDString = data["folderID"] as? String,
                           let folderID = UUID(uuidString: folderIDString),
                           let uuidString = data["uuid"] as? String,
                           let uuid = UUID(uuidString: uuidString)
                     else {
                         return nil
                     }
                     return Document(id: uuid, name: name, url: url, folderID: folderID)
                 }
                 
                 self.updateChatThreads(with: fetchedDocuments)
             }
             didFetch = true
         }
     }

     func updateChatThreads(with documents: [Document]) {
         var updatedThreads: [ChatThread] = chatThreads

         for document in documents {
             if document.folderID == selectedFolder?.id {
                 if let existingThreadIndex = updatedThreads.firstIndex(where: { $0.document.id == document.id }) {
                     // Update the existing thread
                     updatedThreads[existingThreadIndex].document = document
                 }
                 else {
                     // Create a new thread only if it doesn't already exist
                     let newThread = ChatThread(document: document, chatMessages: [])
                     updatedThreads.append(newThread)
                 }
             }
         }

         // Sort the updatedThreads array based on the name of the documents
         updatedThreads.sort { $0.document.name.localizedCaseInsensitiveCompare($1.document.name) == .orderedAscending }

         chatThreads = updatedThreads
     }
  
     func moveSelectedDocument(document: Document, to folder: Folder) {
         let db = Firestore.firestore()

         db.collection("ResearchPapers").document(document.id.uuidString).updateData([
             "folderID": folder.id.uuidString
         ]) { error in
             if let error = error {
                 print("Error updating folderID in Firestore: \(error)")
             } else {
                 if let threadIndex = self.chatThreads.firstIndex(where: { $0.document.id == document.id }) {
                     if self.selectedFolder?.id != folder.id {
                         // Remove the document from chatThreads if it's moved out of the current folder
                         DispatchQueue.main.async {
                             self.chatThreads.remove(at: threadIndex)
                         }
                     } else {
                         // Update folderID if it's moved within the current folder
                         self.chatThreads[threadIndex].document.folderID = folder.id
                     }
                 }
             }
         }
     }
 }



 struct ChatThreadRow: View {
    let thread: ChatThread
    var onDelete: () -> Void
    var onMove: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundColor(.blue)
            VStack(alignment: .leading) {
                Text(thread.document.name)
                    .font(.headline)
                Text("Last message: \(thread.chatMessages.last?.content ?? "No messages")")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
        .contextMenu {
            Button(action: onDelete) {
                Text("Delete")
                Image(systemName: "trash")
            }
            Button(action: onMove) {
                Text("Move")
                Image(systemName: "folder")
            }
        }
    }
 }

 // Custom SearchBar component
 struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        TextField("Search...", text: $text)
            .padding(7)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal)
    }
 }

 */



















/*
 import SwiftUI
 import MobileCoreServices
 import FirebaseStorage
 import UniformTypeIdentifiers
 import FirebaseFirestore

 struct Document: Identifiable {
    let id: UUID
    let name: String
    let url: URL
    var folderID: UUID

    init(id: UUID, name: String, url: URL, folderID: UUID) {
        self.id = id
        self.name = name
        self.url = url
        self.folderID = folderID
    }
 }

 struct ChatThread: Identifiable {
     let id = UUID()
     var document: Document
     var chatMessages: [ChatMessage]
 }



 struct HomePage: View {
     
     @State private var alert = false
     @State private var chatThreads: [ChatThread] = []
     @State private var documents: [Document] = []
     @State private var errorMessage = ""
     @State private var isLoading = true // New state to manage loading state
     @State private var showDocumentPicker = false
     @State private var searchText = ""
     @State var didFetch = false
     @Binding var selectedFolder: Folder?
     @State private var showMoveDocumentView = false
     @State private var selectedDocument: Document?
     @State private var selectedMoveFolder: Folder?
     @Binding var folders: [Folder]
     @State private var selectedThread: ChatThread?
     @State private var longPressedDocument: Document?
     @State private var isLongPressActive = false // New state for long-press
     @State private var showDeleteConfirmationAlert = false
     @State private var selectedFolderIndex: Int = 0 // Initialize with default selected index
     @State private var isLoadingDocument = false
     @State private var showSuccessMessage = false  // State to manage success message

     var filteredChatThreads: [ChatThread] {
         searchText.isEmpty ? chatThreads : chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
     }

     var body: some View {
         VStack {
             
             if let folderName = selectedFolder?.name {
                 Text(folderName)
                     .font(.largeTitle)
                     .fontWeight(.bold)
                     .padding(.top)
             }

             SearchBar(text: $searchText)  // Custom SearchBar component

             List(filteredChatThreads) { thread in
                 NavigationLink(destination: DocumentView(documentURL: thread.document.url)) {
                     ChatThreadRow(thread: thread,
                                   onDelete: {
                                       self.selectedDocument = thread.document
                                       self.deleteSelectedDocument()
                                   },
                                   onMove: {
                                       self.selectedDocument = thread.document
                                       self.showMoveDocumentView = true
                                   })
                 }
             }
             .listStyle(PlainListStyle())
         }
         .padding(.horizontal)
         .navigationBarTitle("Documents", displayMode: .inline)
         .navigationBarItems(trailing: Button(action: {
             showDocumentPicker.toggle()
         }) {
             Image(systemName: "plus")
                 .imageScale(.large)
         })

         .onAppear {
             fetchDocuments()
         }
         .sheet(isPresented: $showDocumentPicker) {
             DocumentPicker(
                alert: self.$alert,
                documents: self.$documents,
                completionHandler: { document, errorMessage in
                    if let errorMessage = errorMessage {
                        self.errorMessage = errorMessage
                    }
                    else {
                        // Handle successful document upload if needed
                        
                        let newThread = ChatThread(document: document, chatMessages: [])
                        self.chatThreads.append(newThread)
                        self.chatThreads.sort { $0.document.name.localizedCaseInsensitiveCompare($1.document.name) == .orderedAscending }
                    }
                }, selectedFolder: self.$selectedFolder
            )
        }
        .alert(isPresented: $alert) {
            if !errorMessage.isEmpty {
                return Alert(
                    title: Text("Error"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("Ok")) {
                        errorMessage = ""
                    }
                )
            }
            else {
                return Alert(
                title: Text("Message"),
                message: Text("Uploaded Successfully"),
                dismissButton: .default(Text("Ok"))
                )
            }
        }
        .sheet(isPresented: $showMoveDocumentView, onDismiss: {
            selectedMoveFolder = nil
        }) {
            if let selectedDocument = selectedDocument {
                MoveDocumentView(
                    showMoveDocumentView: $showMoveDocumentView,
                    document: selectedDocument,
                    availableFolders: folders,
                    selectedFolder: $selectedMoveFolder,
                    moveAction: { folder in
                        moveSelectedDocument(document: selectedDocument, to: folder)
                        showMoveDocumentView = false
                    },
                    selectedFolderIndex: $selectedFolderIndex
                )
            }
        }
     }
     


     func deleteSelectedDocument() {
         guard let document = selectedDocument else {
             print("No document selected for deletion.")
             return
         }

         let db = Firestore.firestore()
         let storageRef = Storage.storage().reference()

         // Delete from Firestore
         db.collection("ResearchPapers").document(document.id.uuidString).delete { error in
             if let error = error {
                 print("Error deleting document from Firestore: \(error)")
                 return
             }
             print("Document successfully deleted from Firestore.")

             // Delete from Firebase Storage
             let fileRef = storageRef.child(document.url.lastPathComponent)
             fileRef.delete { error in
                 if let error = error {
                     print("Error deleting document from Firebase Storage: \(error)")
                 } else {
                     // Document successfully deleted from Firestore and Firebase Storage
                     // Remove it from the chatThreads array
                     DispatchQueue.main.async {
                         self.chatThreads.removeAll { $0.document.id == document.id }
                     }
                 }
             }
         }
     }
     
     func fetchDocuments() {
         if !didFetch {
             let db = Firestore.firestore()
             db.collection("ResearchPapers").getDocuments { (querySnapshot, error) in
                 if let error = error {
                     print("Error getting documents: \(error.localizedDescription)")
                     return
                 }
                 
                 guard let documents = querySnapshot?.documents else {
                     print("No documents found")
                     return
                 }
                 
                 let fetchedDocuments = documents.compactMap { documentSnapshot -> Document? in
                     let data = documentSnapshot.data()
                     guard let name = data["name"] as? String,
                           let urlString = data["url"] as? String,
                           let url = URL(string: urlString),
                           let folderIDString = data["folderID"] as? String,
                           let folderID = UUID(uuidString: folderIDString),
                           let uuidString = data["uuid"] as? String,
                           let uuid = UUID(uuidString: uuidString)
                     else {
                         return nil
                     }
                     return Document(id: uuid, name: name, url: url, folderID: folderID)
                 }
                 
                 self.updateChatThreads(with: fetchedDocuments)
             }
             didFetch = true
         }
     }

     func updateChatThreads(with documents: [Document]) {
         var updatedThreads: [ChatThread] = chatThreads

         for document in documents {
             if document.folderID == selectedFolder?.id {
                 if let existingThreadIndex = updatedThreads.firstIndex(where: { $0.document.id == document.id }) {
                     // Update the existing thread
                     updatedThreads[existingThreadIndex].document = document
                 }
                 else {
                     // Create a new thread only if it doesn't already exist
                     let newThread = ChatThread(document: document, chatMessages: [])
                     updatedThreads.append(newThread)
                 }
             }
         }

         // Sort the updatedThreads array based on the name of the documents
         updatedThreads.sort { $0.document.name.localizedCaseInsensitiveCompare($1.document.name) == .orderedAscending }

         chatThreads = updatedThreads
     }
  
     func moveSelectedDocument(document: Document, to folder: Folder) {
         let db = Firestore.firestore()

         // Update the folderID of the document in Firestore
         db.collection("ResearchPapers").document(document.id.uuidString).updateData([
             "folderID": folder.id.uuidString
         ]) { error in
             if let error = error {
                 print("Error updating folderID in Firestore: \(error)")
             }
             else {
                 // Successfully moved the document, update the document's folderID in chatThreads
                 if let threadIndex = self.chatThreads.firstIndex(where: { $0.document.id == document.id }) {
                     self.chatThreads[threadIndex].document.folderID = folder.id
                 }
             }
         }
     }

 }



 struct ChatThreadRow: View {
    let thread: ChatThread
    var onDelete: () -> Void
    var onMove: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundColor(.blue)
            VStack(alignment: .leading) {
                Text(thread.document.name)
                    .font(.headline)
                Text("Last message: \(thread.chatMessages.last?.content ?? "No messages")")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
        .contextMenu {
            Button(action: onDelete) {
                Text("Delete")
                Image(systemName: "trash")
            }
            Button(action: onMove) {
                Text("Move")
                Image(systemName: "folder")
            }
        }
    }
 }

 // Custom SearchBar component
 struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        TextField("Search...", text: $text)
            .padding(7)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal)
    }
 }
 */




















/*
 import SwiftUI
 import MobileCoreServices
 import FirebaseStorage
 import UniformTypeIdentifiers
 import FirebaseFirestore

 struct Document: Identifiable {
    let id: UUID
    let name: String
    let url: URL
    var folderID: UUID

    init(id: UUID, name: String, url: URL, folderID: UUID) {
        self.id = id
        self.name = name
        self.url = url
        self.folderID = folderID
    }
 }

 struct ChatThread: Identifiable {
     let id = UUID()
     var document: Document
     var chatMessages: [ChatMessage]
 }



 struct HomePage: View {
     
     @State private var alert = false
     @State private var chatThreads: [ChatThread] = []
     @State private var documents: [Document] = []
     @State private var errorMessage = ""
     @State private var isLoading = true // New state to manage loading state
     @State private var showDocumentPicker = false
     @State private var searchText = ""
     @State var didFetch = false
     @Binding var selectedFolder: Folder?
     @State private var showMoveDocumentView = false
     @State private var selectedDocument: Document?
     @State private var selectedMoveFolder: Folder?
     @Binding var folders: [Folder]
     @State private var selectedThread: ChatThread?
     @State private var selectedDocuments: Set<UUID> = []
     @State private var longPressedDocument: Document?
     @State private var isLongPressActive = false // New state for long-press
     @State private var showDeleteConfirmationAlert = false
     @State private var selectedFolderIndex: Int = 0 // Initialize with default selected index
     @State private var isLoadingDocument = false
     // State to track the currently opening document
     @State private var showSuccessMessage = false  // State to manage success message

     var filteredChatThreads: [ChatThread] {
         searchText.isEmpty ? chatThreads : chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
     }

     var body: some View {
         VStack {
             
             if let folderName = selectedFolder?.name {
                 Text(folderName)
                     .font(.largeTitle)
                     .fontWeight(.bold)
                     .padding(.top)
             }

             SearchBar(text: $searchText)  // Custom SearchBar component

             List(filteredChatThreads) { thread in
                 NavigationLink(destination: DocumentView(documentURL: thread.document.url)) {
                     ChatThreadRow(thread: thread,
                                   onDelete: {
                                       self.selectedDocuments.insert(thread.document.id)
                                       self.deleteSelectedDocuments()
                                   },
                                   onMove: {
                                       self.selectedDocument = thread.document
                                       self.showMoveDocumentView = true
                                   })
                 }
             }
             .listStyle(PlainListStyle())
         }
         .padding(.horizontal)
         .navigationBarTitle("Documents", displayMode: .inline)
         .navigationBarItems(trailing: Button(action: {
             showDocumentPicker.toggle()
         }) {
             Image(systemName: "plus")
                 .imageScale(.large)
         })

         .onAppear {
             fetchDocuments()
         }
         .sheet(isPresented: $showDocumentPicker) {
             DocumentPicker(
                alert: self.$alert,
                documents: self.$documents,
                completionHandler: { document, errorMessage in
                    if let errorMessage = errorMessage {
                        self.errorMessage = errorMessage
                    }
                    else {
                        // Handle successful document upload if needed
                        
                        let newThread = ChatThread(document: document, chatMessages: [])
                        self.chatThreads.append(newThread)
                        self.chatThreads.sort { $0.document.name.localizedCaseInsensitiveCompare($1.document.name) == .orderedAscending }
                    }
                }, selectedFolder: self.$selectedFolder
            )
        }
        .alert(isPresented: $alert) {
            if !errorMessage.isEmpty {
                return Alert(
                    title: Text("Error"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("Ok")) {
                        errorMessage = ""
                    }
                )
            }
            else {
                return Alert(
                title: Text("Message"),
                message: Text("Uploaded Successfully"),
                dismissButton: .default(Text("Ok"))
                )
            }
        }
        .sheet(isPresented: $showMoveDocumentView, onDismiss: {
            selectedMoveFolder = nil
        }) {
            if let selectedDocument = selectedDocument {
                MoveDocumentView(
                    showMoveDocumentView: $showMoveDocumentView,
                    document: selectedDocument,
                    availableFolders: folders,
                    selectedFolder: $selectedMoveFolder,
                    moveAction: { folder in
                        moveSelectedDocument(document: selectedDocument, to: folder)
                        showMoveDocumentView = false
                    },
                    selectedFolderIndex: $selectedFolderIndex
                )
            }
        }
     }
     


     func deleteSelectedDocuments() {
         let db = Firestore.firestore()
         let storageRef = Storage.storage().reference()

         for documentID in selectedDocuments {
             // Delete from Firestore
             db.collection("ResearchPapers").document(documentID.uuidString).delete { error in
                 if let error = error {
                     print("Error deleting document from Firestore: \(error)")
                     return
                 }
                 print("Document successfully deleted from Firestore.")

                 // Find the document in the chatThreads to get the URL for Firebase Storage
                 if let document = chatThreads.first(where: { $0.document.id == documentID }) {
                     // Delete from Firebase Storage
                     let fileRef = storageRef.child(document.document.url.lastPathComponent)
                     fileRef.delete { error in
                         if let error = error {
                             print("Error deleting document from Firebase Storage: \(error)")
                         } else {
                             // Document successfully deleted from Firestore and Firebase Storage
                             // Remove it from the chatThreads array
                             DispatchQueue.main.async {
                                 self.chatThreads.removeAll { $0.document.id == documentID }
                             }
                         }
                     }
                 }
             }
         }
         // Clear the selectedDocuments set
         self.selectedDocuments.removeAll()
     }

     // Function to toggle document selection
     func toggleSelection(_ documentID: UUID) {
         if selectedDocuments.contains(documentID) {
             selectedDocuments.remove(documentID)
         } else {
             selectedDocuments.insert(documentID)
         }
     }
     
     // Function to select all documents
     func selectAll() {
         selectedDocuments = Set(filteredChatThreads.map { $0.document.id })
     }
     
     // Function to deselect all documents
     func deselectAll() {
         selectedDocuments.removeAll()
     }

     
     func fetchDocuments() {
         if !didFetch {
             let db = Firestore.firestore()
             db.collection("ResearchPapers").getDocuments { (querySnapshot, error) in
                 if let error = error {
                     print("Error getting documents: \(error.localizedDescription)")
                     return
                 }
                 
                 guard let documents = querySnapshot?.documents else {
                     print("No documents found")
                     return
                 }
                 
                 let fetchedDocuments = documents.compactMap { documentSnapshot -> Document? in
                     let data = documentSnapshot.data()
                     guard let name = data["name"] as? String,
                           let urlString = data["url"] as? String,
                           let url = URL(string: urlString),
                           let folderIDString = data["folderID"] as? String,
                           let folderID = UUID(uuidString: folderIDString),
                           let uuidString = data["uuid"] as? String,
                           let uuid = UUID(uuidString: uuidString)
                     else {
                         return nil
                     }
                     return Document(id: uuid, name: name, url: url, folderID: folderID)
                 }
                 
                 self.updateChatThreads(with: fetchedDocuments)
             }
             didFetch = true
         }
     }

     func updateChatThreads(with documents: [Document]) {
         var updatedThreads: [ChatThread] = chatThreads

         for document in documents {
             if document.folderID == selectedFolder?.id {
                 if let existingThreadIndex = updatedThreads.firstIndex(where: { $0.document.id == document.id }) {
                     // Update the existing thread
                     updatedThreads[existingThreadIndex].document = document
                 }
                 else {
                     // Create a new thread only if it doesn't already exist
                     let newThread = ChatThread(document: document, chatMessages: [])
                     updatedThreads.append(newThread)
                 }
             }
         }

         // Sort the updatedThreads array based on the name of the documents
         updatedThreads.sort { $0.document.name.localizedCaseInsensitiveCompare($1.document.name) == .orderedAscending }

         chatThreads = updatedThreads
     }
  
     func moveSelectedDocument(document: Document, to folder: Folder) {
         let db = Firestore.firestore()

         // Update the folderID of the document in Firestore
         db.collection("ResearchPapers").document(document.id.uuidString).updateData([
             "folderID": folder.id.uuidString
         ]) { error in
             if let error = error {
                 print("Error updating folderID in Firestore: \(error)")
             } else {
                 // Successfully moved the document, update the document's folderID in chatThreads
                 if let threadIndex = self.chatThreads.firstIndex(where: { $0.document.id == document.id }) {
                     self.chatThreads[threadIndex].document.folderID = folder.id
                 }
             }
         }
     }

 }



 struct ChatThreadRow: View {
    let thread: ChatThread
    var onDelete: () -> Void
    var onMove: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundColor(.blue)
            VStack(alignment: .leading) {
                Text(thread.document.name)
                    .font(.headline)
                Text("Last message: \(thread.chatMessages.last?.content ?? "No messages")")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
        .contextMenu {
            Button(action: onDelete) {
                Text("Delete")
                Image(systemName: "trash")
            }
            Button(action: onMove) {
                Text("Move")
                Image(systemName: "folder")
            }
        }
    }
 }

 // Custom SearchBar component
 struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        TextField("Search...", text: $text)
            .padding(7)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal)
    }
 }
 */





















/*
 import SwiftUI
 import MobileCoreServices
 import FirebaseStorage
 import UniformTypeIdentifiers
 import FirebaseFirestore

struct Document: Identifiable {
    let id: UUID
    let name: String
    let url: URL
    var folderID: UUID

    init(id: UUID, name: String, url: URL, folderID: UUID) {
        self.id = id
        self.name = name
        self.url = url
        self.folderID = folderID
    }
}

 struct ChatThread: Identifiable {
     let id = UUID()
     var document: Document
     var chatMessages: [ChatMessage]
 }



 struct HomePage: View {
     
     @State private var alert = false
     @State private var chatThreads: [ChatThread] = []
     @State private var documents: [Document] = []
     @State private var errorMessage = ""
     @State private var isLoading = true // New state to manage loading state
     @State private var showDocumentPicker = false
     @State private var searchText = ""
     @State var didFetch = false
     @Binding var selectedFolder: Folder?
     @State private var showMoveDocumentView = false
     @State private var selectedDocument: Document?
     @State private var selectedMoveFolder: Folder?
     @State private var folders: [Folder] = []
     @State private var selectedThread: ChatThread?
     @State private var selectedDocuments: Set<UUID> = []
     @State private var longPressedDocument: Document?
     @State private var isLongPressActive = false // New state for long-press
     @State private var showDeleteConfirmationAlert = false
     @State private var selectedFolderIndex: Int = 0 // Initialize with default selected index
     @State private var isLoadingDocument = false
     // State to track the currently opening document
     @State private var showSuccessMessage = false  // State to manage success message

     var filteredChatThreads: [ChatThread] {
         searchText.isEmpty ? chatThreads : chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
     }

     var body: some View {
         VStack {
             
             if let folderName = selectedFolder?.name {
                 Text(folderName)
                     .font(.largeTitle)
                     .fontWeight(.bold)
                     .padding(.top)
             }

             SearchBar(text: $searchText)  // Custom SearchBar component

             List(filteredChatThreads) { thread in
                 NavigationLink(destination: DocumentView(documentURL: thread.document.url)) {
                     ChatThreadRow(thread: thread,
                                   onDelete: {
                                       self.selectedDocuments.insert(thread.document.id)
                                       self.deleteSelectedDocuments()
                                   },
                                   onMove: { self.showMoveDocumentView = true; self.selectedDocument = thread.document })
                 }
             }
             .listStyle(PlainListStyle())
         }
         .padding(.horizontal)
         .navigationBarTitle("Documents", displayMode: .inline)
         .navigationBarItems(trailing: Button(action: {
             showDocumentPicker.toggle()
         }) {
             Image(systemName: "plus")
                 .imageScale(.large)
         })

         .onAppear {
             fetchDocuments()
         }
         .sheet(isPresented: $showDocumentPicker) {
             DocumentPicker(
                alert: self.$alert,
                documents: self.$documents,
                completionHandler: { document, errorMessage in
                    if let errorMessage = errorMessage {
                        self.errorMessage = errorMessage
                    }
                    else {
                        // Handle successful document upload if needed
                        
                        let newThread = ChatThread(document: document, chatMessages: [])
                        self.chatThreads.append(newThread)
                        self.chatThreads.sort { $0.document.name.localizedCaseInsensitiveCompare($1.document.name) == .orderedAscending }
                    }
                }, selectedFolder: self.$selectedFolder
            )
        }
        .alert(isPresented: $alert) {
            if !errorMessage.isEmpty {
                return Alert(
                    title: Text("Error"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("Ok")) {
                        errorMessage = ""
                    }
                )
            }
            else {
                return Alert(
                title: Text("Message"),
                message: Text("Uploaded Successfully"),
                dismissButton: .default(Text("Ok"))
                )
            }
        }
         .sheet(isPresented: $showMoveDocumentView, onDismiss: {
             selectedMoveFolder = nil
         }) {
             MoveDocumentView(
                 showMoveDocumentView: $showMoveDocumentView,
                 selectedDocuments: selectedDocuments,
                 availableFolders: folders,
                 selectedFolder: $selectedMoveFolder,
                 moveAction: { folder in
                     moveSelectedDocuments(folder: folder)
                     showMoveDocumentView = false // Close the sheet after moving documents
                 },
                 selectedFolderIndex: $selectedFolderIndex
             )
             .id(UUID()) // Force view refresh
             .onDisappear {
                 isLongPressActive = false // Reset long-press state when sheet is dismissed
             }
         }
     }
     


     func deleteSelectedDocuments() {
         let db = Firestore.firestore()
         let storageRef = Storage.storage().reference()

         for documentID in selectedDocuments {
             // Delete from Firestore
             db.collection("ResearchPapers").document(documentID.uuidString).delete { error in
                 if let error = error {
                     print("Error deleting document from Firestore: \(error)")
                     return
                 }
                 print("Document successfully deleted from Firestore.")

                 // Find the document in the chatThreads to get the URL for Firebase Storage
                 if let document = chatThreads.first(where: { $0.document.id == documentID }) {
                     // Delete from Firebase Storage
                     let fileRef = storageRef.child(document.document.url.lastPathComponent)
                     fileRef.delete { error in
                         if let error = error {
                             print("Error deleting document from Firebase Storage: \(error)")
                         } else {
                             // Document successfully deleted from Firestore and Firebase Storage
                             // Remove it from the chatThreads array
                             DispatchQueue.main.async {
                                 self.chatThreads.removeAll { $0.document.id == documentID }
                             }
                         }
                     }
                 }
             }
         }
         // Clear the selectedDocuments set
         self.selectedDocuments.removeAll()
     }

     // Function to toggle document selection
     func toggleSelection(_ documentID: UUID) {
         if selectedDocuments.contains(documentID) {
             selectedDocuments.remove(documentID)
         } else {
             selectedDocuments.insert(documentID)
         }
     }
     
     // Function to select all documents
     func selectAll() {
         selectedDocuments = Set(filteredChatThreads.map { $0.document.id })
     }
     
     // Function to deselect all documents
     func deselectAll() {
         selectedDocuments.removeAll()
     }

     
     func fetchDocuments() {
         if !didFetch {
             let db = Firestore.firestore()
             db.collection("ResearchPapers").getDocuments { (querySnapshot, error) in
                 if let error = error {
                     print("Error getting documents: \(error.localizedDescription)")
                     return
                 }
                 
                 guard let documents = querySnapshot?.documents else {
                     print("No documents found")
                     return
                 }
                 
                 let fetchedDocuments = documents.compactMap { documentSnapshot -> Document? in
                     let data = documentSnapshot.data()
                     guard let name = data["name"] as? String,
                           let urlString = data["url"] as? String,
                           let url = URL(string: urlString),
                           let folderIDString = data["folderID"] as? String,
                           let folderID = UUID(uuidString: folderIDString),
                           let uuidString = data["uuid"] as? String,
                           let uuid = UUID(uuidString: uuidString)
                     else {
                         return nil
                     }
                     return Document(id: uuid, name: name, url: url, folderID: folderID)
                 }
                 
                 self.updateChatThreads(with: fetchedDocuments)
             }
             didFetch = true
         }
     }

     func updateChatThreads(with documents: [Document]) {
         var updatedThreads: [ChatThread] = chatThreads

         for document in documents {
             if document.folderID == selectedFolder?.id {
                 if let existingThreadIndex = updatedThreads.firstIndex(where: { $0.document.id == document.id }) {
                     // Update the existing thread
                     updatedThreads[existingThreadIndex].document = document
                 }
                 else {
                     // Create a new thread only if it doesn't already exist
                     let newThread = ChatThread(document: document, chatMessages: [])
                     updatedThreads.append(newThread)
                 }
             }
         }

         // Sort the updatedThreads array based on the name of the documents
         updatedThreads.sort { $0.document.name.localizedCaseInsensitiveCompare($1.document.name) == .orderedAscending }

         chatThreads = updatedThreads
     }
  
     func moveSelectedDocuments(folder: Folder) {
         let db = Firestore.firestore()

         for threadIndex in chatThreads.indices {
             if selectedDocuments.contains(chatThreads[threadIndex].document.id) {
                 let documentName = chatThreads[threadIndex].document.name

                 // Query Firestore by document name
                 db.collection("ResearchPapers").whereField("name", isEqualTo: documentName).getDocuments { (snapshot, error) in
                     if let error = error {
                         print("Error querying documents: \(error.localizedDescription)")
                         return
                     }

                     guard let document = snapshot?.documents.first else {
                         print("Document not found")
                         return
                     }

                     // Update the folderID of the retrieved document
                     document.reference.updateData([
                         "folderID": folder.id.uuidString
                     ]) { error in
                         if let error = error {
                             print("Error updating folderID in Firestore: \(error)")
                         }
                         else {
                             // Successfully moved documents, update selectedFolder
                             selectedFolder = folder
                         }
                     }
                 }
             }
         }

         selectedDocuments.removeAll()
     }

 }



struct ChatThreadRow: View {
    let thread: ChatThread
    var onDelete: () -> Void
    var onMove: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundColor(.blue)
            VStack(alignment: .leading) {
                Text(thread.document.name)
                    .font(.headline)
                Text("Last message: \(thread.chatMessages.last?.content ?? "No messages")")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
        .contextMenu {
            Button(action: onDelete) {
                Text("Delete")
                Image(systemName: "trash")
            }
            Button(action: onMove) {
                Text("Move")
                Image(systemName: "folder")
            }
        }
    }
}

// Custom SearchBar component
struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        TextField("Search...", text: $text)
            .padding(7)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal)
    }
}
 */

















/*
 import SwiftUI
 import MobileCoreServices
 import FirebaseStorage
 import UniformTypeIdentifiers
 import FirebaseFirestore

 struct Document: Identifiable { // Rename here
     let id = UUID()
     let name: String
     let url: URL
     var folderID: UUID
 }

 struct ChatThread: Identifiable {
     let id = UUID()
     var document: Document
     var chatMessages: [ChatMessage]
 }



 struct HomePage: View {
     
     @State private var alert = false
     @State private var chatThreads: [ChatThread] = []
     @State private var documents: [Document] = []
     @State private var errorMessage = ""
     @State private var isLoading = true // New state to manage loading state
     @State private var showDocumentPicker = false
     @State private var searchText = ""
     @State var didFetch = false
     @Binding var selectedFolder: Folder?
     @State private var showMoveDocumentView = false
     @State private var selectedDocument: Document?
     @State private var selectedMoveFolder: Folder?
     @State private var folders: [Folder] = []
     @State private var selectedThread: ChatThread?
     @State private var selectedDocuments: Set<UUID> = []
     @State private var longPressedDocument: Document?
     @State private var isLongPressActive = false // New state for long-press
     @State private var showDeleteConfirmationAlert = false
     @State private var selectedFolderIndex: Int = 0 // Initialize with default selected index
     @State private var isLoadingDocument = false
     // State to track the currently opening document
     @State private var showSuccessMessage = false  // State to manage success message

     var filteredChatThreads: [ChatThread] {
         searchText.isEmpty ? chatThreads : chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
     }

     var body: some View {
         VStack {
             
             if let folderName = selectedFolder?.name {
                 Text(folderName)
                     .font(.largeTitle)
                     .fontWeight(.bold)
                     .padding(.top)
             }

             SearchBar(text: $searchText)  // Custom SearchBar component

             List(filteredChatThreads) { thread in
                 NavigationLink(destination: DocumentView(documentURL: thread.document.url)) {
                     ChatThreadRow(thread: thread)  // Custom ChatThreadRow component
                 }
             }
             .listStyle(PlainListStyle())
         }
         .padding(.horizontal)
         .navigationBarTitle("Documents", displayMode: .inline)
         .navigationBarItems(trailing: Button(action: {
             showDocumentPicker.toggle()
         }) {
             Image(systemName: "plus")
                 .imageScale(.large)
         })

         .onAppear {
             fetchDocuments()
         }
         .sheet(isPresented: $showDocumentPicker) {
             DocumentPicker(
                 alert: self.$alert,
                 documents: self.$documents,
                 completionHandler: { document, errorMessage in
                     if let errorMessage = errorMessage {
                         self.errorMessage = errorMessage
                         self.alert = true
                     }
                     else {
                         // Handle successful document upload
                         self.documents.append(document) // Add the new document to the documents array
                         self.updateChatThreads(with: self.documents) // Update chat threads with the new document list
                         self.showSuccessMessage = true  // Set success message flag
                     }
                 }, selectedFolder: self.$selectedFolder
             )
         }
         .alert(isPresented: $alert) {
             Alert(
                 title: Text("Error"),
                 message: Text(errorMessage),
                 dismissButton: .default(Text("Ok")) {
                     errorMessage = ""
                 }
             )
         }
         .alert(isPresented: $showSuccessMessage) {
             Alert(
                 title: Text("Message"),
                 message: Text("Uploaded Successfully"),
                 dismissButton: .default(Text("Ok"))
             )
         }
         .sheet(isPresented: $showMoveDocumentView, onDismiss: {
             selectedMoveFolder = nil
         }) {
             MoveDocumentView(
                 showMoveDocumentView: $showMoveDocumentView,
                 selectedDocuments: selectedDocuments,
                 availableFolders: folders,
                 selectedFolder: $selectedMoveFolder,
                 moveAction: { folder in
                     moveSelectedDocuments(folder: folder)
                     showMoveDocumentView = false // Close the sheet after moving documents
                 },
                 selectedFolderIndex: $selectedFolderIndex
             )
             .id(UUID()) // Force view refresh
             .onDisappear {
                 isLongPressActive = false // Reset long-press state when sheet is dismissed
             }
         }
         .alert(isPresented: $showDeleteConfirmationAlert) {
             Alert(
                 title: Text("Delete Documents"),
                 message: Text("Are you sure you want to delete the selected documents?"),
                 primaryButton: .default(Text("Cancel")),
                 secondaryButton: .destructive(Text("Delete")) {
                     deleteSelectedDocuments()
                 }
             )
         }


     }
     


     func deleteSelectedDocuments() {
         let db = Firestore.firestore()
         let storageRef = Storage.storage().reference()
         
         for threadIndex in chatThreads.indices {
             if selectedDocuments.contains(chatThreads[threadIndex].document.id) {
                 let document = chatThreads[threadIndex].document
                 
                 // Delete the document from Firestore
                 db.collection("ResearchPapers").document(document.id.uuidString).delete { error in
                     if let error = error {
                         print("Error deleting document from Firestore: \(error)")
                         return
                     }
                     
                     // Delete the document from Firebase Storage
                     let fileRef = storageRef.child(document.url.lastPathComponent)
                     fileRef.delete { error in
                         if let error = error {
                             print("Error deleting document from Firebase Storage: \(error)")
                         }
                         else {
                             // Document successfully deleted from Firestore and Firebase Storage
                             // You can also remove it from the chatThreads array
                             if let indexToDelete = chatThreads.firstIndex(where: { $0.document.id == document.id }) {
                                 chatThreads.remove(at: indexToDelete)
                             }
                             // Clear the selectedDocuments set
                             selectedDocuments.remove(document.id)
                         }
                     }
                 }
             }
         }
     }
     
     // Function to toggle document selection
     func toggleSelection(_ documentID: UUID) {
         if selectedDocuments.contains(documentID) {
             selectedDocuments.remove(documentID)
         } else {
             selectedDocuments.insert(documentID)
         }
     }
     
     // Function to select all documents
     func selectAll() {
         selectedDocuments = Set(filteredChatThreads.map { $0.document.id })
     }
     
     // Function to deselect all documents
     func deselectAll() {
         selectedDocuments.removeAll()
     }

     
     func fetchDocuments() {
         if !didFetch {
             
             let db = Firestore.firestore()
             db.collection("ResearchPapers").getDocuments { (querySnapshot, error) in
                 if let error = error {
                     print("Error getting documents: \(error.localizedDescription)")
                     return
                 }
                 
                 guard let documents = querySnapshot?.documents else {
                     print("No documents found")
                     return
                 }
                 
                 let fetchedDocuments = documents.compactMap { document -> Document? in
                     let data = document.data()
                     guard let name = data["name"] as? String,
                           let urlString = data["url"] as? String,
                           let url = URL(string: urlString),
                           let ID = data["folderID"] as? String,
                           let folderID = UUID(uuidString: ID)
                     else {
                         return nil
                     }
                     return Document(name: name, url: url, folderID: folderID)
                 }
                 
                 
                 updateChatThreads(with: fetchedDocuments)
             }
             didFetch = true
         }
     }
     
     func updateChatThreads(with documents: [Document]) {
         var updatedThreads: [ChatThread] = chatThreads

         for document in documents {
             if document.folderID == selectedFolder?.id {
                 if let existingThreadIndex = updatedThreads.firstIndex(where: { $0.document.id == document.id }) {
                     // Update the existing thread
                     updatedThreads[existingThreadIndex].document = document
                 }
                 else {
                     // Create a new thread only if it doesn't already exist
                     let newThread = ChatThread(document: document, chatMessages: [])
                     updatedThreads.append(newThread)
                 }
             }
         }

         // Sort the updatedThreads array based on the name of the documents
         updatedThreads.sort { $0.document.name.localizedCaseInsensitiveCompare($1.document.name) == .orderedAscending }

         chatThreads = updatedThreads
     }
  
     func moveSelectedDocuments(folder: Folder) {
         let db = Firestore.firestore()

         for threadIndex in chatThreads.indices {
             if selectedDocuments.contains(chatThreads[threadIndex].document.id) {
                 let documentName = chatThreads[threadIndex].document.name

                 // Query Firestore by document name
                 db.collection("ResearchPapers").whereField("name", isEqualTo: documentName).getDocuments { (snapshot, error) in
                     if let error = error {
                         print("Error querying documents: \(error.localizedDescription)")
                         return
                     }

                     guard let document = snapshot?.documents.first else {
                         print("Document not found")
                         return
                     }

                     // Update the folderID of the retrieved document
                     document.reference.updateData([
                         "folderID": folder.id.uuidString
                     ]) { error in
                         if let error = error {
                             print("Error updating folderID in Firestore: \(error)")
                         }
                         else {
                             // Successfully moved documents, update selectedFolder
                             selectedFolder = folder
                         }
                     }
                 }
             }
         }

         selectedDocuments.removeAll()
     }

 }



// Custom view for each chat thread row
struct ChatThreadRow: View {
    let thread: ChatThread

    var body: some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundColor(.blue)
            VStack(alignment: .leading) {
                Text(thread.document.name)
                    .font(.headline)
                Text("Last message: \(thread.chatMessages.last?.content ?? "No messages")")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
    }
}

// Custom SearchBar component
struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        TextField("Search...", text: $text)
            .padding(7)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal)
    }
}
 */



















/*
 
 import SwiftUI
 import MobileCoreServices
 import FirebaseStorage
 import UniformTypeIdentifiers
 import FirebaseFirestore

 struct Document: Identifiable { // Rename here
     let id = UUID()
     let name: String
     let url: URL
     var folderID: UUID
 }

 struct ChatThread: Identifiable {
     let id = UUID()
     var document: Document
     var chatMessages: [ChatMessage]
 }



 struct HomePage: View {
     
     @State private var alert = false
     @State private var chatThreads: [ChatThread] = []
     @State private var documents: [Document] = []
     @State private var errorMessage = ""
     @State private var isLoading = true // New state to manage loading state
     @State private var showDocumentPicker = false
     @State private var searchText = ""
     @State var didFetch = false
     @Binding var selectedFolder: Folder?
     @State private var showMoveDocumentView = false
     @State private var selectedDocument: Document?
     @State private var selectedMoveFolder: Folder?
     @State private var folders: [Folder] = []
     @State private var selectedThread: ChatThread?
     @State private var selectedDocuments: Set<UUID> = []
     @State private var longPressedDocument: Document?
     @State private var isLongPressActive = false // New state for long-press
     @State private var showDeleteConfirmationAlert = false
     @State private var selectedFolderIndex: Int = 0 // Initialize with default selected index
     @State private var isLoadingDocument = false
     // State to track the currently opening document
     @State private var openingDocumentID: String?

     var filteredChatThreads: [ChatThread] {
         searchText.isEmpty ? chatThreads : chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
     }

     var body: some View {
         VStack {
             if let folderName = selectedFolder?.name {
                 Text(folderName)
                     .font(.largeTitle)
                     .fontWeight(.bold)
                     .padding(.top)
             }

             SearchBar(text: $searchText)  // Custom SearchBar component

             List(filteredChatThreads) { thread in
                 NavigationLink(destination: DocumentView(documentURL: thread.document.url)) {
                     ChatThreadRow(thread: thread)  // Custom ChatThreadRow component
                 }
             }
             .listStyle(PlainListStyle())
         }
         .padding(.horizontal)
         .navigationBarTitle("Documents", displayMode: .inline)
         .onAppear {
             fetchChatThreads()  // Function to fetch chat threads
             fetchDocuments()
         }
     }
     
     // Function to fetch chat threads for the selected folder
     private func fetchChatThreads() {
         // Fetching logic here...
     }

     func deleteSelectedDocuments() {
         let db = Firestore.firestore()
         let storageRef = Storage.storage().reference()
         
         for threadIndex in chatThreads.indices {
             if selectedDocuments.contains(chatThreads[threadIndex].document.id) {
                 let document = chatThreads[threadIndex].document
                 
                 // Delete the document from Firestore
                 db.collection("ResearchPapers").document(document.id.uuidString).delete { error in
                     if let error = error {
                         print("Error deleting document from Firestore: \(error)")
                         return
                     }
                     
                     // Delete the document from Firebase Storage
                     let fileRef = storageRef.child(document.url.lastPathComponent)
                     fileRef.delete { error in
                         if let error = error {
                             print("Error deleting document from Firebase Storage: \(error)")
                         }
                         else {
                             // Document successfully deleted from Firestore and Firebase Storage
                             // You can also remove it from the chatThreads array
                             if let indexToDelete = chatThreads.firstIndex(where: { $0.document.id == document.id }) {
                                 chatThreads.remove(at: indexToDelete)
                             }
                             // Clear the selectedDocuments set
                             selectedDocuments.remove(document.id)
                         }
                     }
                 }
             }
         }
     }
     
     // Function to toggle document selection
     func toggleSelection(_ documentID: UUID) {
         if selectedDocuments.contains(documentID) {
             selectedDocuments.remove(documentID)
         } else {
             selectedDocuments.insert(documentID)
         }
     }
     
     // Function to select all documents
     func selectAll() {
         selectedDocuments = Set(filteredChatThreads.map { $0.document.id })
     }
     
     // Function to deselect all documents
     func deselectAll() {
         selectedDocuments.removeAll()
     }

     
     func fetchDocuments() {
         if !didFetch {
             
             let db = Firestore.firestore()
             db.collection("ResearchPapers").getDocuments { (querySnapshot, error) in
                 if let error = error {
                     print("Error getting documents: \(error.localizedDescription)")
                     return
                 }
                 
                 guard let documents = querySnapshot?.documents else {
                     print("No documents found")
                     return
                 }
                 
                 let fetchedDocuments = documents.compactMap { document -> Document? in
                     let data = document.data()
                     guard let name = data["name"] as? String,
                           let urlString = data["url"] as? String,
                           let url = URL(string: urlString),
                           let ID = data["folderID"] as? String,
                           let folderID = UUID(uuidString: ID)
                     else {
                         return nil
                     }
                     return Document(name: name, url: url, folderID: folderID)
                 }
                 
                 
                 updateChatThreads(with: fetchedDocuments)
             }
             didFetch = true
         }
     }
     
     func updateChatThreads(with documents: [Document]) {
         var updatedThreads: [ChatThread] = chatThreads

         for document in documents {
             if document.folderID == selectedFolder?.id {
                 if let existingThreadIndex = updatedThreads.firstIndex(where: { $0.document.id == document.id }) {
                     // Update the existing thread
                     updatedThreads[existingThreadIndex].document = document
                 }
                 else {
                     // Create a new thread only if it doesn't already exist
                     let newThread = ChatThread(document: document, chatMessages: [])
                     updatedThreads.append(newThread)
                 }
             }
         }

         // Sort the updatedThreads array based on the name of the documents
         updatedThreads.sort { $0.document.name.localizedCaseInsensitiveCompare($1.document.name) == .orderedAscending }

         chatThreads = updatedThreads
     }
     
     func moveSelectedDocuments(folder: Folder) {
         let db = Firestore.firestore()

         for threadIndex in chatThreads.indices {
             if selectedDocuments.contains(chatThreads[threadIndex].document.id) {
                 let documentName = chatThreads[threadIndex].document.name

                 // Query Firestore by document name
                 db.collection("ResearchPapers").whereField("name", isEqualTo: documentName).getDocuments { (snapshot, error) in
                     if let error = error {
                         print("Error querying documents: \(error.localizedDescription)")
                         return
                     }

                     guard let document = snapshot?.documents.first else {
                         print("Document not found")
                         return
                     }

                     // Update the folderID of the retrieved document
                     document.reference.updateData([
                         "folderID": folder.id.uuidString
                     ]) { error in
                         if let error = error {
                             print("Error updating folderID in Firestore: \(error)")
                         }
                         else {
                             // Successfully moved documents, update selectedFolder
                             selectedFolder = folder
                         }
                     }
                 }
             }
         }

         selectedDocuments.removeAll()
     }

 }



// Custom view for each chat thread row
struct ChatThreadRow: View {
    let thread: ChatThread

    var body: some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundColor(.blue)
            VStack(alignment: .leading) {
                Text(thread.document.name)
                    .font(.headline)
                Text("Last message: \(thread.chatMessages.last?.content ?? "No messages")")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
    }
}

// Custom SearchBar component
struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        TextField("Search...", text: $text)
            .padding(7)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal)
    }
}

 */












/*
 
 import SwiftUI
 import MobileCoreServices
 import FirebaseStorage
 import UniformTypeIdentifiers
 import FirebaseFirestore

 struct Document: Identifiable { // Rename here
     let id = UUID()
     let name: String
     let url: URL
     var folderID: UUID
 }

 struct ChatThread: Identifiable {
     let id = UUID()
     var document: Document
     var chatMessages: [ChatMessage]
 }


 struct HomePage: View {
     
     @State private var alert = false
     @State private var chatThreads: [ChatThread] = []
     @State private var documents: [Document] = []
     @State private var errorMessage = ""
     @State private var isLoading = true // New state to manage loading state
     @State private var showDocumentPicker = false
     @State private var searchText = ""
     @State var didFetch = false
     @Binding var selectedFolder: Folder?
     @State private var showMoveDocumentView = false
     @State private var selectedDocument: Document?
     @State private var selectedMoveFolder: Folder?
     @State private var folders: [Folder] = []
     @State private var selectedThread: ChatThread?
     @State private var selectedDocuments: Set<UUID> = []
     @State private var longPressedDocument: Document?
     @State private var isLongPressActive = false // New state for long-press
     @State private var showDeleteConfirmationAlert = false
     @State private var selectedFolderIndex: Int = 0 // Initialize with default selected index

     var filteredChatThreads: [ChatThread] {
         if searchText.isEmpty {
             return chatThreads
         }
         else {
             return chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
         }
     }
     
     var body: some View {
         ZStack {
             List {
                 ForEach(Array(filteredChatThreads.enumerated()), id: \.element.id) { (index, thread) in
                     NavigationLink(destination: DocumentView(documentURL: thread.document.url).transition(.slide)) {
                         HStack {
                             // Primary HStack for content
                             HStack(alignment: .center, spacing: 10) {
                                 Text("\(index + 1).")
                                     .font(.headline)

                                 Text(thread.document.name)
                                     .foregroundColor(selectedDocuments.contains(thread.document.id) ? Color.blue : Color.primary)
                                     .lineLimit(1)
                                     .truncationMode(.tail)

                                 Spacer() // Pushes content to the left
                             }
                             .padding()
                             .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading) // Ensures content alignment to the left
                             .background(Color(UIColor.secondarySystemBackground))
                             .cornerRadius(10)
                             .shadow(radius: 2)
                             .contextMenu {
                                 Button(action: {
                                     withAnimation {
                                         toggleSelection(thread.document.id)
                                     }
                                 }) {
                                     Label("Select", systemImage: selectedDocuments.contains(thread.document.id) ? "checkmark.circle.fill" : "circle")
                                 }
                             }
                         }
                         .padding(.vertical, 5)
                     }
                     .buttonStyle(PlainButtonStyle())
                 }
             }
             .listStyle(PlainListStyle())
             .accentColor(.purple)
         }
         .navigationBarTitle("")
         .navigationViewStyle(StackNavigationViewStyle())
         .toolbar {
             ToolbarItemGroup(placement: .navigationBarLeading) {
                 Text(selectedFolder?.name ?? "")
                     .font(.headline)
                     .bold()
             }
             ToolbarItemGroup(placement: .navigationBarTrailing) {
                 
                 if selectedDocuments.isEmpty {
                     Button(action: {
                         showDocumentPicker.toggle()
                     }) {
                         Image(systemName: "plus")
                     }
                     .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                 }
                 if !selectedDocuments.isEmpty {
                     
                     Button(action: {
                         if !selectedDocuments.isEmpty {
                             // Implement your delete logic here
                             // For example, you can show a confirmation alert before deleting
                             showDeleteConfirmationAlert.toggle()
                         }
                     }) {
                         Image(systemName: "trash.circle")
                     }
                     .foregroundColor(Color.red)
                     .disabled(selectedDocuments.isEmpty)

                     
                     Button(action: {
                         if selectedDocuments.count < filteredChatThreads.count {
                             selectAll()
                         }
                         else {
                             deselectAll()
                         }
                     }) {
                         Image(systemName: selectedDocuments.count < filteredChatThreads.count ? "square.stack.fill" : "checkmark.square.fill")
                     }
                     .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                     .disabled(filteredChatThreads.isEmpty)

                     
                     Button(action: {
                         if !selectedDocuments.isEmpty {
                             showMoveDocumentView.toggle()
                         }
                     }) {
                         Image(systemName: "arrow.right.circle")
                     }
                     .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                     .disabled(selectedDocuments.isEmpty)
                     
                     
                 }
             }
         }
         .onAppear {
             fetchDocuments()
             fetchFolders { fetchedFolders in
                 self.folders = fetchedFolders // Populate the folders array
             }

         }
         .sheet(isPresented: $showDocumentPicker) {
             DocumentPicker(
                 alert: self.$alert,
                 documents: self.$documents,
                 completionHandler: { document, errorMessage in
                     if let errorMessage = errorMessage {
                         self.errorMessage = errorMessage
                     }
                     else {
                         // Handle successful document upload if needed

                         let newThread = ChatThread(document: document, chatMessages: [])
                         self.chatThreads.append(newThread)
                         self.chatThreads.sort { $0.document.name.localizedCaseInsensitiveCompare($1.document.name) == .orderedAscending }
                     }
                 }, selectedFolder: self.$selectedFolder
             )
         }
         .alert(isPresented: $alert) {
             if !errorMessage.isEmpty {
                 return Alert(
                     title: Text("Error"),
                     message: Text(errorMessage),
                     dismissButton: .default(Text("Ok")) {
                         errorMessage = ""
                     }
                 )
             }
             else {
                 return Alert(
                     title: Text("Message"),
                     message: Text("Uploaded Successfully"),
                     dismissButton: .default(Text("Ok"))
                 )
             }
         }
         .sheet(isPresented: $showMoveDocumentView, onDismiss: {
             selectedMoveFolder = nil
         }) {
             MoveDocumentView(
                 showMoveDocumentView: $showMoveDocumentView,
                 selectedDocuments: selectedDocuments,
                 availableFolders: folders,
                 selectedFolder: $selectedMoveFolder,
                 moveAction: { folder in
                     moveSelectedDocuments(folder: folder)
                     showMoveDocumentView = false // Close the sheet after moving documents
                 },
                 selectedFolderIndex: $selectedFolderIndex
             )
             .id(UUID()) // Force view refresh
             .onDisappear {
                 isLongPressActive = false // Reset long-press state when sheet is dismissed
             }
         }
         .searchable(text: $searchText, prompt: "Search documents")
         .alert(isPresented: $showDeleteConfirmationAlert) {
             Alert(
                 title: Text("Delete Documents"),
                 message: Text("Are you sure you want to delete the selected documents?"),
                 primaryButton: .default(Text("Cancel")),
                 secondaryButton: .destructive(Text("Delete")) {
                     deleteSelectedDocuments()
                 }
             )
         }
     }
     
     func deleteSelectedDocuments() {
         let db = Firestore.firestore()
         let storageRef = Storage.storage().reference()
         
         for threadIndex in chatThreads.indices {
             if selectedDocuments.contains(chatThreads[threadIndex].document.id) {
                 let document = chatThreads[threadIndex].document
                 
                 // Delete the document from Firestore
                 db.collection("ResearchPapers").document(document.id.uuidString).delete { error in
                     if let error = error {
                         print("Error deleting document from Firestore: \(error)")
                         return
                     }
                     
                     // Delete the document from Firebase Storage
                     let fileRef = storageRef.child(document.url.lastPathComponent)
                     fileRef.delete { error in
                         if let error = error {
                             print("Error deleting document from Firebase Storage: \(error)")
                         }
                         else {
                             // Document successfully deleted from Firestore and Firebase Storage
                             // You can also remove it from the chatThreads array
                             if let indexToDelete = chatThreads.firstIndex(where: { $0.document.id == document.id }) {
                                 chatThreads.remove(at: indexToDelete)
                             }
                             // Clear the selectedDocuments set
                             selectedDocuments.remove(document.id)
                         }
                     }
                 }
             }
         }
     }
     
     // Function to toggle document selection
     func toggleSelection(_ documentID: UUID) {
         if selectedDocuments.contains(documentID) {
             selectedDocuments.remove(documentID)
         } else {
             selectedDocuments.insert(documentID)
         }
     }
     
     // Function to select all documents
     func selectAll() {
         selectedDocuments = Set(filteredChatThreads.map { $0.document.id })
     }
     
     // Function to deselect all documents
     func deselectAll() {
         selectedDocuments.removeAll()
     }

     
     func fetchDocuments() {
         if !didFetch {
             
             let db = Firestore.firestore()
             db.collection("ResearchPapers").getDocuments { (querySnapshot, error) in
                 if let error = error {
                     print("Error getting documents: \(error.localizedDescription)")
                     return
                 }
                 
                 guard let documents = querySnapshot?.documents else {
                     print("No documents found")
                     return
                 }
                 
                 let fetchedDocuments = documents.compactMap { document -> Document? in
                     let data = document.data()
                     guard let name = data["name"] as? String,
                           let urlString = data["url"] as? String,
                           let url = URL(string: urlString),
                           let ID = data["folderID"] as? String,
                           let folderID = UUID(uuidString: ID)
                     else {
                         return nil
                     }
                     return Document(name: name, url: url, folderID: folderID)
                 }
                 
                 
                 updateChatThreads(with: fetchedDocuments)
             }
             didFetch = true
         }
     }
     
     func updateChatThreads(with documents: [Document]) {
         var updatedThreads: [ChatThread] = chatThreads

         for document in documents {
             if document.folderID == selectedFolder?.id {
                 if let existingThreadIndex = updatedThreads.firstIndex(where: { $0.document.id == document.id }) {
                     // Update the existing thread
                     updatedThreads[existingThreadIndex].document = document
                 }
                 else {
                     // Create a new thread only if it doesn't already exist
                     let newThread = ChatThread(document: document, chatMessages: [])
                     updatedThreads.append(newThread)
                 }
             }
         }

         // Sort the updatedThreads array based on the name of the documents
         updatedThreads.sort { $0.document.name.localizedCaseInsensitiveCompare($1.document.name) == .orderedAscending }

         chatThreads = updatedThreads
     }
     
     func moveSelectedDocuments(folder: Folder) {
         let db = Firestore.firestore()

         for threadIndex in chatThreads.indices {
             if selectedDocuments.contains(chatThreads[threadIndex].document.id) {
                 let documentName = chatThreads[threadIndex].document.name

                 // Query Firestore by document name
                 db.collection("ResearchPapers").whereField("name", isEqualTo: documentName).getDocuments { (snapshot, error) in
                     if let error = error {
                         print("Error querying documents: \(error.localizedDescription)")
                         return
                     }

                     guard let document = snapshot?.documents.first else {
                         print("Document not found")
                         return
                     }

                     // Update the folderID of the retrieved document
                     document.reference.updateData([
                         "folderID": folder.id.uuidString
                     ]) { error in
                         if let error = error {
                             print("Error updating folderID in Firestore: \(error)")
                         }
                         else {
                             // Successfully moved documents, update selectedFolder
                             selectedFolder = folder
                         }
                     }
                 }
             }
         }

         selectedDocuments.removeAll()
     }

 }
 

*/













/*
 import SwiftUI
 import MobileCoreServices
 import FirebaseStorage
 import UniformTypeIdentifiers
 import FirebaseFirestore

 struct Document: Identifiable { // Rename here
     let id = UUID()
     let name: String
     let url: URL
     var folderID: UUID
 }

 struct ChatThread: Identifiable {
     let id = UUID()
     var document: Document
     var chatMessages: [ChatMessage]
 }


 struct HomePage: View {
     
     @State private var alert = false
     @State private var chatThreads: [ChatThread] = []
     @State private var documents: [Document] = []
     @State private var errorMessage = ""
     @State private var isLoading = true // New state to manage loading state
     @State private var showDocumentPicker = false
     @State private var searchText = ""
     @State var didFetch = false
     @Binding var selectedFolder: Folder?
     @State private var showMoveDocumentView = false
     @State private var selectedDocument: Document?
     @State private var selectedMoveFolder: Folder?
     @State private var folders: [Folder] = []
     @State private var selectedThread: ChatThread?
     @State private var selectedDocuments: Set<UUID> = []
     @State private var longPressedDocument: Document?
     @State private var isLongPressActive = false // New state for long-press
     @State private var showDeleteConfirmationAlert = false
     @State private var selectedFolderIndex: Int = 0 // Initialize with default selected index

     var filteredChatThreads: [ChatThread] {
         if searchText.isEmpty {
             return chatThreads
         }
         else {
             return chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
         }
     }
     
     var body: some View {
         ZStack {
             List {
                 ForEach(Array(filteredChatThreads.enumerated()), id: \.element.id) { (index, thread) in
                     NavigationLink(destination: DocumentView(documentURL: thread.document.url).transition(.slide)) {
                         HStack {
                             HStack {
                                 Text("\(index + 1).")
                                     .font(.headline)
                                     .padding(.horizontal, 10)
                                 Text(thread.document.name)
                                     .foregroundColor(selectedDocuments.contains(thread.document.id) ? Color.blue : Color.primary)
                                     .lineLimit(1)
                                     .truncationMode(.tail)
                             }
                             .padding()
                             .frame(minWidth: 0, maxWidth: .infinity) // Ensures the HStack takes up the full available width
                             .background(Color(UIColor.secondarySystemBackground))
                             .cornerRadius(10)
                             .shadow(radius: 2)
                             .contextMenu {
                                 Button(action: {
                                     withAnimation {
                                         toggleSelection(thread.document.id)
                                     }
                                 }) {
                                     Label("Select", systemImage: selectedDocuments.contains(thread.document.id) ? "checkmark.circle.fill" : "circle")
                                 }
                             }
                         }
                         .padding(.vertical, 5)
                     }
                     .buttonStyle(PlainButtonStyle())
                 }
             }
             .listStyle(PlainListStyle())
             .accentColor(.purple)
         }
         .navigationBarTitle("")
         .navigationViewStyle(StackNavigationViewStyle())
         .toolbar {
             ToolbarItemGroup(placement: .navigationBarLeading) {
                 Text(selectedFolder?.name ?? "")
                     .font(.headline)
                     .bold()
             }
             ToolbarItemGroup(placement: .navigationBarTrailing) {
                 
                 if selectedDocuments.isEmpty {
                     Button(action: {
                         showDocumentPicker.toggle()
                     }) {
                         Image(systemName: "plus")
                     }
                     .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                 }
                 if !selectedDocuments.isEmpty {
                     
                     Button(action: {
                         if !selectedDocuments.isEmpty {
                             // Implement your delete logic here
                             // For example, you can show a confirmation alert before deleting
                             showDeleteConfirmationAlert.toggle()
                         }
                     }) {
                         Image(systemName: "trash.circle")
                     }
                     .foregroundColor(Color.red)
                     .disabled(selectedDocuments.isEmpty)

                     
                     Button(action: {
                         if selectedDocuments.count < filteredChatThreads.count {
                             selectAll()
                         }
                         else {
                             deselectAll()
                         }
                     }) {
                         Image(systemName: selectedDocuments.count < filteredChatThreads.count ? "square.stack.fill" : "checkmark.square.fill")
                     }
                     .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                     .disabled(filteredChatThreads.isEmpty)

                     
                     Button(action: {
                         if !selectedDocuments.isEmpty {
                             showMoveDocumentView.toggle()
                         }
                     }) {
                         Image(systemName: "arrow.right.circle")
                     }
                     .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                     .disabled(selectedDocuments.isEmpty)
                     
                     
                 }
             }
         }
         .onAppear {
             fetchDocuments()
             fetchFolders { fetchedFolders in
                 self.folders = fetchedFolders // Populate the folders array
             }

         }
         .sheet(isPresented: $showDocumentPicker) {
             DocumentPicker(
                 alert: self.$alert,
                 documents: self.$documents,
                 completionHandler: { document, errorMessage in
                     if let errorMessage = errorMessage {
                         self.errorMessage = errorMessage
                     }
                     else {
                         // Handle successful document upload if needed

                         let newThread = ChatThread(document: document, chatMessages: [])
                         self.chatThreads.append(newThread)
                         self.chatThreads.sort { $0.document.name.localizedCaseInsensitiveCompare($1.document.name) == .orderedAscending }
                     }
                 }, selectedFolder: self.$selectedFolder
             )
         }
         .alert(isPresented: $alert) {
             if !errorMessage.isEmpty {
                 return Alert(
                     title: Text("Error"),
                     message: Text(errorMessage),
                     dismissButton: .default(Text("Ok")) {
                         errorMessage = ""
                     }
                 )
             }
             else {
                 return Alert(
                     title: Text("Message"),
                     message: Text("Uploaded Successfully"),
                     dismissButton: .default(Text("Ok"))
                 )
             }
         }
         .sheet(isPresented: $showMoveDocumentView, onDismiss: {
             selectedMoveFolder = nil
         }) {
             MoveDocumentView(
                 showMoveDocumentView: $showMoveDocumentView,
                 selectedDocuments: selectedDocuments,
                 availableFolders: folders,
                 selectedFolder: $selectedMoveFolder,
                 moveAction: { folder in
                     moveSelectedDocuments(folder: folder)
                     showMoveDocumentView = false // Close the sheet after moving documents
                 },
                 selectedFolderIndex: $selectedFolderIndex
             )
             .id(UUID()) // Force view refresh
             .onDisappear {
                 isLongPressActive = false // Reset long-press state when sheet is dismissed
             }
         }
         .searchable(text: $searchText, prompt: "Search documents")
         .alert(isPresented: $showDeleteConfirmationAlert) {
             Alert(
                 title: Text("Delete Documents"),
                 message: Text("Are you sure you want to delete the selected documents?"),
                 primaryButton: .default(Text("Cancel")),
                 secondaryButton: .destructive(Text("Delete")) {
                     deleteSelectedDocuments()
                 }
             )
         }
     }
     
     func deleteSelectedDocuments() {
         let db = Firestore.firestore()
         let storageRef = Storage.storage().reference()
         
         for threadIndex in chatThreads.indices {
             if selectedDocuments.contains(chatThreads[threadIndex].document.id) {
                 let document = chatThreads[threadIndex].document
                 
                 // Delete the document from Firestore
                 db.collection("ResearchPapers").document(document.id.uuidString).delete { error in
                     if let error = error {
                         print("Error deleting document from Firestore: \(error)")
                         return
                     }
                     
                     // Delete the document from Firebase Storage
                     let fileRef = storageRef.child(document.url.lastPathComponent)
                     fileRef.delete { error in
                         if let error = error {
                             print("Error deleting document from Firebase Storage: \(error)")
                         }
                         else {
                             // Document successfully deleted from Firestore and Firebase Storage
                             // You can also remove it from the chatThreads array
                             if let indexToDelete = chatThreads.firstIndex(where: { $0.document.id == document.id }) {
                                 chatThreads.remove(at: indexToDelete)
                             }
                             // Clear the selectedDocuments set
                             selectedDocuments.remove(document.id)
                         }
                     }
                 }
             }
         }
     }
     
     // Function to toggle document selection
     func toggleSelection(_ documentID: UUID) {
         if selectedDocuments.contains(documentID) {
             selectedDocuments.remove(documentID)
         } else {
             selectedDocuments.insert(documentID)
         }
     }
     
     // Function to select all documents
     func selectAll() {
         selectedDocuments = Set(filteredChatThreads.map { $0.document.id })
     }
     
     // Function to deselect all documents
     func deselectAll() {
         selectedDocuments.removeAll()
     }

     
     func fetchDocuments() {
         if !didFetch {
             
             let db = Firestore.firestore()
             db.collection("ResearchPapers").getDocuments { (querySnapshot, error) in
                 if let error = error {
                     print("Error getting documents: \(error.localizedDescription)")
                     return
                 }
                 
                 guard let documents = querySnapshot?.documents else {
                     print("No documents found")
                     return
                 }
                 
                 let fetchedDocuments = documents.compactMap { document -> Document? in
                     let data = document.data()
                     guard let name = data["name"] as? String,
                           let urlString = data["url"] as? String,
                           let url = URL(string: urlString),
                           let ID = data["folderID"] as? String,
                           let folderID = UUID(uuidString: ID)
                     else {
                         return nil
                     }
                     return Document(name: name, url: url, folderID: folderID)
                 }
                 
                 
                 updateChatThreads(with: fetchedDocuments)
             }
             didFetch = true
         }
     }
     
     func updateChatThreads(with documents: [Document]) {
         var updatedThreads: [ChatThread] = chatThreads

         for document in documents {
             if document.folderID == selectedFolder?.id {
                 if let existingThreadIndex = updatedThreads.firstIndex(where: { $0.document.id == document.id }) {
                     // Update the existing thread
                     updatedThreads[existingThreadIndex].document = document
                 }
                 else {
                     // Create a new thread only if it doesn't already exist
                     let newThread = ChatThread(document: document, chatMessages: [])
                     updatedThreads.append(newThread)
                 }
             }
         }

         // Sort the updatedThreads array based on the name of the documents
         updatedThreads.sort { $0.document.name.localizedCaseInsensitiveCompare($1.document.name) == .orderedAscending }

         chatThreads = updatedThreads
     }
     
     func moveSelectedDocuments(folder: Folder) {
         let db = Firestore.firestore()

         for threadIndex in chatThreads.indices {
             if selectedDocuments.contains(chatThreads[threadIndex].document.id) {
                 let documentName = chatThreads[threadIndex].document.name

                 // Query Firestore by document name
                 db.collection("ResearchPapers").whereField("name", isEqualTo: documentName).getDocuments { (snapshot, error) in
                     if let error = error {
                         print("Error querying documents: \(error.localizedDescription)")
                         return
                     }

                     guard let document = snapshot?.documents.first else {
                         print("Document not found")
                         return
                     }

                     // Update the folderID of the retrieved document
                     document.reference.updateData([
                         "folderID": folder.id.uuidString
                     ]) { error in
                         if let error = error {
                             print("Error updating folderID in Firestore: \(error)")
                         }
                         else {
                             // Successfully moved documents, update selectedFolder
                             selectedFolder = folder
                         }
                     }
                 }
             }
         }

         selectedDocuments.removeAll()
     }

 }
*/












 /*
 import SwiftUI
 import MobileCoreServices
 import FirebaseStorage
 import UniformTypeIdentifiers
 import FirebaseFirestore

 struct Document: Identifiable { // Rename here
     let id = UUID()
     let name: String
     let url: URL
     var folderID: UUID
 }

 struct ChatThread: Identifiable {
     let id = UUID()
     var document: Document
     var chatMessages: [ChatMessage]
 }


 struct HomePage: View {
     
     @State private var alert = false
     @State private var chatThreads: [ChatThread] = []
     @State private var documents: [Document] = []
     @State private var errorMessage = ""
     @State private var isLoading = true // New state to manage loading state
     @State private var showDocumentPicker = false
     @State private var searchText = ""
     @State var didFetch = false
     @Binding var selectedFolder: Folder?
     @State private var showMoveDocumentView = false
     @State private var selectedDocument: Document?
     @State private var selectedMoveFolder: Folder?
     @State private var folders: [Folder] = []
     @State private var selectedThread: ChatThread?
     @State private var selectedDocuments: Set<UUID> = []
     @State private var longPressedDocument: Document?
     @State private var isLongPressActive = false // New state for long-press
     @State private var showDeleteConfirmationAlert = false
     @State private var selectedFolderIndex: Int = 0 // Initialize with default selected index

     var filteredChatThreads: [ChatThread] {
         if searchText.isEmpty {
             return chatThreads
         }
         else {
             return chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
         }
     }
     
     var body: some View {
         ZStack {
             List {
                 ForEach(Array(filteredChatThreads.enumerated()), id: \.element.id) { (index, thread) in
                     NavigationLink(destination: DocumentView(documentURL: thread.document.url)) {
                         HStack {
                             HStack {
                                 Text("\(index + 1).")
                                     .font(.headline)
                                     .padding(.horizontal, 10)
                                 Text(thread.document.name)
                                     .foregroundColor(selectedDocuments.contains(thread.document.id) ? Color.blue : Color(UIColor.label)) // Default text color
                                 
                             }
                             .contextMenu {
                                 Button(action: {
                                     toggleSelection(thread.document.id)
                                 }) {
                                     Label("Select", systemImage: selectedDocuments.contains(thread.document.id) ? "checkmark.circle.fill" : "circle")
                                 }
                             }
                         }
                         .padding(10)
                     }
                 }
             }
         }
         .navigationBarTitle("")
         .navigationViewStyle(StackNavigationViewStyle())
         .toolbar {
             ToolbarItemGroup(placement: .navigationBarLeading) {
                 Text(selectedFolder?.name ?? "")
                     .font(.headline)
                     .bold()
             }
             ToolbarItemGroup(placement: .navigationBarTrailing) {
                 
                 if selectedDocuments.isEmpty {
                     Button(action: {
                         showDocumentPicker.toggle()
                     }) {
                         Image(systemName: "plus")
                     }
                     .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                 }
                 if !selectedDocuments.isEmpty {
                     
                     Button(action: {
                         if !selectedDocuments.isEmpty {
                             // Implement your delete logic here
                             // For example, you can show a confirmation alert before deleting
                             showDeleteConfirmationAlert.toggle()
                         }
                     }) {
                         Image(systemName: "trash.circle")
                     }
                     .foregroundColor(Color.red)
                     .disabled(selectedDocuments.isEmpty)

                     
                     Button(action: {
                         if selectedDocuments.count < filteredChatThreads.count {
                             selectAll()
                         }
                         else {
                             deselectAll()
                         }
                     }) {
                         Image(systemName: selectedDocuments.count < filteredChatThreads.count ? "square.stack.fill" : "checkmark.square.fill")
                     }
                     .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                     .disabled(filteredChatThreads.isEmpty)

                     
                     Button(action: {
                         if !selectedDocuments.isEmpty {
                             showMoveDocumentView.toggle()
                         }
                     }) {
                         Image(systemName: "arrow.right.circle")
                     }
                     .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                     .disabled(selectedDocuments.isEmpty)
                     
                     
                 }
             }
         }
         .onAppear {
             fetchDocuments()
             fetchFolders { fetchedFolders in
                 self.folders = fetchedFolders // Populate the folders array
             }

         }
         .sheet(isPresented: $showDocumentPicker) {
             DocumentPicker(
                 alert: self.$alert,
                 documents: self.$documents,
                 completionHandler: { document, errorMessage in
                     if let errorMessage = errorMessage {
                         self.errorMessage = errorMessage
                     }
                     else {
                         // Handle successful document upload if needed

                         let newThread = ChatThread(document: document, chatMessages: [])
                         self.chatThreads.append(newThread)
                         self.chatThreads.sort { $0.document.name.localizedCaseInsensitiveCompare($1.document.name) == .orderedAscending }
                     }
                 }, selectedFolder: self.$selectedFolder
             )
         }
         .alert(isPresented: $alert) {
             if !errorMessage.isEmpty {
                 return Alert(
                     title: Text("Error"),
                     message: Text(errorMessage),
                     dismissButton: .default(Text("Ok")) {
                         errorMessage = ""
                     }
                 )
             }
             else {
                 return Alert(
                     title: Text("Message"),
                     message: Text("Uploaded Successfully"),
                     dismissButton: .default(Text("Ok"))
                 )
             }
         }
         .sheet(isPresented: $showMoveDocumentView, onDismiss: {
             selectedMoveFolder = nil
         }) {
             MoveDocumentView(
                 showMoveDocumentView: $showMoveDocumentView,
                 selectedDocuments: selectedDocuments,
                 availableFolders: folders,
                 selectedFolder: $selectedMoveFolder,
                 moveAction: { folder in
                     moveSelectedDocuments(folder: folder)
                     showMoveDocumentView = false // Close the sheet after moving documents
                 },
                 selectedFolderIndex: $selectedFolderIndex
             )
             .id(UUID()) // Force view refresh
             .onDisappear {
                 isLongPressActive = false // Reset long-press state when sheet is dismissed
             }
         }
         .searchable(text: $searchText, prompt: "Search documents")
         .alert(isPresented: $showDeleteConfirmationAlert) {
             Alert(
                 title: Text("Delete Documents"),
                 message: Text("Are you sure you want to delete the selected documents?"),
                 primaryButton: .default(Text("Cancel")),
                 secondaryButton: .destructive(Text("Delete")) {
                     deleteSelectedDocuments()
                 }
             )
         }
     }
     
     func deleteSelectedDocuments() {
         let db = Firestore.firestore()
         let storageRef = Storage.storage().reference()
         
         for threadIndex in chatThreads.indices {
             if selectedDocuments.contains(chatThreads[threadIndex].document.id) {
                 let document = chatThreads[threadIndex].document
                 
                 // Delete the document from Firestore
                 db.collection("ResearchPapers").document(document.id.uuidString).delete { error in
                     if let error = error {
                         print("Error deleting document from Firestore: \(error)")
                         return
                     }
                     
                     // Delete the document from Firebase Storage
                     let fileRef = storageRef.child(document.url.lastPathComponent)
                     fileRef.delete { error in
                         if let error = error {
                             print("Error deleting document from Firebase Storage: \(error)")
                         }
                         else {
                             // Document successfully deleted from Firestore and Firebase Storage
                             // You can also remove it from the chatThreads array
                             if let indexToDelete = chatThreads.firstIndex(where: { $0.document.id == document.id }) {
                                 chatThreads.remove(at: indexToDelete)
                             }
                             // Clear the selectedDocuments set
                             selectedDocuments.remove(document.id)
                         }
                     }
                 }
             }
         }
     }
     
     // Function to toggle document selection
     func toggleSelection(_ documentID: UUID) {
         if selectedDocuments.contains(documentID) {
             selectedDocuments.remove(documentID)
         } else {
             selectedDocuments.insert(documentID)
         }
     }
     
     // Function to select all documents
     func selectAll() {
         selectedDocuments = Set(filteredChatThreads.map { $0.document.id })
     }
     
     // Function to deselect all documents
     func deselectAll() {
         selectedDocuments.removeAll()
     }

     
     func fetchDocuments() {
         if !didFetch {
             
             let db = Firestore.firestore()
             db.collection("ResearchPapers").getDocuments { (querySnapshot, error) in
                 if let error = error {
                     print("Error getting documents: \(error.localizedDescription)")
                     return
                 }
                 
                 guard let documents = querySnapshot?.documents else {
                     print("No documents found")
                     return
                 }
                 
                 let fetchedDocuments = documents.compactMap { document -> Document? in
                     let data = document.data()
                     guard let name = data["name"] as? String,
                           let urlString = data["url"] as? String,
                           let url = URL(string: urlString),
                           let ID = data["folderID"] as? String,
                           let folderID = UUID(uuidString: ID)
                     else {
                         return nil
                     }
                     return Document(name: name, url: url, folderID: folderID)
                 }
                 
                 
                 updateChatThreads(with: fetchedDocuments)
             }
             didFetch = true
         }
     }
     
     func updateChatThreads(with documents: [Document]) {
         var updatedThreads: [ChatThread] = chatThreads

         for document in documents {
             if document.folderID == selectedFolder?.id {
                 if let existingThreadIndex = updatedThreads.firstIndex(where: { $0.document.id == document.id }) {
                     // Update the existing thread
                     updatedThreads[existingThreadIndex].document = document
                 }
                 else {
                     // Create a new thread only if it doesn't already exist
                     let newThread = ChatThread(document: document, chatMessages: [])
                     updatedThreads.append(newThread)
                 }
             }
         }

         // Sort the updatedThreads array based on the name of the documents
         updatedThreads.sort { $0.document.name.localizedCaseInsensitiveCompare($1.document.name) == .orderedAscending }

         chatThreads = updatedThreads
     }
     
     func moveSelectedDocuments(folder: Folder) {
         let db = Firestore.firestore()

         for threadIndex in chatThreads.indices {
             if selectedDocuments.contains(chatThreads[threadIndex].document.id) {
                 let documentName = chatThreads[threadIndex].document.name

                 // Query Firestore by document name
                 db.collection("ResearchPapers").whereField("name", isEqualTo: documentName).getDocuments { (snapshot, error) in
                     if let error = error {
                         print("Error querying documents: \(error.localizedDescription)")
                         return
                     }

                     guard let document = snapshot?.documents.first else {
                         print("Document not found")
                         return
                     }

                     // Update the folderID of the retrieved document
                     document.reference.updateData([
                         "folderID": folder.id.uuidString
                     ]) { error in
                         if let error = error {
                             print("Error updating folderID in Firestore: \(error)")
                         }
                         else {
                             // Successfully moved documents, update selectedFolder
                             selectedFolder = folder
                         }
                     }
                 }
             }
         }

         selectedDocuments.removeAll()
     }

 }
 */
