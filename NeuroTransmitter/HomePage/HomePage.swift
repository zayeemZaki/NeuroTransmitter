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
