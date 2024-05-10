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




/*
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

 */






/*
 
 import SwiftUI
 import FirebaseFirestore
 import PDFKit

 struct Folder: Identifiable {
     let id: UUID
     let name: String
     let hasDocuments: Bool // New property to track if the folder has documents
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
     @State private var selectedFolder: Folder? = nil
     @State private var newFolderName = ""
     @State private var showFolderCreationPopover = false
     @State private var searchText = ""
     @State private var isLongPressActive = false // Track long-press
     @State private var selectedDeleteFolder: Folder? = nil // Track the folder to delete
     @State private var showAlert = false // Track whether to show an alert
     @State private var showAlert2 = false // Track whether to show an alert
     @Environment(\.colorScheme) var colorScheme
     @State private var hasDocuments = false
     @State private var isContextMenuActive = false // Track whether the context menu is active

     var body: some View {
         NavigationStack {
             ZStack {
                 Color.gray.opacity(0.2).edgesIgnoringSafeArea(.all)

                 List(folders.filter { searchText.isEmpty ? true : $0.name.localizedCaseInsensitiveContains(searchText) }) { folder in
                     NavigationLink(value: folder) {
                         HStack {
                             Image(systemName: "folder.fill")
                                 .foregroundColor(Color.yellow)
                             Text(folder.name)
                                 .font(.headline)
                         }
                         .padding()
                         .frame(maxWidth: .infinity, alignment: .leading)
                         .cornerRadius(8)
                         .overlay(
                             RoundedRectangle(cornerRadius: 8)
                                 .stroke(Color(red: 0.2, green: 0.5, blue: 0.3).opacity(0.2), lineWidth: 2)
                         )
                     }
                     .padding(.vertical, 5)
                     .contextMenu {
                         Button(action: {
                             isLongPressActive = true
                             selectedDeleteFolder = folder
                             deleteFolder()
                         }) {
                             Label("Delete", systemImage: "trash")
                                 .foregroundColor(.red)
                         }
                     }
                 }
                 .listStyle(PlainListStyle())
                 .searchable(text: $searchText, prompt: "Search Folders")
                 .navigationDestination(for: Folder.self) { folder in
                     HomePage(selectedFolder: .constant(folder), folders: $folders, onDocumentMove: {
                         fetchFolders { fetchedFolders in
                             // Update your folders state with the fetched folders
                             self.folders = fetchedFolders
                         }
                     })
                 }
             }
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
                             .rotationEffect(showFolderCreationPopover ? .degrees(45) : .degrees(0))
                             .animation(.easeIn, value: showFolderCreationPopover)
                             .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                     }
                 }
                 ToolbarItem(placement: .navigationBarTrailing) {
                     NavigationLink(destination: Profile()) {
                         Image(systemName: "person.fill")
                             .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                     }
                 }
             }
         }

        // .navigationViewStyle(StackNavigationViewStyle())
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
                         let newFolder = Folder(id: UUID(), name: newFolderName, hasDocuments: false)
                         createFolder(folder: newFolder)
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
                 .frame(width: geometry.size.width * 0.8, height: geometry.size.height * 0.6)
                 .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
             }
         }
         .onAppear {
             fetchFolders { fetchedFolders in
                 // Sort all folders alphabetically
                 var folders = fetchedFolders.sorted {
                     $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                 }
                 
                 // Find the index of the "Recent" folder, if it exists
                 if let recentFolderIndex = folders.firstIndex(where: {
                     $0.name.lowercased() == "recent"
                 }) {
                     // Remove the "Recent" folder from its current position
                     let recentFolder = folders.remove(at: recentFolderIndex)
                     // Insert the "Recent" folder at the top
                     folders.insert(recentFolder, at: 0)
                 }
                 else {
                     // "Recent" folder doesn't exist, create it
                     let recentFolder = Folder(id: UUID(), name: "Recent", hasDocuments: false)
                     createFolder(folder: recentFolder)
                     // Insert the new "Recent" folder at the top
                     folders.insert(recentFolder, at: 0)
                 }

                 // Update availableFolders
                 self.folders = folders
             }
         }


         .searchable(text: $searchText, prompt: "Search folders")
         .alert(isPresented: $showAlert) {
             Alert(
                 title: Text("Cannot Delete Folder"),
                 message: Text("This folder contains documents and cannot be deleted."),
                 dismissButton: .default(Text("OK"))
             )
         }
         .alert(isPresented: $showAlert2) {
             Alert(
                 title: Text("Cannot Delete Recent Folder"),
                 message: Text("This folder is default and can't be deleted."),
                 dismissButton: .default(Text("OK"))
             )
         }
     }
     
     private func isSelectedFolder(_ folder: Folder) -> Bool {
         return selectedFolder == folder
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
 */
















/*
 
 import SwiftUI
 import FirebaseFirestore
 import PDFKit

 struct Folder: Identifiable {
     let id: UUID
     let name: String
     let hasDocuments: Bool // New property to track if the folder has documents
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
     @State private var selectedFolder: Folder? = nil
     @State private var newFolderName = ""
     @State private var showFolderCreationPopover = false
     @State private var searchText = ""
     @State private var isLongPressActive = false // Track long-press
     @State private var selectedDeleteFolder: Folder? = nil // Track the folder to delete
     @State private var showAlert = false // Track whether to show an alert
     @State private var showAlert2 = false // Track whether to show an alert
     @Environment(\.colorScheme) var colorScheme
     @State private var hasDocuments = false
     @State private var isContextMenuActive = false // Track whether the context menu is active

     var body: some View {
         NavigationStack {
             ZStack {
                 Color.gray.opacity(0.2).edgesIgnoringSafeArea(.all)

                 List(folders.filter { searchText.isEmpty ? true : $0.name.localizedCaseInsensitiveContains(searchText) }) { folder in
                     NavigationLink(value: folder) {
                         HStack {
                             Image(systemName: "folder.fill")
                                 .foregroundColor(Color.yellow)
                             Text(folder.name)
                                 .font(.headline)
                         }
                         .padding()
                         .frame(maxWidth: .infinity, alignment: .leading)
                         .cornerRadius(8)
                         .overlay(
                             RoundedRectangle(cornerRadius: 8)
                                 .stroke(Color(red: 0.2, green: 0.5, blue: 0.3).opacity(0.2), lineWidth: 2)
                         )
                     }
                     .padding(.vertical, 5)
                     .contextMenu {
                         Button(action: {
                             isLongPressActive = true
                             selectedDeleteFolder = folder
                         }) {
                             Label("Delete", systemImage: "trash")
                                 .foregroundColor(.red)
                         }
                     }
                 }
                 .listStyle(PlainListStyle())
                 .searchable(text: $searchText, prompt: "Search Folders")
                 .navigationDestination(for: Folder.self) { folder in
                     HomePage(selectedFolder: .constant(folder), folders: $folders, onDocumentMove: {
                         fetchFolders { fetchedFolders in
                             // Update your folders state with the fetched folders
                             self.folders = fetchedFolders
                         }
                     })
                 }
             }
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
                             .rotationEffect(showFolderCreationPopover ? .degrees(45) : .degrees(0))
                             .animation(.easeIn, value: showFolderCreationPopover)
                             .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                     }
                 }
                 ToolbarItem(placement: .navigationBarTrailing) {
                     NavigationLink(destination: Profile()) {
                         Image(systemName: "person.fill")
                             .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                     }
                 }
             }
         }

        // .navigationViewStyle(StackNavigationViewStyle())
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
                         let newFolder = Folder(id: UUID(), name: newFolderName, hasDocuments: false)
                         createFolder(folder: newFolder)
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
                 .frame(width: geometry.size.width * 0.8, height: geometry.size.height * 0.6)
                 .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
             }
         }
         .onAppear {
             fetchFolders { fetchedFolders in
                 // Sort all folders alphabetically
                 var folders = fetchedFolders.sorted {
                     $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                 }
                 
                 // Find the index of the "Recent" folder, if it exists
                 if let recentFolderIndex = folders.firstIndex(where: {
                     $0.name.lowercased() == "recent"
                 }) {
                     // Remove the "Recent" folder from its current position
                     let recentFolder = folders.remove(at: recentFolderIndex)
                     // Insert the "Recent" folder at the top
                     folders.insert(recentFolder, at: 0)
                 }
                 else {
                     // "Recent" folder doesn't exist, create it
                     let recentFolder = Folder(id: UUID(), name: "Recent", hasDocuments: false)
                     createFolder(folder: recentFolder)
                     // Insert the new "Recent" folder at the top
                     folders.insert(recentFolder, at: 0)
                 }

                 // Update availableFolders
                 self.folders = folders
             }
         }


         .searchable(text: $searchText, prompt: "Search folders")
         .alert(isPresented: $showAlert) {
             Alert(
                 title: Text("Cannot Delete Folder"),
                 message: Text("This folder contains documents and cannot be deleted."),
                 dismissButton: .default(Text("OK"))
             )
         }
         .alert(isPresented: $showAlert2) {
             Alert(
                 title: Text("Cannot Delete Recent Folder"),
                 message: Text("This folder is default and can't be deleted."),
                 dismissButton: .default(Text("OK"))
             )
         }
     }
     
     private func isSelectedFolder(_ folder: Folder) -> Bool {
         return selectedFolder == folder
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
 */




















/*
 import SwiftUI
 import FirebaseFirestore
 import PDFKit

 struct Folder: Identifiable {
     let id: UUID
     let name: String
     let hasDocuments: Bool // New property to track if the folder has documents
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
     @State private var selectedFolder: Folder? = nil
     @State private var newFolderName = ""
     @State private var showFolderCreationPopover = false
     @State private var searchText = ""
     @State private var isLongPressActive = false // Track long-press
     @State private var selectedDeleteFolder: Folder? = nil // Track the folder to delete
     @State private var showAlert = false // Track whether to show an alert
     @State private var showAlert2 = false // Track whether to show an alert
     @Environment(\.colorScheme) var colorScheme
     @State private var hasDocuments = false
     @State private var isContextMenuActive = false // Track whether the context menu is active

     var body: some View {
         NavigationStack {
             ZStack {
                 Color.gray.opacity(0.2).edgesIgnoringSafeArea(.all)

                 List(folders.filter { searchText.isEmpty ? true : $0.name.localizedCaseInsensitiveContains(searchText) }) { folder in
                     NavigationLink(value: folder) {
                         HStack {
                             Image(systemName: "folder.fill")
                                 .foregroundColor(Color.yellow)
                             Text(folder.name)
                                 .font(.headline)
                         }
                         .padding()
                         .frame(maxWidth: .infinity, alignment: .leading)
                         .cornerRadius(8)
                         .overlay(
                             RoundedRectangle(cornerRadius: 8)
                                 .stroke(Color(red: 0.2, green: 0.5, blue: 0.3).opacity(0.2), lineWidth: 2)
                         )
                     }
                     .padding(.vertical, 5)
                     .contextMenu {
                         Button(action: {
                             isLongPressActive = true
                             selectedDeleteFolder = folder
                         }) {
                             Label("Delete", systemImage: "trash")
                                 .foregroundColor(.red)
                         }
                     }
                 }
                 .listStyle(PlainListStyle())
                 .searchable(text: $searchText, prompt: "Search Folders")
                 .navigationDestination(for: Folder.self) { folder in
                     HomePage(selectedFolder: .constant(folder), folders: $folders, onDocumentMove: {
                         fetchFolders { fetchedFolders in
                             // Update your folders state with the fetched folders
                             self.folders = fetchedFolders
                         }
                     })
                 }
             }
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
                             .rotationEffect(showFolderCreationPopover ? .degrees(45) : .degrees(0))
                             .animation(.easeIn, value: showFolderCreationPopover)
                             .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                     }
                 }
                 ToolbarItem(placement: .navigationBarTrailing) {
                     NavigationLink(destination: Profile()) {
                         Image(systemName: "person.fill")
                             .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                     }
                 }
             }
         }

        // .navigationViewStyle(StackNavigationViewStyle())
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
                         let newFolder = Folder(id: UUID(), name: newFolderName, hasDocuments: false)
                         createFolder(folder: newFolder)
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
                 .frame(width: geometry.size.width * 0.8, height: geometry.size.height * 0.6)
                 .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
             }
         }
         .onAppear {
             fetchFolders { fetchedFolders in
                 // Exclude "Recent" folder if it exists in the fetched list
                 var folders = fetchedFolders.filter { $0.name.lowercased() != "recent" }
                     .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

                 // Check if the "Recent" folder already exists
                 let recentFolderExists = fetchedFolders.contains { $0.name.lowercased() == "recent" }

                 // Create or get the "Recent" folder
                 let recentFolder: Folder
                 if !recentFolderExists {
                     recentFolder = Folder(id: UUID(), name: "Recent", hasDocuments: false)
                     createFolder(folder: recentFolder)
                 } else {
                     recentFolder = fetchedFolders.first { $0.name.lowercased() == "recent" }!
                 }

                 // Insert "Recent" folder at the top
                 folders.insert(recentFolder, at: 0)

                 // Update availableFolders
                 self.folders = folders
             }
         }


         .searchable(text: $searchText, prompt: "Search folders")
         .alert(isPresented: $showAlert) {
             Alert(
                 title: Text("Cannot Delete Folder"),
                 message: Text("This folder contains documents and cannot be deleted."),
                 dismissButton: .default(Text("OK"))
             )
         }
         .alert(isPresented: $showAlert2) {
             Alert(
                 title: Text("Cannot Delete Recent Folder"),
                 message: Text("This folder is default and can't be deleted."),
                 dismissButton: .default(Text("OK"))
             )
         }
     }
     
     private func isSelectedFolder(_ folder: Folder) -> Bool {
         return selectedFolder == folder
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
             "name": folder.name, // Use folder.name instead of newFolderName
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

             // Find the insertion index based on alphabetical order
             if let insertionIndex = self.folders.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(newFolder.name) == .orderedDescending }) {
                 self.folders.insert(newFolder, at: insertionIndex)
             }
             else {
                 self.folders.append(newFolder)
             }
         }
     }
 }
 */























/*
 
 import SwiftUI
 import FirebaseFirestore
 import PDFKit

 struct Folder: Identifiable {
     let id: UUID
     let name: String
     let hasDocuments: Bool // New property to track if the folder has documents
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
     @State private var selectedFolder: Folder? = nil
     @State private var newFolderName = ""
     @State private var showFolderCreationPopover = false
     @State private var searchText = ""
     @State private var isLongPressActive = false // Track long-press
     @State private var selectedDeleteFolder: Folder? = nil // Track the folder to delete
     @State private var showAlert = false // Track whether to show an alert
     @State private var showAlert2 = false // Track whether to show an alert
     @Environment(\.colorScheme) var colorScheme
     @State private var hasDocuments = false
     @State private var isContextMenuActive = false // Track whether the context menu is active

     var body: some View {
         NavigationStack {
             ZStack {
                 Color.gray.opacity(0.2).edgesIgnoringSafeArea(.all)

                 List(folders.filter { searchText.isEmpty ? true : $0.name.localizedCaseInsensitiveContains(searchText) }) { folder in
                     NavigationLink(value: folder) {
                         HStack {
                             Image(systemName: "folder.fill")
                                 .foregroundColor(Color.yellow)
                             Text(folder.name)
                                 .font(.headline)
                         }
                         .padding()
                         .frame(maxWidth: .infinity, alignment: .leading)
                         .cornerRadius(8)
                         .overlay(
                             RoundedRectangle(cornerRadius: 8)
                                 .stroke(Color(red: 0.2, green: 0.5, blue: 0.3).opacity(0.2), lineWidth: 2)
                         )
                     }
                     .padding(.vertical, 5)
                     .contextMenu {
                         Button(action: {
                             isLongPressActive = true
                             selectedDeleteFolder = folder
                         }) {
                             Label("Delete", systemImage: "trash")
                                 .foregroundColor(.red)
                         }
                     }
                 }
                 .listStyle(PlainListStyle())
                 .searchable(text: $searchText, prompt: "Search Folders")
                 .navigationDestination(for: Folder.self) { folder in
                     HomePage(selectedFolder: .constant(folder), folders: $folders)
                 }
             }
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
                             .rotationEffect(showFolderCreationPopover ? .degrees(45) : .degrees(0))
                             .animation(.easeIn, value: showFolderCreationPopover)
                             .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                     }
                 }
                 ToolbarItem(placement: .navigationBarTrailing) {
                     NavigationLink(destination: Profile()) {
                         Image(systemName: "person.fill")
                             .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                     }
                 }
             }
         }

        // .navigationViewStyle(StackNavigationViewStyle())
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
                         let newFolder = Folder(id: UUID(), name: newFolderName, hasDocuments: false)
                         createFolder(folder: newFolder)
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
                 .frame(width: geometry.size.width * 0.8, height: geometry.size.height * 0.6)
                 .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
             }
         }
         .onAppear {
             fetchFolders { fetchedFolders in
                 // Exclude "Recent" folder if it exists in the fetched list
                 var folders = fetchedFolders.filter { $0.name.lowercased() != "recent" }
                     .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

                 // Check if the "Recent" folder already exists
                 let recentFolderExists = fetchedFolders.contains { $0.name.lowercased() == "recent" }

                 // Create or get the "Recent" folder
                 let recentFolder: Folder
                 if !recentFolderExists {
                     recentFolder = Folder(id: UUID(), name: "Recent", hasDocuments: false)
                     createFolder(folder: recentFolder)
                 } else {
                     recentFolder = fetchedFolders.first { $0.name.lowercased() == "recent" }!
                 }

                 // Insert "Recent" folder at the top
                 folders.insert(recentFolder, at: 0)

                 // Update availableFolders
                 self.folders = folders
             }
         }


         .searchable(text: $searchText, prompt: "Search folders")
         .alert(isPresented: $showAlert) {
             Alert(
                 title: Text("Cannot Delete Folder"),
                 message: Text("This folder contains documents and cannot be deleted."),
                 dismissButton: .default(Text("OK"))
             )
         }
         .alert(isPresented: $showAlert2) {
             Alert(
                 title: Text("Cannot Delete Recent Folder"),
                 message: Text("This folder is default and can't be deleted."),
                 dismissButton: .default(Text("OK"))
             )
         }
     }
     
     private func isSelectedFolder(_ folder: Folder) -> Bool {
         return selectedFolder == folder
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
             "name": folder.name, // Use folder.name instead of newFolderName
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

             // Find the insertion index based on alphabetical order
             if let insertionIndex = self.folders.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(newFolder.name) == .orderedDescending }) {
                 self.folders.insert(newFolder, at: insertionIndex)
             }
             else {
                 self.folders.append(newFolder)
             }
         }
     }
 }
 */





















/*
 
 import SwiftUI
 import FirebaseFirestore
 import PDFKit

 struct Folder: Identifiable {
     let id: UUID
     let name: String
     let hasDocuments: Bool // New property to track if the folder has documents
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
     @State private var selectedFolder: Folder? = nil
     @State private var newFolderName = ""
     @State private var showFolderCreationPopover = false
     @State private var searchText = ""
     @State private var isLongPressActive = false // Track long-press
     @State private var selectedDeleteFolder: Folder? = nil // Track the folder to delete
     @State private var showAlert = false // Track whether to show an alert
     @State private var showAlert2 = false // Track whether to show an alert
     @Environment(\.colorScheme) var colorScheme
     @State private var hasDocuments = false
     @State private var isContextMenuActive = false // Track whether the context menu is active

     var body: some View {
         ZStack {
             // Background color for the entire view
             Color.gray.opacity(0.2).edgesIgnoringSafeArea(.all)

             List(folders.filter { searchText.isEmpty ? true : $0.name.localizedCaseInsensitiveContains(searchText) }) { folder in
                 NavigationLink(destination: HomePage(selectedFolder: $selectedFolder), tag: folder, selection: $selectedFolder) {
                     HStack {
                         Image(systemName: "folder.fill")
                             .foregroundColor(Color.yellow)
                         Text(folder.name)
                             .font(.headline)
                     }
                     .padding()
                     .frame(maxWidth: .infinity, alignment: .leading)
                     .background(Color(red: 0.2, green: 0.5, blue: 0.3).opacity(0.2))
                     .cornerRadius(8)
                     .overlay(
                         RoundedRectangle(cornerRadius: 8)
                             .stroke(Color(red: 0.2, green: 0.5, blue: 0.3), lineWidth: 2)
                     )
                     .scaleEffect(isSelectedFolder(folder) ? 1.05 : 1.0)
                     .animation(.spring(), value: isSelectedFolder(folder))

                 }
                 .padding(.vertical, 5)
                 .contextMenu {
                     Button(action: {
                         isLongPressActive = true
                         selectedDeleteFolder = folder
                     }) {
                         Label("Delete", systemImage: "trash")
                             .foregroundColor(.red)
                     }
                 }
             }
             .listStyle(PlainListStyle())
             .searchable(text: $searchText, prompt: "Search Folders")
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
                             .rotationEffect(showFolderCreationPopover ? .degrees(45) : .degrees(0))
                             .animation(.easeIn, value: showFolderCreationPopover)
                             .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))
                     }
                 }
                 ToolbarItem(placement: .navigationBarTrailing) {
                     NavigationLink(destination: Profile()) {
                         Image(systemName: "person.fill")
                             .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))

                     }
                 }
             }
         }
         .navigationViewStyle(StackNavigationViewStyle())
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
                         let newFolder = Folder(id: UUID(), name: newFolderName, hasDocuments: false)
                         createFolder(folder: newFolder)
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
                 .frame(width: geometry.size.width * 0.8, height: geometry.size.height * 0.6)
                 .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
             }
         }
         .onAppear {
             fetchFolders { fetchedFolders in
                 // Exclude "Recent" folder if it exists in the fetched list
                 var folders = fetchedFolders.filter { $0.name.lowercased() != "recent" }
                     .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

                 // Check if the "Recent" folder already exists in the fetched data
                 let recentFolderExists = fetchedFolders.contains { $0.name.lowercased() == "recent" }

                 // Create the "Recent" folder if it doesn't exist
                 let recentFolder: Folder
                 if !recentFolderExists {
                     recentFolder = Folder(id: UUID(), name: "Recent", hasDocuments: false)
                     createFolder(folder: recentFolder)
                 } else {
                     recentFolder = fetchedFolders.first { $0.name.lowercased() == "recent" }!
                 }

                 // Insert "Recent" folder at the top of the list
                 folders.insert(recentFolder, at: 0)

                 self.folders = folders
             }
         }

         .searchable(text: $searchText, prompt: "Search folders")
         .alert(isPresented: $showAlert) {
             Alert(
                 title: Text("Cannot Delete Folder"),
                 message: Text("This folder contains documents and cannot be deleted."),
                 dismissButton: .default(Text("OK"))
             )
         }
         .alert(isPresented: $showAlert2) {
             Alert(
                 title: Text("Cannot Delete Recent Folder"),
                 message: Text("This folder is default and can't be deleted."),
                 dismissButton: .default(Text("OK"))
             )
         }
     }
     
     private func isSelectedFolder(_ folder: Folder) -> Bool {
         return selectedFolder == folder
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
             "name": folder.name, // Use folder.name instead of newFolderName
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
 import FirebaseFirestore
 import PDFKit

 struct Folder: Identifiable {
     let id: UUID
     let name: String
     let hasDocuments: Bool // New property to track if the folder has documents
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
     @State private var selectedFolder: Folder? = nil
     @State private var newFolderName = ""
     @State private var showFolderCreationPopover = false
     @State private var searchText = ""
     @State private var isLongPressActive = false // Track long-press
     @State private var selectedDeleteFolder: Folder? = nil // Track the folder to delete
     @State private var showAlert = false // Track whether to show an alert
     @State private var showAlert2 = false // Track whether to show an alert
     @Environment(\.colorScheme) var colorScheme
     @State private var hasDocuments = false
     @State private var isContextMenuActive = false // Track whether the context menu is active

     var body: some View {
         ZStack {
             List(folders.filter { searchText.isEmpty ? true : $0.name.localizedCaseInsensitiveContains(searchText) }) { folder in
                 NavigationLink(destination: HomePage(selectedFolder: $selectedFolder), tag: folder, selection: $selectedFolder) {
                     Text(folder.name)
                         .font(.headline)
                         .padding(10)
                         .foregroundColor(colorScheme == .dark ? .white : .black)
                         .contextMenu {
                             if !isContextMenuActive {
                                 Button(action: {
                                     isLongPressActive = true
                                     selectedDeleteFolder = folder
                                 }) {
                                     Label("Delete", systemImage: "trash")
                                 }
                             }
                         }
                 }
                 .padding(10)
                 .background(Color(uiColor: .systemBackground))
                 .cornerRadius(10)
                 .shadow(color: Color.gray.opacity(0.3), radius: 5, x: 0, y: 2)
             }
             .listStyle(PlainListStyle())
             .searchable(text: $searchText, prompt: "Search Folders")
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
                 }
                 ToolbarItem(placement: .navigationBarTrailing) {
                     NavigationLink(destination: Profile()) {
                         Image(systemName: "person.fill")
                     }
                 }
             }
         }
         .navigationViewStyle(StackNavigationViewStyle())

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
                         let newFolder = Folder(id: UUID(), name: newFolderName, hasDocuments: false)
                         createFolder(folder: newFolder)
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
                 .frame(width: geometry.size.width * 0.8, height: geometry.size.height * 0.6)
                 .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
             }
         }
         .onAppear {
             fetchFolders { fetchedFolders in
                 var folders = fetchedFolders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

                 // Check if the "Recent" folder already exists
                 if folders.first(where: { $0.name.lowercased() == "recent" }) == nil {
                     // If not, create the "Recent" folder and add it to the list
                     let recentFolder = Folder(id: UUID(), name: "Recent", hasDocuments: false)
                     folders.insert(recentFolder, at: 0) // Insert at the beginning of the list
                     createFolder(folder: recentFolder)
                 }

                 self.folders = folders
             }
         }
         .searchable(text: $searchText, prompt: "Search folders")
         .alert(isPresented: $showAlert) {
             Alert(
                 title: Text("Cannot Delete Folder"),
                 message: Text("This folder contains documents and cannot be deleted."),
                 dismissButton: .default(Text("OK"))
             )
         }
         .alert(isPresented: $showAlert2) {
             Alert(
                 title: Text("Cannot Delete Recent Folder"),
                 message: Text("This folder is default and can't be deleted."),
                 dismissButton: .default(Text("OK"))
             )
         }
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
             "name": folder.name, // Use folder.name instead of newFolderName
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
 import FirebaseFirestore
 import PDFKit

 struct Folder: Identifiable {
     let id: UUID
     let name: String
     let hasDocuments: Bool // New property to track if the folder has documents
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
     @State private var selectedFolder: Folder? = nil
     @State private var newFolderName = ""
     @State private var showFolderCreationPopover = false
     @State private var searchText = ""
     @State private var isLongPressActive = false // Track long-press
     @State private var selectedDeleteFolder: Folder? = nil // Track the folder to delete
     @State private var showAlert = false // Track whether to show an alert
     @State private var showAlert2 = false // Track whether to show an alert
     @Environment(\.colorScheme) var colorScheme
     @State private var hasDocuments = false
     @State private var isContextMenuActive = false // Track whether the context menu is active

     var body: some View {
         ZStack {
             List(folders.filter { searchText.isEmpty ? true : $0.name.localizedCaseInsensitiveContains(searchText) }) { folder in
                 NavigationLink(destination: HomePage(selectedFolder: $selectedFolder), tag: folder, selection: $selectedFolder) {
                     Text(folder.name)
                         .font(.headline)
                         .padding(10)
                         .foregroundColor(colorScheme == .dark ? .white : .black)
                         .contextMenu {
                             if !isContextMenuActive { // Check if the context menu is not active
                                 Button(action: {
                                     isLongPressActive = true
                                     selectedDeleteFolder = folder
                                 }) {
                                     Label("Delete", systemImage: "trash")
                                 }
                             }
                         }
                 }
                 .padding(10)
                 .background(
                     // Show delete button for the selected folder
                     Group {
                         if isLongPressActive && selectedDeleteFolder == folder {
                             HStack {
                                 Spacer()
                                 Button(action: {
                                     // Check if the folder has documents
                                     if folder.hasDocuments {
                                         showAlert = true
                                     } else {
                                         // Delete folder action
                                         deleteFolder()
                                     }
                                 }) {
                                     Image(systemName: "trash")
                                         .foregroundColor(.white)
                                         .padding(.vertical, 5)
                                         .padding(.horizontal, 10)
                                         .background(Color.red)
                                         .cornerRadius(10)
                                 }
                             }
                             .padding(.trailing, 20)
                             .transition(.move(edge: .trailing))
                         }
                     }
                 )
             }
             .listStyle(PlainListStyle())
             .onChange(of: showAlert) { newValue in
                 if newValue == true {
                     // Alert is shown, deactivate the context menu
                     isContextMenuActive = true
                 }
             }
             .onDisappear {
                 // Reset states when leaving the view
                 isContextMenuActive = false
                 selectedDeleteFolder = nil
                 isLongPressActive = false
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
                     .foregroundColor(colorScheme == .dark ? .white : .black)
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
                         let newFolder = Folder(id: UUID(), name: newFolderName, hasDocuments: false)
                         createFolder(folder: newFolder)
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
                 .frame(width: geometry.size.width * 0.8, height: geometry.size.height * 0.6)
                 .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
             }
         }
         .onAppear {
             fetchFolders { fetchedFolders in
                 var folders = fetchedFolders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

                 // Check if the "Recent" folder already exists
                 if folders.first(where: { $0.name.lowercased() == "recent" }) == nil {
                     // If not, create the "Recent" folder and add it to the list
                     let recentFolder = Folder(id: UUID(), name: "Recent", hasDocuments: false)
                     folders.insert(recentFolder, at: 0) // Insert at the beginning of the list
                     createFolder(folder: recentFolder)
                 }

                 self.folders = folders
             }
         }
         .searchable(text: $searchText, prompt: "Search folders")
         .alert(isPresented: $showAlert) {
             Alert(
                 title: Text("Cannot Delete Folder"),
                 message: Text("This folder contains documents and cannot be deleted."),
                 dismissButton: .default(Text("OK"))
             )
         }
         .alert(isPresented: $showAlert2) {
             Alert(
                 title: Text("Cannot Delete Recent Folder"),
                 message: Text("This folder is default and can't be deleted."),
                 dismissButton: .default(Text("OK"))
             )
         }
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
             "name": folder.name, // Use folder.name instead of newFolderName
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
