import SwiftUI
import FirebaseFirestore
import PDFKit

struct Folder: Identifiable {
    let id: UUID
    let name: String
    let hasDocuments: Bool
}

extension Folder: Hashable {
    static func == (lhs: Folder, rhs: Folder) -> Bool {
        return lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

struct FolderListView: View {
    @State private var folders: [Folder] = []
    @State private var newFolderName = ""
    @State private var showFolderCreationPopover = false
    @State private var searchText = ""
    @State private var selectedDeleteFolder: Folder? = nil
    @State private var showAlert = false
    @State private var showAlert2 = false
    @Environment(\.colorScheme) var colorScheme
    @State private var isLongPressActive = false // Track long-press
    @State private var showingProfile = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.gray.opacity(0.2).edgesIgnoringSafeArea(.all)

                // Use a GeometryReader to make better use of the available space
                GeometryReader { _ in
                    List(folders.filter { searchText.isEmpty ? true : $0.name.localizedCaseInsensitiveContains(searchText) }) { folder in
                        NavigationLink(value: folder) {
                            FolderRow(folder: folder)
                        }
                        .padding(.vertical, 5)
                        .contextMenu {
                            Button(role: .destructive) {
                                selectedDeleteFolder = folder
                                deleteFolder()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                    .searchable(text: $searchText, prompt: "Search Folders")
                    .navigationDestination(for: Folder.self) { selectedFolder in
                        HomePage(selectedFolder: .constant(selectedFolder), folders: $folders, onDocumentMove: {
                            fetchFolders { fetchedFolders in
                                // Assuming 'self.folders' is a @State variable in your current view
                                // Update your folders array with the fetched folders
                                self.folders = fetchedFolders
                            }
                        })
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    leadingToolbarItems
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    trailingToolbarItems
                }
            }
        }
        .popover(isPresented: $showFolderCreationPopover) {
            folderCreationPopover
        }
        .onAppear {
            fetchFolders { fetchedFolders in
                DispatchQueue.main.async {
                    self.folders = fetchedFolders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                }
            }
        }
        .alert("Cannot Delete Folder", isPresented: $showAlert, actions: {}) {
            Text("This folder contains documents and cannot be deleted.")
        }
        .alert("Cannot Delete Recent Folder", isPresented: $showAlert2, actions: {}) {
            Text("This folder is default and can't be deleted.")
        }
    }

    // Extracted view components for better readability and maintenance
    @ViewBuilder
    private var leadingToolbarItems: some View {
        Text("Folders")
            .font(.largeTitle)
            .bold()
    }
    
    @ViewBuilder
    private var trailingToolbarItems: some View {
        Button(action: {
            showFolderCreationPopover.toggle()
        }) {
            Image(systemName: "folder.badge.plus")
        }
        
        NavigationLink(destination: Profile()) {
            Image(systemName: "person.fill")
        }
    }
    
    @ViewBuilder
    private var folderCreationPopover: some View {
        VStack(spacing: 20) {
            Text("Create New Folder")
                .font(.title)
                .bold()

            TextField("Folder Name", text: $newFolderName)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            Button("Create Folder") {
                let newFolder = Folder(id: UUID(), name: newFolderName, hasDocuments: false)
                createFolder(folder: newFolder)
                showFolderCreationPopover = false
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 300, height: 200)
    }

     func deleteFolder() {
         if let folderToDelete = selectedDeleteFolder {
             // Check if the folder name is "Recent"
             if folderToDelete.name == "Recent" {
                 print("The 'Recent' folder cannot be deleted.")
                 // Optionally, set showAlert to true to inform the user
                 showAlert2 = true
                 isLongPressActive = false
             }
             else if folderToDelete.hasDocuments {
                 showAlert = true // Show an alert indicating that the folder has documents and cannot be deleted.
                 isLongPressActive = false
             }
             else {
                 let db = Firestore.firestore()
                 let documentReference = db.collection("Folders").document(folderToDelete.id.uuidString)

                 // Check if the folder has documents before deleting
                 db.collection("ResearchPapers")
                     .whereField("folderID", isEqualTo: folderToDelete.id.uuidString)
                     .getDocuments { (snapshot, error) in
                         if let error = error {
                             print("Error checking for documents: \(error.localizedDescription)")
                         }
                         else if let snapshot = snapshot, !snapshot.documents.isEmpty {
                             showAlert = true // Show an alert indicating that the folder has documents and cannot be deleted.
                         }
                         else {
                             // No documents found in the folder, proceed with deletion
                             documentReference.delete { error in
                                 if let error = error {
                                     print("Error deleting folder: \(error.localizedDescription)")
                                 }
                                 else {
                                     print("Folder deleted successfully")
                                     // Remove the folder from the local list
                                     if let indexToDelete = self.folders.firstIndex(where: { $0.id == folderToDelete.id }) {
                                         self.folders.remove(at: indexToDelete)
                                     }
                                     // Reset the selectedDeleteFolder and isLongPressActive states
                                     selectedDeleteFolder = nil
                                     isLongPressActive = false
                                 }
                             }
                         }
                     }
             }
         }
     }


     func createFolder(folder: Folder) {
         let db = Firestore.firestore()
         let newFolderId = UUID()

         let newFolderData: [String: Any] = [
             "name": folder.name,
             "folderId": newFolderId.uuidString,
             "hasDocuments": false
         ]

         let documentReference = db.collection("Folders").document(newFolderId.uuidString)

         documentReference.setData(newFolderData) { error in
             if let error = error {
                 print("Error creating folder: \(error.localizedDescription)")
                 return
             }

             let newFolder = Folder(id: newFolderId, name: folder.name, hasDocuments: false)

             // Insert the new folder in sorted order, starting from index 1 to exclude "Recent"
             let insertionIndex = self.folders[1...].firstIndex(where: {
                 $0.name.localizedCaseInsensitiveCompare(newFolder.name) == .orderedDescending
             }) ?? self.folders.count

             self.folders.insert(newFolder, at: insertionIndex)
         }
     }
 }

struct FolderRow: View {
    let folder: Folder

    var body: some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundColor(.yellow)
            Text(folder.name)
                .font(.headline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 2)
        )
    }
}


