//
//  FetchFolders.swift
//  NeuroTransmitter
//
//  Created by Zayeem Zaki on 8/10/23.
//

import Foundation
import FirebaseFirestore

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
            guard let folderName = folderData["name"] as? String,
                  let folderIdString = folderData["folderId"] as? String,
                  let folderId = UUID(uuidString: folderIdString) else {
                print("Could not fetch")
                return nil
            }
            return Folder(id: folderId, name: folderName)
        }

        completion(fetchedFolders)
    }
}




/*
 import Foundation
 import FirebaseFirestore

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
             guard let folderName = folderData["name"] as? String,
                   let folderIdString = folderData["folderId"] as? String,
                   let folderId = UUID(uuidString: folderIdString) else {
                 print("Could not fetch")
                 return nil
             }
             return Folder(id: folderId, name: folderName)
         }

         completion(fetchedFolders)
     }
 }
 */


