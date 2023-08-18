//
//  MoveDocumentView.swift
//  NeuroTransmitter
//
//  Created by Zayeem Zaki on 8/12/23.
//

import SwiftUI

struct MoveDocumentView: View {
    @Binding var showMoveDocumentView: Bool
    let selectedDocuments: Set<UUID>
    let availableFolders: [Folder]
    @Binding var selectedFolder: Folder?
    let moveAction: (Folder) -> Void
    
    @Binding var selectedFolderIndex: Int 
    
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
                        //    showMoveDocumentView = false
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

