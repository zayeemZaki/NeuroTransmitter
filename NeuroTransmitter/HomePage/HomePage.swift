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
                Button(action: {
                    showDocumentPicker.toggle()
                }) {
                    Image(systemName: "plus")
                }
                .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                
                if !selectedDocuments.isEmpty {
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
            } else {
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
                 Button(action: {
                     showDocumentPicker.toggle()
                 }) {
                     Image(systemName: "plus")
                 }
                 .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                 
                 if !selectedDocuments.isEmpty {
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
             } else {
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














//import SwiftUI
//import MobileCoreServices
//import FirebaseStorage
//import UniformTypeIdentifiers
//import FirebaseFirestore
//
//struct Document: Identifiable { // Rename here
//    let id = UUID()
//    let name: String
//    let url: URL
//    var folderID: UUID
//}
//
//struct ChatThread: Identifiable {
//    let id = UUID()
//    var document: Document
//    var chatMessages: [ChatMessage]
//}
//
//
//struct HomePage: View {
//
//    @State private var alert = false
//    @State private var chatThreads: [ChatThread] = []
//    @State private var documents: [Document] = []
//    @State private var errorMessage = ""
//    @State private var isLoading = true // New state to manage loading state
//    @State private var showDocumentPicker = false
//    @State private var searchText = ""
//    @State var didFetch = false
//    @Binding var selectedFolder: Folder?
//    @State private var showMoveDocumentView = false
//    @State private var selectedDocument: Document?
//    @State private var selectedMoveFolder: Folder?
//    @State private var folders: [Folder] = [] // Add this line
//    @State private var selectedThread: ChatThread? // Add this line
//    @State private var selectedDocuments: Set<UUID> = []
//    @State private var longPressedDocument: Document?
//    @State private var isLongPressActive = false // New state for long-press
//
//    @State private var selectedFolderIndex: Int = 0 // Initialize with default selected index
//
//    var filteredChatThreads: [ChatThread] {
//        if searchText.isEmpty {
//            return chatThreads
//        } else {
//            return chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
//        }
//    }
//
//    var body: some View {
//        VStack(spacing: 0) { // Use a VStack to eliminate spacing between views
//            searchable(text: $searchText, prompt: "Search documents")
//
//            List {
//                ForEach(Array(filteredChatThreads.enumerated()), id: \.element.id) { (index, thread) in
//                    HStack {
//                        // Checkbox to select/deselect document
//                        if isLongPressActive {
//                            if !selectedDocuments.isEmpty {
//                                Image(systemName: selectedDocuments.contains(thread.document.id) ? "checkmark.square.fill" : "square")
//                                    .onTapGesture {
//                                        toggleSelection(thread.document.id)
//                                    }
//                                    .padding(.trailing, 8)
//                            }
//                        }
//
//                        NavigationLink(destination: DocumentView(documentURL: thread.document.url)) {
//                            HStack {
//                                Text("\(index + 1).")
//                                    .font(.headline)
//                                    .padding(.horizontal, 10)
//                                Text(thread.document.name)
//                            }
//                        }
//                        .padding(10)
//                        .onLongPressGesture {
//                            toggleSelection(thread.document.id) // Toggle document selection
//                            longPressedDocument = thread.document // Set the long-pressed document
//                            isLongPressActive = true // Activate long-press state
//                        }
//                    }
//                }
//            }
//
//        }
//        .navigationBarTitle("")
//        .navigationViewStyle(StackNavigationViewStyle())
//        .toolbar {
//            ToolbarItemGroup(placement: .navigationBarLeading) {
//                Text(selectedFolder?.name ?? "")
//                    .font(.headline)
//                    .bold()
//            }
//            ToolbarItemGroup(placement: .navigationBarTrailing) {
//                Button(action: {
//                    showDocumentPicker.toggle()
//                }) {
//                    Image(systemName: "plus")
//                }
//                .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
//
//                if !selectedDocuments.isEmpty {
//                    Button(action: {
//                        if selectedDocuments.count < filteredChatThreads.count {
//                            selectAll()
//                        } else {
//                            deselectAll()
//                        }
//                    }) {
//                        Image(systemName: selectedDocuments.count < filteredChatThreads.count ? "square.stack.fill" : "checkmark.square.fill")
//                    }
//                    .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
//                    .disabled(filteredChatThreads.isEmpty)
//
//
//                    Button(action: {
//                        if !selectedDocuments.isEmpty {
//                            showMoveDocumentView.toggle()
//                        }
//                    }) {
//                        Image(systemName: "arrow.right.circle")
//                    }
//                    .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
//                    .disabled(selectedDocuments.isEmpty)
//
//                }
//            }
//        }
//        .onAppear {
//            fetchDocuments()
//            fetchFolders { fetchedFolders in
//                self.folders = fetchedFolders // Populate the folders array
//            }
//
//        }
//        .sheet(isPresented: $showDocumentPicker) {
//            DocumentPicker(
//                alert: self.$alert,
//                documents: self.$documents,
//                completionHandler: { document, errorMessage in
//                    if let errorMessage = errorMessage {
//                        self.errorMessage = errorMessage
//                    } else {
//                        // Handle successful document upload if needed
//
//                        let newThread = ChatThread(document: document, chatMessages: [])
//                        self.chatThreads.append(newThread)
//                        self.chatThreads.sort { $0.document.name.localizedCaseInsensitiveCompare($1.document.name) == .orderedAscending }
//                    }
//                }, selectedFolder: self.$selectedFolder
//            )
//        }
//        .alert(isPresented: $alert) {
//            if !errorMessage.isEmpty {
//                return Alert(
//                    title: Text("Error"),
//                    message: Text(errorMessage),
//                    dismissButton: .default(Text("Ok")) {
//                        errorMessage = ""
//                    }
//                )
//            } else {
//                return Alert(
//                    title: Text("Message"),
//                    message: Text("Uploaded Successfully"),
//                    dismissButton: .default(Text("Ok"))
//                )
//            }
//        }
//        .sheet(isPresented: $showMoveDocumentView, onDismiss: {
//            selectedMoveFolder = nil
//        }) {
//            MoveDocumentView(
//                showMoveDocumentView: $showMoveDocumentView,
//                selectedDocuments: selectedDocuments,
//                availableFolders: folders,
//                selectedFolder: $selectedMoveFolder,
//                moveAction: { folder in
//                    moveSelectedDocuments(folder: folder)
//                    showMoveDocumentView = false // Close the sheet after moving documents
//                },
//                selectedFolderIndex: $selectedFolderIndex
//            )
//            .id(UUID()) // Force view refresh
//            .onDisappear {
//                isLongPressActive = false // Reset long-press state when sheet is dismissed
//            }
//        }
//    }
//
//    // Function to toggle document selection
//    func toggleSelection(_ documentID: UUID) {
//        if selectedDocuments.contains(documentID) {
//            selectedDocuments.remove(documentID)
//        } else {
//            selectedDocuments.insert(documentID)
//        }
//    }
//
//    // Function to select all documents
//    func selectAll() {
//        selectedDocuments = Set(filteredChatThreads.map { $0.document.id })
//    }
//
//    // Function to deselect all documents
//    func deselectAll() {
//        selectedDocuments.removeAll()
//    }
//
//
//    func fetchDocuments() {
//        if !didFetch {
//
//            let db = Firestore.firestore()
//            db.collection("ResearchPapers").getDocuments { (querySnapshot, error) in
//                if let error = error {
//                    print("Error getting documents: \(error.localizedDescription)")
//                    return
//                }
//
//                guard let documents = querySnapshot?.documents else {
//                    print("No documents found")
//                    return
//                }
//
//                let fetchedDocuments = documents.compactMap { document -> Document? in
//                    let data = document.data()
//                    guard let name = data["name"] as? String,
//                          let urlString = data["url"] as? String,
//                          let url = URL(string: urlString),
//                          let ID = data["folderID"] as? String,
//                          let folderID = UUID(uuidString: ID)
//                    else {
//                        return nil
//                    }
//                    return Document(name: name, url: url, folderID: folderID)
//                }
//
//
//                updateChatThreads(with: fetchedDocuments)
//            }
//            didFetch = true
//        }
//    }
//
//    func updateChatThreads(with documents: [Document]) {
//        var updatedThreads: [ChatThread] = chatThreads
//
//        for document in documents {
//            if document.folderID == selectedFolder?.id {
//                if let existingThreadIndex = updatedThreads.firstIndex(where: { $0.document.id == document.id }) {
//                    // Update the existing thread
//                    updatedThreads[existingThreadIndex].document = document
//                } else {
//                    // Create a new thread only if it doesn't already exist
//                    let newThread = ChatThread(document: document, chatMessages: [])
//                    updatedThreads.append(newThread)
//                }
//            }
//        }
//
//        // Sort the updatedThreads array based on the name of the documents
//        updatedThreads.sort { $0.document.name.localizedCaseInsensitiveCompare($1.document.name) == .orderedAscending }
//
//        chatThreads = updatedThreads
//    }
//
//    func moveSelectedDocuments(folder: Folder) {
//        let db = Firestore.firestore()
//
//        for threadIndex in chatThreads.indices {
//            if selectedDocuments.contains(chatThreads[threadIndex].document.id) {
//                let documentName = chatThreads[threadIndex].document.name
//
//                // Query Firestore by document name
//                db.collection("ResearchPapers").whereField("name", isEqualTo: documentName).getDocuments { (snapshot, error) in
//                    if let error = error {
//                        print("Error querying documents: \(error.localizedDescription)")
//                        return
//                    }
//
//                    guard let document = snapshot?.documents.first else {
//                        print("Document not found")
//                        return
//                    }
//
//                    // Update the folderID of the retrieved document
//                    document.reference.updateData([
//                        "folderID": folder.id.uuidString
//                    ]) { error in
//                        if let error = error {
//                            print("Error updating folderID in Firestore: \(error)")
//                        } else {
//                            // Successfully moved documents, update selectedFolder
//                            selectedFolder = folder
//                        }
//                    }
//                }
//            }
//        }
//
//        selectedDocuments.removeAll()
//    }
//
//}









 







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
     @State private var folders: [Folder] = [] // Add this line
     @State private var selectedThread: ChatThread? // Add this line
     @State private var selectedDocuments: Set<UUID> = []
     @State private var longPressedDocument: Document?
     @State private var isLongPressActive = false // New state for long-press

     @State private var selectedFolderIndex: Int = 0 // Initialize with default selected index

     var filteredChatThreads: [ChatThread] {
         if searchText.isEmpty {
             return chatThreads
         } else {
             return chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
         }
     }
     
     var body: some View {
         List {
             ForEach(Array(filteredChatThreads.enumerated()), id: \.element.id) { (index, thread) in
                 HStack {
                     // Checkbox to select/deselect document
                     if isLongPressActive {
                         if !selectedDocuments.isEmpty {
                             Image(systemName: selectedDocuments.contains(thread.document.id) ? "checkmark.square.fill" : "square")
                                 .onTapGesture {
                                     toggleSelection(thread.document.id)
                                 }
                                 .padding(.trailing, 8)
                         }
                     }
                     
                     NavigationLink(destination: DocumentView(documentURL: thread.document.url)) {
                         HStack {
                             Text("\(index + 1).")
                                 .font(.headline)
                                 .padding(.horizontal, 10)
                             Text(thread.document.name)
                         }
                     }
                     .padding(10)
                     .onLongPressGesture {
                         toggleSelection(thread.document.id) // Toggle document selection
                         longPressedDocument = thread.document // Set the long-pressed document
                         isLongPressActive = true // Activate long-press state
                     }
                 }
             }
         }
         .navigationBarTitle("")
         .navigationViewStyle(StackNavigationViewStyle())
         .toolbar {
             ToolbarItemGroup(placement: .navigationBarLeading) {
                 Text("Research Papers")
                     .font(.headline)
                     .bold()
             }
             ToolbarItemGroup(placement: .navigationBarTrailing) {
                 Button(action: {
                     showDocumentPicker.toggle()
                 }) {
                     Image(systemName: "plus")
                 }
                 .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                 
                 Button(action: {
                     selectedDocuments.isEmpty ? selectAll() : deselectAll()
                 }) {
                     Image(systemName: selectedDocuments.isEmpty ? "square.stack.fill" : "checkmark.square.fill")
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
                     } else {
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
             } else {
                 return Alert(
                     title: Text("Message"),
                     message: Text("Uploaded Successfully"),
                     dismissButton: .default(Text("Ok"))
                 )
             }
         }
         .searchable(text: $searchText, prompt: "Search documents")
         .sheet(isPresented: $showMoveDocumentView) {
             MoveDocumentView(
                 showMoveDocumentView: $showMoveDocumentView,
                 selectedDocuments: selectedDocuments,
                 availableFolders: folders,
                 selectedFolder: $selectedMoveFolder,
                 moveAction: { folder in
                     moveSelectedDocuments(folder: folder)
                 },
                 selectedFolderIndex: $selectedFolderIndex
             )
             .id(UUID()) // Force view refresh
             .onDisappear {
                 isLongPressActive = false // Reset long-press state when sheet is dismissed
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
                 } else {
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
     @State private var folders: [Folder] = [] // Add this line
     @State private var selectedThread: ChatThread? // Add this line
     @State private var selectedDocuments: Set<UUID> = []
     @State private var longPressedDocument: Document?
     @State private var isLongPressActive = false // New state for long-press

     @State private var selectedFolderIndex: Int = 0 // Initialize with default selected index

     var filteredChatThreads: [ChatThread] {
         if searchText.isEmpty {
             return chatThreads
         } else {
             return chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
         }
     }
     
     var body: some View {
         List {
             ForEach(Array(filteredChatThreads.enumerated()), id: \.element.id) { (index, thread) in
                 HStack {
                     // Checkbox to select/deselect document
                     if isLongPressActive {
                         Image(systemName: selectedDocuments.contains(thread.document.id) ? "checkmark.square.fill" : "square")
                             .onTapGesture {
                                 toggleSelection(thread.document.id)
                             }
                             .padding(.trailing, 8)
                     }
                     
                     NavigationLink(destination: DocumentView(documentURL: thread.document.url)) {
                         HStack {
                             Text("\(index + 1).")
                                 .font(.headline)
                                 .padding(.horizontal, 10)
                             Text(thread.document.name)
                         }
                     }
                     .padding(10)
                     .onLongPressGesture {
                         toggleSelection(thread.document.id) // Toggle document selection
                         longPressedDocument = thread.document // Set the long-pressed document
                         isLongPressActive = true // Activate long-press state
                     }
                 }
             }
         }
         .navigationBarTitle("")
         .navigationViewStyle(StackNavigationViewStyle())
         .toolbar {
             ToolbarItemGroup(placement: .navigationBarLeading) {
                 Text("Research Papers")
                     .font(.headline)
                     .bold()
             }
             ToolbarItemGroup(placement: .navigationBarTrailing) {
                 Button(action: {
                     showDocumentPicker.toggle()
                 }) {
                     Image(systemName: "plus")
                 }
                 .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                 
                 Button(action: {
                     selectedDocuments.isEmpty ? selectAll() : deselectAll()
                 }) {
                     Image(systemName: selectedDocuments.isEmpty ? "square.stack.fill" : "checkmark.square.fill")
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
                     } else {
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
             } else {
                 return Alert(
                     title: Text("Message"),
                     message: Text("Uploaded Successfully"),
                     dismissButton: .default(Text("Ok"))
                 )
             }
         }
         .searchable(text: $searchText, prompt: "Search documents")
         .sheet(isPresented: $showMoveDocumentView) {
             MoveDocumentView(
                 showMoveDocumentView: $showMoveDocumentView,
                 selectedDocuments: selectedDocuments,
                 availableFolders: folders,
                 selectedFolder: $selectedMoveFolder,
                 moveAction: { folder in
                     moveSelectedDocuments(folder: folder)
                 },
                 selectedFolderIndex: $selectedFolderIndex
             )
             .id(UUID()) // Force view refresh
             .onDisappear {
                 isLongPressActive = false // Reset long-press state when sheet is dismissed
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
                 } else {
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
     @State private var folders: [Folder] = [] // Add this line
     @State private var selectedThread: ChatThread? // Add this line
     @State private var selectedDocuments: Set<UUID> = []
     @State private var longPressedDocument: Document?

     @State private var selectedFolderIndex: Int = 0 // Initialize with default selected index

     var filteredChatThreads: [ChatThread] {
         if searchText.isEmpty {
             return chatThreads
         } else {
             return chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
         }
     }
     
     var body: some View {
         List {
             ForEach(Array(filteredChatThreads.enumerated()), id: \.element.id) { (index, thread) in
                 HStack {
                     // Checkbox to select/deselect document
                     Image(systemName: selectedDocuments.contains(thread.document.id) ? "checkmark.square.fill" : "square")
                         .onTapGesture {
                             toggleSelection(thread.document.id)
                         }
                         .padding(.trailing, 8)
                     
                     NavigationLink(destination: DocumentView(documentURL: thread.document.url)) {
                         HStack {
                             Text("\(index + 1).")
                                 .font(.headline)
                                 .padding(.horizontal, 10)
                             Text(thread.document.name)
                         }
                     }
                     .padding(10)
                     .onLongPressGesture {
                         longPressedDocument = thread.document // Set the long-pressed document
                     }
                 }
             }
         }
         .navigationBarTitle("")
         .navigationViewStyle(StackNavigationViewStyle())
         .toolbar {
             ToolbarItemGroup(placement: .navigationBarLeading) {
                 Text("Research Papers")
                     .font(.headline)
                     .bold()
             }
             ToolbarItemGroup(placement: .navigationBarTrailing) {
                 Button(action: {
                     showDocumentPicker.toggle()
                 }) {
                     Image(systemName: "plus")
                 }
                 .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                 
                 Button(action: {
                     selectedDocuments.isEmpty ? selectAll() : deselectAll()
                 }) {
                     Image(systemName: selectedDocuments.isEmpty ? "square.stack.fill" : "checkmark.square.fill")
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
                     } else {
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
             } else {
                 return Alert(
                     title: Text("Message"),
                     message: Text("Uploaded Successfully"),
                     dismissButton: .default(Text("Ok"))
                 )
             }
         }
         .searchable(text: $searchText, prompt: "Search documents")
         .sheet(isPresented: $showMoveDocumentView) {
             MoveDocumentView(
                 showMoveDocumentView: $showMoveDocumentView,
                 selectedDocuments: selectedDocuments,
                 availableFolders: folders,
                 selectedFolder: $selectedMoveFolder,
                 moveAction: { folder in
                   moveSelectedDocuments(folder: folder)
                 }, selectedFolderIndex: $selectedFolderIndex
             )
             .id(UUID()) // Force view refresh
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
                 } else {
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
     @State private var folders: [Folder] = [] // Add this line
     @State private var selectedThread: ChatThread? // Add this line
     @State private var selectedDocuments: Set<UUID> = []
     @State private var longPressedDocument: Document?

     @State private var selectedFolderIndex: Int = 0 // Initialize with default selected index

     var filteredChatThreads: [ChatThread] {
         if searchText.isEmpty {
             return chatThreads
         } else {
             return chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
         }
     }
     
     var body: some View {
         List {
             ForEach(Array(filteredChatThreads.enumerated()), id: \.element.id) { (index, thread) in
                 HStack {
                     // Checkbox to select/deselect document
                     Image(systemName: selectedDocuments.contains(thread.document.id) ? "checkmark.square.fill" : "square")
                         .onTapGesture {
                             toggleSelection(thread.document.id)
                         }
                         .padding(.trailing, 8)
                     
                     NavigationLink(destination: DocumentView(documentURL: thread.document.url)) {
                         HStack {
                             Text("\(index + 1).")
                                 .font(.headline)
                                 .padding(.horizontal, 10)
                             Text(thread.document.name)
                         }
                     }
                     .padding(10)
                     .onLongPressGesture {
                         longPressedDocument = thread.document // Set the long-pressed document
                     }
                 }
             }
         }
         .navigationBarTitle("")
         .navigationViewStyle(StackNavigationViewStyle())
         .toolbar {
             ToolbarItemGroup(placement: .navigationBarLeading) {
                 Text("Research Papers")
                     .font(.headline)
                     .bold()
             }
             ToolbarItemGroup(placement: .navigationBarTrailing) {
                 Button(action: {
                     showDocumentPicker.toggle()
                 }) {
                     Image(systemName: "plus")
                 }
                 .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                 
                 Button(action: {
                     selectedDocuments.isEmpty ? selectAll() : deselectAll()
                 }) {
                     Image(systemName: selectedDocuments.isEmpty ? "square.stack.fill" : "checkmark.square.fill")
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
                     } else {
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
             } else {
                 return Alert(
                     title: Text("Message"),
                     message: Text("Uploaded Successfully"),
                     dismissButton: .default(Text("Ok"))
                 )
             }
         }
         .searchable(text: $searchText, prompt: "Search documents")
         .sheet(isPresented: $showMoveDocumentView) {
             MoveDocumentView(
                 showMoveDocumentView: $showMoveDocumentView,
                 selectedDocuments: selectedDocuments,
                 availableFolders: folders,
                 selectedFolder: $selectedMoveFolder,
                 moveAction: { folder in
                     moveSelectedDocuments(to: folder)
                 }, selectedFolderIndex: $selectedFolderIndex
             )
             .id(UUID()) // Force view refresh
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
                 } else {
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
     
     func moveSelectedDocuments(to folder: Folder) {
         let db = Firestore.firestore()

         for threadIndex in chatThreads.indices {
             if selectedDocuments.contains(chatThreads[threadIndex].document.id) {
                 var updatedDocument = chatThreads[threadIndex].document
                 updatedDocument.folderID = folder.id
                 chatThreads[threadIndex].document = updatedDocument
                 print("1")
                 // Update Firestore with the new folder ID
                 db.collection("ResearchPapers").document(updatedDocument.id.uuidString).updateData([
                     "folderID": folder.id.uuidString
                 ]) { error in
                     if let error = error {
                         print("Error updating folderID in Firestore: \(error)")
                     }
                 }
             }
             print("2")

         }
         print("3")

         selectedDocuments.removeAll()
     }


 }

 struct MoveDocumentView: View {
     @Binding var showMoveDocumentView: Bool
     let selectedDocuments: Set<UUID>
     let availableFolders: [Folder]
     @Binding var selectedFolder: Folder?
     let moveAction: (Folder) -> Void
     
     @Binding var selectedFolderIndex: Int // Add this
     
     var body: some View {
         NavigationView {
             VStack {
                 Picker("Select Folder", selection: $selectedFolderIndex) {
                     ForEach(availableFolders.indices) { index in
                         Text(availableFolders[index].name).tag(index)
                     }
                 }
                 .pickerStyle(.wheel)
                 .padding()
                 
                 Button("Move Documents") {
                     if selectedFolderIndex >= 0 && selectedFolderIndex < availableFolders.count {
                         let selectedFolder = availableFolders[selectedFolderIndex]
                         print("Button tapped - selected folder: \(selectedFolder)")
                         moveAction(selectedFolder)
                     } else {
                         print("Selected folder is nil.")
                     }
                     showMoveDocumentView = false
                 }
                 .padding()
                 .background(Color.blue)
                 .foregroundColor(.white)
                 .cornerRadius(10)
             }
             .navigationBarTitle("Move Documents", displayMode: .inline)
             .navigationBarItems(trailing: Button("Cancel") {
                 showMoveDocumentView = false
             })
         }
     }
 }



     

 struct FolderListView: View {
     @State private var folders: [Folder] = []
     @State private var selectedFolder: Folder? = nil
     @State private var newFolderName = ""
     @State private var showFolderCreationPopover = false
     @State private var searchText = ""

     var body: some View {
         ZStack {
             List(folders.filter { searchText.isEmpty ? true : $0.name.localizedCaseInsensitiveContains(searchText) }) { folder in
                 NavigationLink(destination: HomePage(selectedFolder: $selectedFolder), tag: folder, selection: $selectedFolder) {
                     HStack {
                         Text(folder.name)
                             .font(.headline)
                         Spacer()
                     }
                 }
                 .padding(10)
             }
         }
         .navigationBarTitle("")
         .navigationViewStyle(StackNavigationViewStyle())
         .toolbar {
             ToolbarItem(placement: .navigationBarLeading) {
                 Text("Folders")
                     .font(.largeTitle)
                     .bold()
                     .padding(10)
             }
             ToolbarItem(placement: .navigationBarTrailing) {
                 Button(action: {
                     showFolderCreationPopover.toggle()
                 }) {
                     Image(systemName: "folder.badge.plus")
                 }
                 .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
             }
             ToolbarItem(placement: .navigationBarTrailing) {
                 NavigationLink(destination: Profile()) {
                     Image(systemName: "person.fill")
                 }
                 .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
             }
         }
         .popover(isPresented: $showFolderCreationPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
             GeometryReader { geometry in
                 VStack(spacing: 20) {
                     Text("Create New Folder")
                         .font(.title)
                         .bold()

                     TextField("Folder Name", text: $newFolderName)
                         .padding()
                         .textFieldStyle(RoundedBorderTextFieldStyle())
                         .autocapitalization(.none)
                         .disableAutocorrection(true)

                     Button(action: {
                         createFolder()
                         showFolderCreationPopover.toggle()
                     }) {
                         Text("Create Folder")
                             .padding()
                             .frame(maxWidth: .infinity)
                             .background(Color(red: 0.2, green: 0.5, blue: 0.3))
                             .foregroundColor(.white)
                             .cornerRadius(10)
                     }
                 }
                 .padding()
                 .cornerRadius(20)
                 .shadow(radius: 5)
                 .frame(width: geometry.size.width * 0.8, height: geometry.size.height * 0.6) // Adjust the size as needed
                 .position(x: geometry.size.width / 2, y: geometry.size.height / 2) // Center position
             }
         }

         .onAppear {
             fetchFolders { fetchedFolders in
                 self.folders = fetchedFolders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
             }
         }
         .searchable(text: $searchText, prompt: "Search folders")
     }
     
     

     func createFolder() {
         let db = Firestore.firestore()
         let newFolderId = UUID()

         let newFolderData: [String: Any] = [
             "name": newFolderName,
             "folderId": newFolderId.uuidString
         ]

         db.collection("Folders").addDocument(data: newFolderData) { error in
             if let error = error {
                 print("Error creating folder: \(error.localizedDescription)")
                 return
             }

             let newFolder = Folder(id: newFolderId, name: newFolderName)

             // Find the insertion index based on alphabetical order
             if let insertionIndex = self.folders.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(newFolder.name) == .orderedDescending }) {
                 self.folders.insert(newFolder, at: insertionIndex)
             } else {
                 self.folders.append(newFolder)
             }
         }
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
     @State private var folders: [Folder] = [] // Add this line
     @State private var selectedThread: ChatThread? // Add this line
     @State private var selectedDocuments: Set<UUID> = []
     @State private var longPressedDocument: Document?


     var filteredChatThreads: [ChatThread] {
         if searchText.isEmpty {
             return chatThreads
         } else {
             return chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
         }
     }
     
     var body: some View {
         List {
             ForEach(Array(filteredChatThreads.enumerated()), id: \.element.id) { (index, thread) in
                 HStack {
                     // Checkbox to select/deselect document
                     Image(systemName: selectedDocuments.contains(thread.document.id) ? "checkmark.square.fill" : "square")
                         .onTapGesture {
                             toggleSelection(thread.document.id)
                         }
                         .padding(.trailing, 8)
                     
                     NavigationLink(destination: DocumentView(documentURL: thread.document.url)) {
                         HStack {
                             Text("\(index + 1).")
                                 .font(.headline)
                                 .padding(.horizontal, 10)
                             Text(thread.document.name)
                         }
                     }
                     .padding(10)
                     .onLongPressGesture {
                         longPressedDocument = thread.document // Set the long-pressed document
                     }
                 }
             }
         }
         .navigationBarTitle("")
         .navigationViewStyle(StackNavigationViewStyle())
         .toolbar {
             ToolbarItemGroup(placement: .navigationBarLeading) {
                 Text("Research Papers")
                     .font(.headline)
                     .bold()
             }
             ToolbarItemGroup(placement: .navigationBarTrailing) {
                 Button(action: {
                     showDocumentPicker.toggle()
                 }) {
                     Image(systemName: "plus")
                 }
                 .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))

                 if let longPressedDocument = longPressedDocument {
                     Button(action: {
                         showMoveDocumentView.toggle()
                     }) {
                         Image(systemName: "arrow.right.square")
                     }
                     .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                     .disabled(selectedThread == nil) // Disable if no thread is selected
                 }
                 
                 Button(action: {
                     selectedDocuments.isEmpty ? selectAll() : deselectAll()
                 }) {
                     Image(systemName: selectedDocuments.isEmpty ? "square.stack.fill" : "checkmark.square.fill")
                 }
                 .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                 .disabled(filteredChatThreads.isEmpty)


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
                     } else {
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
             } else {
                 return Alert(
                     title: Text("Message"),
                     message: Text("Uploaded Successfully"),
                     dismissButton: .default(Text("Ok"))
                 )
             }
         }
         .searchable(text: $searchText, prompt: "Search documents")
         .sheet(isPresented: $showMoveDocumentView) {
             if let selectedDocument = selectedDocument {
                 MoveDocumentView(
                     showMoveDocumentView: $showMoveDocumentView,
                     document: selectedDocument,
                     availableFolders: folders, // Use the 'folders' array here
                     selectedFolder: $selectedMoveFolder
                 ) { folderID in
                     moveDocument(selectedDocument, to: folderID)
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
                 } else {
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
     
     func moveDocument(_ document: Document, to folderID: UUID) {
         if let index = chatThreads.firstIndex(where: { $0.document.id == document.id }) {
             var updatedThread = chatThreads[index]
             updatedThread.document.folderID = folderID
             chatThreads[index] = updatedThread

             // If you want to update Firestore with the new folder ID, add code here

             selectedMoveFolder = nil
         }
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

     var filteredChatThreads: [ChatThread] {
         if searchText.isEmpty {
             return chatThreads
         } else {
             return chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
         }
     }
     
     var body: some View {
         List {
             ForEach(Array(filteredChatThreads.enumerated()), id: \.element.id) { (index, thread) in
                 NavigationLink(destination: DocumentView(documentURL: thread.document.url)) {
                     HStack {
                         Text("\(index + 1).")
                             .font(.headline)
                             .padding(.horizontal, 10)
                         Text(thread.document.name)
                     }
                 }
                 .padding(10)
             }
         }
         .navigationBarTitle("")
         .navigationViewStyle(StackNavigationViewStyle())
         .toolbar {
             ToolbarItemGroup(placement: .navigationBarLeading) {
                 Text("Research Papers")
                     .font(.largeTitle)
                     .bold()
             }
             ToolbarItemGroup(placement: .navigationBarTrailing) {
                 Button(action: {
                     showDocumentPicker.toggle()
                 }) {
                     Image(systemName: "plus")
                 }
                 .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
             }
         }
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
                     } else {
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
             } else {
                 return Alert(
                     title: Text("Message"),
                     message: Text("Uploaded Successfully"),
                     dismissButton: .default(Text("Ok"))
                 )
             }
         }
         .searchable(text: $searchText, prompt: "Search documents")
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
                 } else {
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

     var filteredChatThreads: [ChatThread] {
         if searchText.isEmpty {
             return chatThreads
         } else {
             return chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
         }
     }
     
     var body: some View {
         List {
             ForEach(Array(filteredChatThreads.enumerated()), id: \.element.id) { (index, thread) in
                 NavigationLink(destination: DocumentView(documentURL: thread.document.url)) {
                     HStack {
                         Text("\(index + 1).")
                             .font(.headline)
                             .padding(.horizontal, 10)
                         Text(thread.document.name)
                     }
                 }
                 .padding(10)
             }
         }
         .navigationBarTitle("")
         .navigationViewStyle(StackNavigationViewStyle())
         .toolbar {
             ToolbarItemGroup(placement: .navigationBarLeading) {
                 Text("Research Papers")
                     .font(.largeTitle)
                     .bold()
             }
             ToolbarItemGroup(placement: .navigationBarTrailing) {
                 Button(action: {
                     showDocumentPicker.toggle()
                 }) {
                     Image(systemName: "plus")
                 }
                 .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
             }
         }
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
                     } else {
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
             } else {
                 return Alert(
                     title: Text("Message"),
                     message: Text("Uploaded Successfully"),
                     dismissButton: .default(Text("Ok"))
                 )
             }
         }
         .searchable(text: $searchText, prompt: "Search documents")
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
                 } else {
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
     
     @Binding var selectedFolder: Folder?

     var filteredChatThreads: [ChatThread] {
         if searchText.isEmpty {
             return chatThreads
         } else {
             return chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
         }
     }
     
     var body: some View {
         List {
             ForEach(Array(filteredChatThreads.enumerated()), id: \.element.id) { (index, thread) in
                 NavigationLink(destination: DocumentView(documentURL: thread.document.url)) {
                     HStack {
                         Text("\(index + 1).")
                             .font(.headline)
                             .padding(.horizontal, 10)
                         Text(thread.document.name)
                     }
                 }
                 .padding(10)
             }
         }
         .navigationBarTitle("")
         .navigationViewStyle(StackNavigationViewStyle())
         .toolbar {
             ToolbarItemGroup(placement: .navigationBarLeading) {
                 Text("Research Papers")
                     .font(.largeTitle)
                     .bold()
             }
             ToolbarItemGroup(placement: .navigationBarTrailing) {
                 Button(action: {
                     showDocumentPicker.toggle()
                 }) {
                     Image(systemName: "plus")
                 }
                 .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
             }
         }
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
                     } else {
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
             } else {
                 return Alert(
                     title: Text("Message"),
                     message: Text("Uploaded Successfully"),
                     dismissButton: .default(Text("Ok"))
                 )
             }
         }
         .searchable(text: $searchText, prompt: "Search documents")
     }


     func fetchDocuments() {
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
     }
     
     func updateChatThreads(with documents: [Document]) {
         var updatedThreads: [ChatThread] = chatThreads

         for document in documents {
             if document.folderID == selectedFolder?.id {
                 if let existingThreadIndex = chatThreads.firstIndex(where: { $0.document.id == document.id }) {
                     updatedThreads[existingThreadIndex].document = document
                 } else {
                     let newThread = ChatThread(document: document, chatMessages: [])
                     updatedThreads.append(newThread)
                 }
             }
         }

         // Sort the updatedThreads array based on the name of the documents
         updatedThreads.sort { $0.document.name.localizedCaseInsensitiveCompare($1.document.name) == .orderedAscending }

         chatThreads = updatedThreads
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
     let document: Document
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
     
     @Binding var selectedFolder: Folder?

     var filteredChatThreads: [ChatThread] {
         if searchText.isEmpty {
             return chatThreads
         } else {
             return chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
         }
     }
     
     var body: some View {
         List {
             ForEach(Array(filteredChatThreads.enumerated()), id: \.element.id) { (index, thread) in
                 NavigationLink(destination: DocumentView(documentURL: thread.document.url)) {
                     HStack {
                         Text("\(index + 1).")
                             .font(.headline)
                             .padding(.horizontal, 10)
                         Text(thread.document.name)
                     }
                 }
                     .padding(10)
             }
         }
         .navigationBarTitle("")
         .navigationViewStyle(StackNavigationViewStyle())
         .toolbar {
             ToolbarItemGroup(placement: .navigationBarLeading) {
                 Text("Research Papers")
                     .font(.largeTitle)
                     .bold()
                     .padding(10)
             }
             ToolbarItemGroup(placement: .navigationBarTrailing) {
                 Button(action: {
                     showDocumentPicker.toggle()
                 }) {
                     Image(systemName: "plus")
                 }
                 .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
             }
         }
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
                     } else {
                         // Handle successful document upload if needed
                         
                         let newThread = ChatThread(document: document, chatMessages: [])
                         self.chatThreads.append(newThread)
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
             } else {
                 return Alert(
                     title: Text("Message"),
                     message: Text("Uploaded Successfully"),
                     dismissButton: .default(Text("Ok"))
                 )
             }
         }
         .searchable(text: $searchText, prompt: "Search documents")
     }


     func fetchDocuments() {
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
     }
     
     func updateChatThreads(with documents: [Document]) {
         var updatedThreads: [ChatThread] = []
         for document in documents {
             if document.folderID == selectedFolder?.id {
                 if let existingThread = chatThreads.first(where: { $0.document.id == document.id }) {
                     updatedThreads.append(existingThread)
                 } else {
                     let newThread = ChatThread(document: document, chatMessages: [])
                     updatedThreads.append(newThread)
                 }
             }
         }

         chatThreads = updatedThreads
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
     let document: Document
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
     
     @Binding var selectedFolder: Folder?

     var filteredChatThreads: [ChatThread] {
         if searchText.isEmpty {
             return chatThreads
         } else {
             return chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
         }
     }
     
     var body: some View {
         List {
             ForEach(Array(filteredChatThreads.enumerated()), id: \.element.id) { (index, thread) in
                 NavigationLink(destination: DocumentView(documentURL: thread.document.url)) {
                     HStack {
                         Text("\(index + 1).")
                             .font(.headline)
                             .padding(.horizontal, 10)
                         Text(thread.document.name)
                     }
                 }
                     .padding(10)
             }
         }
         .navigationBarTitle("")
         .navigationViewStyle(StackNavigationViewStyle())
         .toolbar {
             ToolbarItemGroup(placement: .navigationBarLeading) {
                 Text("Research Papers")
                     .font(.largeTitle)
                     .bold()
                     .padding(10)
             }
             ToolbarItemGroup(placement: .navigationBarTrailing) {
                 Button(action: {
                     showDocumentPicker.toggle()
                 }) {
                     Image(systemName: "plus")
                 }
                 .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
             }
         }
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
                     } else {
                         // Handle successful document upload if needed
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
             } else {
                 return Alert(
                     title: Text("Message"),
                     message: Text("Uploaded Successfully"),
                     dismissButton: .default(Text("Ok"))
                 )
             }
         }
         .searchable(text: $searchText, prompt: "Search documents")
     }


     func fetchDocuments() {
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
     }
     
     func updateChatThreads(with documents: [Document]) {
         var updatedThreads: [ChatThread] = []
       //  print(document.folderID)
       //  print(selectedFolder?.id)
         for document in documents {
             if document.folderID == selectedFolder?.id {
                 if let existingThread = chatThreads.first(where: { $0.document.id == document.id }) {
                     updatedThreads.append(existingThread)
                 } else {
                     let newThread = ChatThread(document: document, chatMessages: [])
                     updatedThreads.append(newThread)
                 }
             }
         }

         chatThreads = updatedThreads
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
     let document: Document
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
     
     @Binding var selectedFolder: Folder?

     var filteredChatThreads: [ChatThread] {
         if searchText.isEmpty {
             return chatThreads
         } else {
             return chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
         }
     }
     
     var body: some View {
         ZStack {
             VStack {
                 List {
                     ForEach(Array(filteredChatThreads.enumerated()), id: \.element.id) { (index, thread) in
                         NavigationLink(destination: DocumentView(documentURL: thread.document.url)) {
                             HStack {
                                 Text("\(index + 1).")
                                     .font(.headline)
                                     .padding(10)
                                 Text(thread.document.name)
                             }
                             .padding(.vertical, 8)
                         }
                     }
                 }
                 .searchable(text: $searchText, prompt: "Search documents")
                 .onSubmit(of: .search) {
                     // Handle search submission if needed
                 }
                 .toolbar {
                     ToolbarItemGroup(placement: .navigationBarLeading) {
                         Text("Research Papers")
                             .font(.largeTitle)
                     }
                     ToolbarItemGroup(placement: .navigationBarTrailing) {
                         Button(action: {
                             showDocumentPicker.toggle()
                         }) {
                             Image(systemName: "plus")
                         }
                         .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                         
                     }
                     
                 }
             }
         }
         .navigationBarTitle("")
         .navigationViewStyle(StackNavigationViewStyle())
         .accentColor(.blue)
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
                     } else {
                         // Handle successful document upload if needed
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
     }
     
     
     func fetchDocuments() {
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
     }
     
     func updateChatThreads(with documents: [Document]) {
         var updatedThreads: [ChatThread] = []
       //  print(document.folderID)
       //  print(selectedFolder?.id)
         for document in documents {
             if document.folderID == selectedFolder?.id {
                 if let existingThread = chatThreads.first(where: { $0.document.id == document.id }) {
                     updatedThreads.append(existingThread)
                 } else {
                     let newThread = ChatThread(document: document, chatMessages: [])
                     updatedThreads.append(newThread)
                 }
             }
         }

         chatThreads = updatedThreads
     }
 }
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
     let document: Document
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
     
     @Binding var selectedFolder: Folder?

     var filteredChatThreads: [ChatThread] {
         if searchText.isEmpty {
             return chatThreads
         } else {
             return chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
         }
     }
     
     var body: some View {
         ZStack {
             VStack {
                 List {
                     ForEach(Array(filteredChatThreads.enumerated()), id: \.element.id) { (index, thread) in
                         NavigationLink(destination: DocumentView(documentURL: thread.document.url)) {
                             HStack {
                                 Text("\(index + 1).")
                                     .font(.headline)
                                     .padding(10)
                                 Text(thread.document.name)
                             }
                             .padding(.vertical, 8)
                         }
                     }
                 }
                 .searchable(text: $searchText, prompt: "Search documents")
                 .onSubmit(of: .search) {
                     // Handle search submission if needed
                 }
                 .toolbar {
                     ToolbarItemGroup(placement: .navigationBarLeading) {
                         Text("Research Papers")
                             .font(.largeTitle)
                     }
                     ToolbarItemGroup(placement: .navigationBarTrailing) {
                         Button(action: {
                             showDocumentPicker.toggle()
                         }) {
                             Image(systemName: "plus")
                         }
                         .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                         
                     }
                     
                 }
             }
         }
         .navigationBarTitle("")
         .navigationViewStyle(StackNavigationViewStyle())
         .accentColor(.blue)
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
                     } else {
                         // Handle successful document upload if needed
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
     }
     
     
     func fetchDocuments() {
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
     }
     
     func updateChatThreads(with documents: [Document]) {
         var updatedThreads: [ChatThread] = []
       //  print(document.folderID)
       //  print(selectedFolder?.id)
         for document in documents {
             if document.folderID == selectedFolder?.id {
                 if let existingThread = chatThreads.first(where: { $0.document.id == document.id }) {
                     updatedThreads.append(existingThread)
                 } else {
                     let newThread = ChatThread(document: document, chatMessages: [])
                     updatedThreads.append(newThread)
                 }
             }
         }

         chatThreads = updatedThreads
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
     let document: Document
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

     @Binding var selectedFolder: Folder?
     var folder: Folder
     

     var filteredChatThreads: [ChatThread] {
         if searchText.isEmpty {
             return chatThreads
         } else {
             return chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
         }
     }

     var body: some View {
         ZStack {
             VStack {
                 List {
                     ForEach(Array(filteredChatThreads.enumerated()), id: \.element.id) { (index, thread) in
                         NavigationLink(destination: DocumentView(documentURL: thread.document.url)) {
                             HStack {
                                 Text("\(index + 1).")
                                     .font(.headline)
                                     .padding(10)
                                 Text(thread.document.name)
                             }
                             .padding(.vertical, 8)
                         }
                     }
                 }
                 .searchable(text: $searchText, prompt: "Search documents")
                 .onSubmit(of: .search) {
                     // Handle search submission if needed
                 }
                 .toolbar {
                     ToolbarItemGroup(placement: .navigationBarLeading) {
                         Text("Research Papers")
                             .font(.largeTitle)
                     }
                     ToolbarItemGroup(placement: .navigationBarTrailing) {
                         Button(action: {
                             showDocumentPicker.toggle()
                         }) {
                             Image(systemName: "plus")
                         }
                         .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                                             
                     }

                 }
             }
         }
         .navigationBarTitle("")
         .navigationViewStyle(StackNavigationViewStyle())
         .accentColor(.blue)
         .onAppear {
             fetchDocuments()
         }
         .sheet(isPresented: $showDocumentPicker) {
             DocumentPicker(
                 alert: self.$alert,
                 documents: self.$documents,
                 completionHandler: { myDocument, errorMessage in
                     if let errorMessage = errorMessage {
                         self.errorMessage = errorMessage
                         self.alert = true
                     } else {
                         // Add logic to associate the document with the selected folder
                         if let selectedFolder = selectedFolder {
                             var updatedDocument = myDocument // Create a mutable copy
                             updatedDocument.folderID = selectedFolder.id // Update the folderID
                             uploadDocumentToFolder(document: updatedDocument, folder: selectedFolder)
                         } else {
                             // Handle case when no folder is selected
                         }
                     }
                 },
                 selectedFolder: self.$selectedFolder
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
     }
     func uploadDocumentToFolder(document: Document, folder: Folder) {
         let db = Firestore.firestore()
         let documentsCollection = db.collection("ResearchPapers")
         
         let documentData: [String: Any] = [
             "name": document.name,
             "url": document.url.absoluteString,
             "folderID": folder.id.uuidString // Assuming folder ID is stored as a UUID
         ]
         
         documentsCollection.addDocument(data: documentData) { error in
             if let error = error {
                 print("Error saving document: \(error.localizedDescription)")
             } else {
                 print("Document saved successfully")
                 // Update your local documents array or perform any other necessary updates
             }
         }
     }

     
     func fetchDocuments() {
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
                       let folderID = data["folderID"] as? UUID
                 else {
                     return nil
                 }
                 return Document(name: name, url: url, folderID: folderID)
             }
             
             updateChatThreads(with: fetchedDocuments)
         }
     }

     
     func updateChatThreads(with documents: [Document]) {
         var updatedThreads: [ChatThread] = []
         
         // Filter the documents based on the selected folder's ID
         let filteredDocuments = documents.filter { $0.folderID == selectedFolder?.id }
         
         for document in filteredDocuments {
             if let existingThread = chatThreads.first(where: { $0.document.id == document.id }) {
                 updatedThreads.append(existingThread)
             } else {
                 let newThread = ChatThread(document: document, chatMessages: [])
                 updatedThreads.append(newThread)
             }
         }
         
         chatThreads = updatedThreads
     }
 }

 func fetchFolders(completion: @escaping ([Folder]) -> Void) {
     let db = Firestore.firestore()
     db.collection("Folders").getDocuments { (querySnapshot, error) in
         if let error = error {
             print("Error fetching folders: \(error.localizedDescription)")
             completion([])
             return
         }
         
         guard let folderDocuments = querySnapshot?.documents else {
             print("No folders found")
             completion([])
             return
         }
         
         let fetchedFolders = folderDocuments.compactMap { folderDocument -> Folder? in
             let folderData = folderDocument.data()
             guard let folderName = folderData["name"] as? String else {
                 return nil
             }
             return Folder(name: folderName)
         }
         
         completion(fetchedFolders)
     }
 }

 struct Folder: Identifiable {
     let id = UUID()
     let name: String
 }


 struct FolderListView: View {
     @State private var folders: [Folder] = []
     @State private var selectedFolder: Folder? = nil
     @State private var showHomePage = false
     @State private var newFolderName = ""
     @State private var showFolderCreationSheet = false

     var body: some View {
         NavigationView {
             List(folders) { folder in
                 NavigationLink(destination: HomePage(selectedFolder: $selectedFolder, folder: folder)) {
                     Text(folder.name)
                 }
             }
         }
             .toolbar {
                 ToolbarItemGroup(placement: .navigationBarLeading) {
                     Text("Folders")
                         .font(.largeTitle)
                 }
                 ToolbarItemGroup(placement: .navigationBarTrailing) {
                     
                     Button(action: {
                         showFolderCreationSheet.toggle()
                     }) {
                         Image(systemName: "folder.badge.plus")
                     }
                     .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                     
                     NavigationLink(destination: Profile()) {
                         Image(systemName: "person.fill")
                     }
                     .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                 }

             }
             .onAppear {
                 fetchFolders { fetchedFolders in
                     self.folders = fetchedFolders // Store the fetched folders in the array
                 }
             }

         .sheet(isPresented: $showFolderCreationSheet) {
             VStack {
                 TextField("Folder Name", text: $newFolderName)
                     .padding()
                     .textFieldStyle(RoundedBorderTextFieldStyle())
                 
                 Button("Create Folder") {
                     createFolder()
                     showFolderCreationSheet.toggle()
                 }
                 .padding()
                 .background(Color.blue)
                 .foregroundColor(.white)
                 .cornerRadius(10)
             }
             .padding()
         }
         
     }
     
     func createFolder() {
         let db = Firestore.firestore()
         let newFolderID = UUID() // Generate a new UUID for the folder
         
         let newFolderData: [String: Any] = [
             "name": newFolderName,
             "id": newFolderID.uuidString // Convert UUID to string
             // Add more properties if needed
         ]
         
         db.collection("Folders").addDocument(data: newFolderData) { error in
             if let error = error {
                 print("Error creating folder: \(error.localizedDescription)")
                 return
             }
         
             let newFolder = Folder(name: newFolderName)
             folders.append(newFolder) // Update your folders array
         }
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

 struct Folder: Identifiable {
     let id = UUID()
     let name: String
 }
 struct ChatThread: Identifiable {
     let id = UUID()
     let document: Document
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

     @Binding var selectedFolder: Folder?
     var folder: Folder
     

     var filteredChatThreads: [ChatThread] {
         if searchText.isEmpty {
             return chatThreads
         } else {
             return chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
         }
     }

     var body: some View {
         ZStack {
             VStack {
                 List {
                     ForEach(Array(filteredChatThreads.enumerated()), id: \.element.id) { (index, thread) in
                         NavigationLink(destination: DocumentView(documentURL: thread.document.url)) {
                             HStack {
                                 Text("\(index + 1).")
                                     .font(.headline)
                                     .padding(10)
                                 Text(thread.document.name)
                             }
                             .padding(.vertical, 8)
                         }
                     }
                 }
                 .searchable(text: $searchText, prompt: "Search documents")
                 .onSubmit(of: .search) {
                     // Handle search submission if needed
                 }
                 .toolbar {
                     ToolbarItemGroup(placement: .navigationBarLeading) {
                         Text("Research Papers")
                             .font(.largeTitle)
                     }
                     ToolbarItemGroup(placement: .navigationBarTrailing) {
                         Button(action: {
                             showDocumentPicker.toggle()
                         }) {
                             Image(systemName: "plus")
                         }
                         .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                                             
                     }

                 }
             }
         }
         .navigationBarTitle("")
         .navigationViewStyle(StackNavigationViewStyle())
         .accentColor(.blue)
         .onAppear {
             fetchDocuments()
         }
         .sheet(isPresented: $showDocumentPicker) {
             DocumentPicker(
                 alert: self.$alert,
                 documents: self.$documents,
                 completionHandler: { myDocument, errorMessage in
                     if let errorMessage = errorMessage {
                         self.errorMessage = errorMessage
                         self.alert = true
                     } else {
                         // Add logic to associate the document with the selected folder
                         if let selectedFolder = selectedFolder {
                             var updatedDocument = myDocument // Create a mutable copy
                             updatedDocument.folderID = selectedFolder.id // Update the folderID
                             uploadDocumentToFolder(document: updatedDocument, folder: selectedFolder)
                         } else {
                             // Handle case when no folder is selected
                         }
                     }
                 },
                 selectedFolder: self.$selectedFolder
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
     }
     func uploadDocumentToFolder(document: Document, folder: Folder) {
         let db = Firestore.firestore()
         let documentsCollection = db.collection("ResearchPapers")
         
         let documentData: [String: Any] = [
             "name": document.name,
             "url": document.url.absoluteString,
             "folderID": folder.id.uuidString // Assuming folder ID is stored as a UUID
         ]
         
         documentsCollection.addDocument(data: documentData) { error in
             if let error = error {
                 print("Error saving document: \(error.localizedDescription)")
             } else {
                 print("Document saved successfully")
                 // Update your local documents array or perform any other necessary updates
             }
         }
     }

     
     func fetchDocuments() {
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
                       let folderID = data["folderID"] as? UUID
                 else {
                     return nil
                 }
                 return Document(name: name, url: url, folderID: folderID)
             }
             
             updateChatThreads(with: fetchedDocuments)
         }
     }

     
     func updateChatThreads(with documents: [Document]) {
         var updatedThreads: [ChatThread] = []
         
         // Filter the documents based on the selected folder's ID
         let filteredDocuments = documents.filter { $0.folderID == selectedFolder?.id }
         
         for document in filteredDocuments {
             if let existingThread = chatThreads.first(where: { $0.document.id == document.id }) {
                 updatedThreads.append(existingThread)
             } else {
                 let newThread = ChatThread(document: document, chatMessages: [])
                 updatedThreads.append(newThread)
             }
         }
         
         chatThreads = updatedThreads
     }
 }

 func fetchFolders(completion: @escaping ([Folder]) -> Void) {
     let db = Firestore.firestore()
     db.collection("Folders").getDocuments { (querySnapshot, error) in
         if let error = error {
             print("Error fetching folders: \(error.localizedDescription)")
             completion([])
             return
         }
         
         guard let folderDocuments = querySnapshot?.documents else {
             print("No folders found")
             completion([])
             return
         }
         
         let fetchedFolders = folderDocuments.compactMap { folderDocument -> Folder? in
             let folderData = folderDocument.data()
             guard let folderName = folderData["name"] as? String else {
                 return nil
             }
             return Folder(name: folderName)
         }
         
         completion(fetchedFolders)
     }
 }

 struct FolderListView: View {
     @State private var folders: [Folder] = []
     @State private var selectedFolder: Folder? = nil
     @State private var showHomePage = false
     @State private var newFolderName = ""
     @State private var showFolderCreationSheet = false

     var body: some View {
         NavigationView {
             List(folders) { folder in
                 NavigationLink(destination: HomePage(selectedFolder: $selectedFolder, folder: folder)) {
                     Text(folder.name)
                 }
             }
         }
             .toolbar {
                 ToolbarItemGroup(placement: .navigationBarLeading) {
                     Text("Folders")
                         .font(.largeTitle)
                 }
                 ToolbarItemGroup(placement: .navigationBarTrailing) {
                     
                     Button(action: {
                         showFolderCreationSheet.toggle()
                     }) {
                         Image(systemName: "folder.badge.plus")
                     }
                     .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                     
                     NavigationLink(destination: Profile()) {
                         Image(systemName: "person.fill")
                     }
                     .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                 }

             }
             
         
         .onAppear {
             fetchFolders { fetchedFolders in
                 folders = fetchedFolders
             }
         }
         .sheet(isPresented: $showFolderCreationSheet) {
             VStack {
                 TextField("Folder Name", text: $newFolderName)
                     .padding()
                     .textFieldStyle(RoundedBorderTextFieldStyle())
                 
                 Button("Create Folder") {
                     createFolder()
                     showFolderCreationSheet.toggle()
                 }
                 .padding()
                 .background(Color.blue)
                 .foregroundColor(.white)
                 .cornerRadius(10)
             }
             .padding()
         }
         
     }
     
     func createFolder() {
         let db = Firestore.firestore()
         let newFolderData: [String: Any] = [
             "name": newFolderName
             // Add more properties if needed
         ]
         
         db.collection("Folders").addDocument(data: newFolderData) { error in
             if let error = error {
                 print("Error creating folder: \(error.localizedDescription)")
                 return
             }
             
             let newFolder = Folder(name: newFolderName)
             // Append the new folder to your array or update chatThreads if needed
         }
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
     let id = UUID()
     let name: String
     let url: URL
 }
 struct Folder: Identifiable {
     let id = UUID()
     let name: String
 }


 struct HomePage: View {
     
     @State private var alert = false
     @State private var chatThreads: [ChatThread] = []
     @State private var documents: [Document] = []
     @State private var errorMessage = ""
     @State private var isLoading = true // New state to manage loading state
     @State private var showDocumentPicker = false
     @State private var searchText = ""

     @Binding var selectedFolder: Folder?
     var folder: Folder

     var filteredChatThreads: [ChatThread] {
         if searchText.isEmpty {
             return chatThreads
         } else {
             return chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
         }
     }
     
     
     var body: some View {
         ZStack {
             VStack {
                 List {
                     ForEach(Array(filteredChatThreads.enumerated()), id: \.element.id) { (index, thread) in
                         NavigationLink(destination: DocumentView(documentURL: thread.document.url)) {
                             HStack {
                                 Text("\(index + 1).")
                                     .font(.headline)
                                     .padding(10)
                                 Text(thread.document.name)
                             }
                             .padding(.vertical, 8)
                         }
                     }
                 }
                 .searchable(text: $searchText, prompt: "Search documents")
                 .onSubmit(of: .search) {
                     // Handle search submission if needed
                 }
                 .toolbar {
                     ToolbarItemGroup(placement: .navigationBarLeading) {
                         Text("Research Papers")
                             .font(.largeTitle)
                     }
                     ToolbarItemGroup(placement: .navigationBarTrailing) {
                         Button(action: {
                             showDocumentPicker.toggle()
                         }) {
                             Image(systemName: "plus")
                         }
                         .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                                             
                     }

                 }
             }
         }
         .navigationBarTitle("")
         .navigationViewStyle(StackNavigationViewStyle())
         .accentColor(.blue)
         .onAppear {
             fetchDocuments()
         }
         .sheet(isPresented: $showDocumentPicker) {
             DocumentPicker(alert: self.$alert, documents: self.$documents) { document, errorMessage in
                 if let errorMessage = errorMessage {
                     self.errorMessage = errorMessage
                     self.alert = true
                 }
                 else {
                     let newThread = ChatThread(document: document, chatMessages: [])
                     self.chatThreads.append(newThread)
                 }
             }
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
     }

     
     func fetchDocuments() {
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
                       let url = URL(string: urlString) else {
                     return nil
                 }
                 return Document(name: name, url: url)
             }
             
             updateChatThreads(with: fetchedDocuments)
         }
     }
     
     
     func updateChatThreads(with documents: [Document]) {
         var updatedThreads: [ChatThread] = []
         
         for document in documents {
             if let existingThread = chatThreads.first(where: { $0.document.id == document.id }) {
                 updatedThreads.append(existingThread)
             } else {
                 let newThread = ChatThread(document: document, chatMessages: [])
                 updatedThreads.append(newThread)
             }
         }
         
         chatThreads = updatedThreads
     }
 }

 func fetchFolders(completion: @escaping ([Folder]) -> Void) {
     let db = Firestore.firestore()
     db.collection("Folders").getDocuments { (querySnapshot, error) in
         if let error = error {
             print("Error fetching folders: \(error.localizedDescription)")
             completion([])
             return
         }
         
         guard let folderDocuments = querySnapshot?.documents else {
             print("No folders found")
             completion([])
             return
         }
         
         let fetchedFolders = folderDocuments.compactMap { folderDocument -> Folder? in
             let folderData = folderDocument.data()
             guard let folderName = folderData["name"] as? String else {
                 return nil
             }
             return Folder(name: folderName)
         }
         
         completion(fetchedFolders)
     }
 }

 struct FolderListView: View {
     @State private var folders: [Folder] = []
     @State private var selectedFolder: Folder? = nil
     @State private var showHomePage = false
     @State private var newFolderName = ""
     @State private var showFolderCreationSheet = false

     var body: some View {
         NavigationView {
             List(folders) { folder in
                 NavigationLink(destination: HomePage(selectedFolder: $selectedFolder, folder: folder)) {
                     Text(folder.name)
                 }
             }
         }
             .toolbar {
                 ToolbarItemGroup(placement: .navigationBarLeading) {
                     Text("Folders")
                         .font(.largeTitle)
                 }
                 ToolbarItemGroup(placement: .navigationBarTrailing) {
                     
                     Button(action: {
                         showFolderCreationSheet.toggle()
                     }) {
                         Image(systemName: "folder.badge.plus")
                     }
                     .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                     
                     NavigationLink(destination: Profile()) {
                         Image(systemName: "person.fill")
                     }
                     .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                 }

             }
             
         
         .onAppear {
             fetchFolders { fetchedFolders in
                 folders = fetchedFolders
             }
         }
         .sheet(isPresented: $showFolderCreationSheet) {
             VStack {
                 TextField("Folder Name", text: $newFolderName)
                     .padding()
                     .textFieldStyle(RoundedBorderTextFieldStyle())
                 
                 Button("Create Folder") {
                     createFolder()
                     showFolderCreationSheet.toggle()
                 }
                 .padding()
                 .background(Color.blue)
                 .foregroundColor(.white)
                 .cornerRadius(10)
             }
             .padding()
         }
         
     }
     
     func createFolder() {
         let db = Firestore.firestore()
         let newFolderData: [String: Any] = [
             "name": newFolderName
             // Add more properties if needed
         ]
         
         db.collection("Folders").addDocument(data: newFolderData) { error in
             if let error = error {
                 print("Error creating folder: \(error.localizedDescription)")
                 return
             }
             
             let newFolder = Folder(name: newFolderName)
             // Append the new folder to your array or update chatThreads if needed
         }
     }
 }

 */



//folder created
/*
 import SwiftUI
 import MobileCoreServices
 import FirebaseStorage
 import UniformTypeIdentifiers
 import FirebaseFirestore

 struct Document: Identifiable {
     let id = UUID()
     let name: String
     let url: URL
 }
 struct Folder: Identifiable {
     let id = UUID()
     let name: String
 }


 struct HomePage: View {
     
     @State private var alert = false
     @State private var chatThreads: [ChatThread] = []
     @State private var documents: [Document] = []
     @State private var errorMessage = ""
     @State private var isLoading = true // New state to manage loading state
     @State private var showDocumentPicker = false
     @State private var searchText = ""
     @State private var showFolderCreationSheet = false
     @State private var newFolderName = ""

     
     var filteredChatThreads: [ChatThread] {
         if searchText.isEmpty {
             return chatThreads
         } else {
             return chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
         }
     }
     
     
     var body: some View {
         ZStack {
             VStack {
                 List {
                     ForEach(Array(filteredChatThreads.enumerated()), id: \.element.id) { (index, thread) in
                         NavigationLink(destination: DocumentView(documentURL: thread.document.url)) {
                             HStack {
                                 Text("\(index + 1).")
                                     .font(.headline)
                                     .padding(10)
                                 Text(thread.document.name)
                             }
                             .padding(.vertical, 8)
                         }
                     }
                 }
                 .searchable(text: $searchText, prompt: "Search documents")
                 .onSubmit(of: .search) {
                     // Handle search submission if needed
                 }
                 .toolbar {
                     ToolbarItemGroup(placement: .navigationBarLeading) {
                         Text("Research Papers")
                             .font(.largeTitle)
                     }
                     ToolbarItemGroup(placement: .navigationBarTrailing) {
                         Button(action: {
                             showDocumentPicker.toggle()
                         }) {
                             Image(systemName: "plus")
                         }
                         .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                         
                         Button(action: {
                             showFolderCreationSheet.toggle()
                         }) {
                             Image(systemName: "folder.badge.plus")
                         }
                         .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                         
                         NavigationLink(destination: Profile()) {
                             Image(systemName: "person.fill")
                         }
                         .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                     }

                 }
             }
         }
         .navigationBarTitle("")
         .navigationViewStyle(StackNavigationViewStyle())
         .accentColor(.blue)
         .onAppear {
             fetchDocuments()
         }
         .sheet(isPresented: $showDocumentPicker) {
             DocumentPicker(alert: self.$alert, documents: self.$documents) { document, errorMessage in
                 if let errorMessage = errorMessage {
                     self.errorMessage = errorMessage
                     self.alert = true
                 }
                 else {
                     let newThread = ChatThread(document: document, chatMessages: [])
                     self.chatThreads.append(newThread)
                 }
             }
         }
         .sheet(isPresented: $showFolderCreationSheet) {
             VStack {
                 TextField("Folder Name", text: $newFolderName)
                     .padding()
                     .textFieldStyle(RoundedBorderTextFieldStyle())
                 
                 Button("Create Folder") {
                     createFolder()
                     showFolderCreationSheet.toggle()
                 }
                 .padding()
                 .background(Color.blue)
                 .foregroundColor(.white)
                 .cornerRadius(10)
             }
             .padding()
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
     }
     func createFolder() {
         let db = Firestore.firestore()
         let newFolderData: [String: Any] = [
             "name": newFolderName
             // Add more properties if needed
         ]
         
         db.collection("Folders").addDocument(data: newFolderData) { error in
             if let error = error {
                 print("Error creating folder: \(error.localizedDescription)")
                 return
             }
             
             let newFolder = Folder(name: newFolderName)
             // Append the new folder to your array or update chatThreads if needed
         }
     }

     
     func fetchDocuments() {
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
                       let url = URL(string: urlString) else {
                     return nil
                 }
                 return Document(name: name, url: url)
             }
             
             updateChatThreads(with: fetchedDocuments)
         }
     }
     
     
     func updateChatThreads(with documents: [Document]) {
         var updatedThreads: [ChatThread] = []
         
         for document in documents {
             if let existingThread = chatThreads.first(where: { $0.document.id == document.id }) {
                 updatedThreads.append(existingThread)
             } else {
                 let newThread = ChatThread(document: document, chatMessages: [])
                 updatedThreads.append(newThread)
             }
         }
         
         chatThreads = updatedThreads
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
     let id = UUID()
     let name: String
     let url: URL
 }

 struct HomePage: View {
     
     @State private var alert = false
     @State private var chatThreads: [ChatThread] = []
     @State private var documents: [Document] = []
     @State private var errorMessage = ""
     @State private var isLoading = true // New state to manage loading state
     @State private var showDocumentPicker = false
     @State private var searchText = ""
     
     
     var filteredChatThreads: [ChatThread] {
         if searchText.isEmpty {
             return chatThreads
         } else {
             return chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
         }
     }
     
     
     var body: some View {
         ZStack {
             VStack {
                 List {
                     ForEach(Array(filteredChatThreads.enumerated()), id: \.element.id) { (index, thread) in
                         NavigationLink(destination: DocumentView(documentURL: thread.document.url)) {
                             HStack {
                                 Text("\(index + 1).")
                                     .font(.headline)
                                     .padding(10)
                                 Text(thread.document.name)
                             }
                             .padding(.vertical, 8)
                         }
                     }
                 }
                 .searchable(text: $searchText, prompt: "Search documents")
                 .onSubmit(of: .search) {
                     // Handle search submission if needed
                 }
                 .toolbar {
                     ToolbarItemGroup(placement: .navigationBarLeading) {
                         Text("Research Papers")
                             .font(.largeTitle)
                     }
                     ToolbarItemGroup(placement: .navigationBarTrailing) {
                         Button(action: {
                             showDocumentPicker.toggle()
                         }) {
                             Image(systemName: "plus")
                         }
                         .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                         
                         NavigationLink(destination: Profile()) {
                             Image(systemName: "person.fill")
                         }
                         .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                     }
                 }
             }
         }
         .navigationBarTitle("")
         .navigationViewStyle(StackNavigationViewStyle())
         .accentColor(.blue)
         .onAppear {
             fetchDocuments()
         }
         .sheet(isPresented: $showDocumentPicker) {
             DocumentPicker(alert: self.$alert, documents: self.$documents) { document, errorMessage in
                 if let errorMessage = errorMessage {
                     self.errorMessage = errorMessage
                     self.alert = true
                 }
                 else {
                     let newThread = ChatThread(document: document, chatMessages: [])
                     self.chatThreads.append(newThread)
                 }
             }
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
     }
     
     
     func fetchDocuments() {
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
                       let url = URL(string: urlString) else {
                     return nil
                 }
                 return Document(name: name, url: url)
             }
             
             updateChatThreads(with: fetchedDocuments)
         }
     }
     
     
     func updateChatThreads(with documents: [Document]) {
         var updatedThreads: [ChatThread] = []
         
         for document in documents {
             if let existingThread = chatThreads.first(where: { $0.document.id == document.id }) {
                 updatedThreads.append(existingThread)
             } else {
                 let newThread = ChatThread(document: document, chatMessages: [])
                 updatedThreads.append(newThread)
             }
         }
         
         chatThreads = updatedThreads
     }
 }

 */
