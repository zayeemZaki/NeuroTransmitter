import SwiftUI

struct MoveDocumentView: View {
    @Binding var showMoveDocumentView: Bool
    let document: Document // Single document to move
    let availableFolders: [Folder]
    @Binding var selectedFolder: Folder?
    let moveAction: (Folder) -> Void
    @Binding var selectedFolderIndex: Int 
    
    var body: some View {
        NavigationView {
            VStack {
                Picker("Select Folder", selection: $selectedFolderIndex) {
                    ForEach(0..<availableFolders.count, id: \.self) { index in
                        Text(self.availableFolders[index].name).tag(index)
                    }
                }
                .pickerStyle(.wheel)
                .padding()
                Button("Move Documents") {
                    if availableFolders.indices.contains(selectedFolderIndex) {
                        let selectedFolder = availableFolders[selectedFolderIndex]
                        moveAction(selectedFolder)
                    } else {
                        print("Selected folder index is out of range.")
                        // Handle the error or adjust the index
                        selectedFolderIndex = availableFolders.indices.first ?? -1
                    }
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
        .onAppear {
            if !availableFolders.isEmpty {
                selectedFolderIndex = 0
            } else {
                selectedFolderIndex = -1  // Set to -1 or any invalid index to indicate 'no selection'
            }
        }

    }

}
