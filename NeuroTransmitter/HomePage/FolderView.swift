//
//  FolderView.swift
//  NeuroTransmitter
//
//  Created by Zayeem Zaki on 8/10/23.
//

import SwiftUI
import FirebaseFirestore

struct Folder: Identifiable {
    let id: UUID
    let name: String
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




/*
 import SwiftUI
 import FirebaseFirestore

 struct Folder: Identifiable {
     let id: UUID
     let name: String
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
     @State private var showHomePage = false
     @State private var newFolderName = ""
     @State private var showFolderCreationSheet = false
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
             ToolbarItemGroup(placement: .navigationBarLeading) {
                 Text("Folders")
                     .font(.largeTitle)
                     .bold()
                     .padding(10)
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
                 self.folders = fetchedFolders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
 import FirebaseFirestore

 struct Folder: Identifiable {
     let id: UUID
     let name: String
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
     @State private var showHomePage = false
     @State private var newFolderName = ""
     @State private var showFolderCreationSheet = false
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
             ToolbarItemGroup(placement: .navigationBarLeading) {
                 Text("Folders")
                     .font(.largeTitle)
                     .bold()
                     .padding(10)
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
                 self.folders = fetchedFolders
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
             self.folders.append(newFolder)
         }
     }
 }
 */



/*
 import Foundation
 import SwiftUI
 import FirebaseFirestore
 import FirebaseStorage

 struct Folder: Identifiable {
     let id: UUID
     let name: String
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
     @State private var showHomePage = false
     @State private var newFolderName = ""
     @State private var showFolderCreationSheet = false
     
     var body: some View {
         NavigationView {
             List(folders) { folder in
                 NavigationLink(destination: HomePage(selectedFolder: $selectedFolder), tag: folder, selection: $selectedFolder) {
                     HStack {
                         Text(folder.name)
                         Spacer()
                     }
                     .contentShape(Rectangle()) // Make the entire HStack tappable
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
                 self.folders = fetchedFolders // Update the 'folders' array with fetched data
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
         let newFolderId = UUID() // Generate a new UUID for the folder
         
         let newFolderData: [String: Any] = [
             "name": newFolderName,
             "folderId": newFolderId.uuidString // Convert UUID to string
             // Add more properties if needed
         ]
         
         db.collection("Folders").addDocument(data: newFolderData) { error in
             if let error = error {
                 print("Error creating folder: \(error.localizedDescription)")
                 return
             }
             
             let newFolder = Folder(id: newFolderId, name: newFolderName)
             self.folders.append(newFolder) // Update your folders array using 'self'
         }
     }
 }
 */
