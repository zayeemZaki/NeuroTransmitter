import SwiftUI
import MobileCoreServices
import FirebaseStorage
import UniformTypeIdentifiers
import PDFKit
import FirebaseFirestore

struct Document: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
}

struct HomePage: View {
    // MARK: - State Properties
    
    @State private var alert = false
    @State private var chatThreads: [ChatThread] = []
    @State private var documents: [Document] = []
    @State private var errorMessage = ""
    @State private var isLoading = true // New state to manage loading state
    @State private var showDocumentPicker = false
    @State private var searchText = ""
    
    // MARK: - Computed Property
    
    var filteredChatThreads: [ChatThread] {
        if searchText.isEmpty {
            return chatThreads
        } else {
            return chatThreads.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    // MARK: - View Body
    
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
    
    // MARK: - Data Fetching
    
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
    
    // MARK: - Data Update
    
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
