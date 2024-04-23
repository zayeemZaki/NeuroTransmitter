import SwiftUI
import Firebase

struct PopUpView: View {
    @Binding var popUpAnnotationContent: String
    var onClose: () -> Void
    let documentURL: URL
    @Binding var selectedPopUpAnnotation: PopUpAnnotation?

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            TextEditor(text: bindingForAnnotationContent())
                .font(.title2)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    LinearGradient(gradient: Gradient(colors: [Color.white, Color.blue.opacity(0.2)]), startPoint: .top, endPoint: .bottom)
                )
                .cornerRadius(15)
                .shadow(color: .blue.opacity(0.5), radius: 20, x: 5, y: 5)
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(Color.blue, lineWidth: 1)
                )
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.3))
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            fetchAnnotationContent()
        }
    }

    private func bindingForAnnotationContent() -> Binding<String> {
        Binding<String>(
            get: { self.popUpAnnotationContent },
            set: { newValue in
                self.popUpAnnotationContent = newValue
                if let annotationID = self.selectedPopUpAnnotation?.annotationID {
                    updateAnnotationContentInFirestore(newValue, documentURL: documentURL, annotationID: annotationID) { success in
                        if success {
                            print("Update successful")
                        } else {
                            print("Failed to update annotation")
                        }
                    }
                } else {
                    print("Annotation ID is nil")
                }
            }
        )
    }

    private func fetchAnnotationContent() {
        guard let annotationID = selectedPopUpAnnotation?.annotationID else {
            print("Annotation ID is nil")
            return
        }
        let db = Firestore.firestore()
        let documentRef = db.collection("popUpAnnotations").document(documentURL.lastPathComponent).collection("annotations").document(annotationID)
        documentRef.getDocument { documentSnapshot, error in
            if let document = documentSnapshot, document.exists {
                self.popUpAnnotationContent = document.data()?["content"] as? String ?? ""
            } else if let error = error {
                print("Error fetching annotation content: \(error)")
            }
        }
    }
    
    private func updateAnnotationContentInFirestore(_ content: String, documentURL: URL, annotationID: String, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
        let documentRef = db.collection("popUpAnnotations").document(documentURL.lastPathComponent).collection("annotations").document(annotationID)
        documentRef.updateData(["content": content]) { error in
            if let error = error {
                print("Error updating document: \(error)")
                completion(false)
            } else {
                print("Document successfully updated")
                completion(true)
            }
        }
    }
}









/*
 import SwiftUI
 import Firebase

 struct PopUpView: View {
     @Binding var popUpAnnotationContent: String
     var onClose: () -> Void
     let documentURL: URL
     @Binding var selectedPopUpAnnotation: PopUpAnnotation?

     var body: some View {
         VStack(alignment: .center, spacing: 10) {
             TextEditor(text: bindingForAnnotationContent())
                 .font(.title2)
                 .padding()
                 .frame(maxWidth: .infinity, maxHeight: .infinity)
                 .background(
                     LinearGradient(gradient: Gradient(colors: [Color.white, Color.blue.opacity(0.2)]), startPoint: .top, endPoint: .bottom)
                 )
                 .cornerRadius(15)
                 .shadow(color: .blue.opacity(0.5), radius: 20, x: 5, y: 5)
                 .overlay(
                     RoundedRectangle(cornerRadius: 15)
                         .stroke(Color.blue, lineWidth: 1)
                 )
         }
         .padding()
         .frame(maxWidth: .infinity, maxHeight: .infinity)
         .background(Color.gray.opacity(0.3))
         .edgesIgnoringSafeArea(.all)
         .onAppear {
             fetchAnnotationContent()
         }
     }

     private func bindingForAnnotationContent() -> Binding<String> {
         Binding<String>(
             get: { self.popUpAnnotationContent },
             set: { newValue in
                 self.popUpAnnotationContent = newValue
                 if let annotationID = self.selectedPopUpAnnotation?.annotationID {
                     updateAnnotationContentInFirestore(newValue, documentURL: documentURL, annotationID: annotationID) { success in
                         if success {
                             print("Update successful")
                         } else {
                             print("Failed to update annotation")
                         }
                     }
                 } else {
                     print("Annotation ID is nil")
                 }
             }
         )
     }

     private func fetchAnnotationContent() {
         guard let annotationID = selectedPopUpAnnotation?.annotationID else {
             print("Annotation ID is nil")
             return
         }
         let db = Firestore.firestore()
         let documentRef = db.collection("popUpAnnotations").document(documentURL.lastPathComponent).collection("annotations").document(annotationID)
         documentRef.getDocument { documentSnapshot, error in
             if let document = documentSnapshot, document.exists {
                 self.popUpAnnotationContent = document.data()?["content"] as? String ?? ""
             } else if let error = error {
                 print("Error fetching annotation content: \(error)")
             }
         }
     }
     
     private func updateAnnotationContentInFirestore(_ content: String, documentURL: URL, annotationID: String, completion: @escaping (Bool) -> Void) {
         let db = Firestore.firestore()
         let documentRef = db.collection("popUpAnnotations").document(documentURL.lastPathComponent).collection("annotations").document(annotationID)
         documentRef.updateData(["content": content]) { error in
             if let error = error {
                 print("Error updating document: \(error)")
                 completion(false)
             } else {
                 print("Document successfully updated")
                 completion(true)
             }
         }
     }
 }

 */
