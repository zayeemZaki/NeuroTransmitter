//
//  SaveUserData.swift
//  NeuroTransmitter
//
//  Created by Zayeem on 11/25/23.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

func saveUserData(withFCMToken fcmToken: String, name: String) {

    var phoneNumber = ""
    var rocketID = ""

    if let userEmail = Auth.auth().currentUser?.email {
        let userData: [String: Any] = [
            "Name": name,
            "RocketID": rocketID,
            "phoneNumber": phoneNumber,
            "isApproved": false,
            "FCMToken": fcmToken
        ]
        
        let userRef = Firestore.firestore().collection("users").document(userEmail)
        userRef.setData(userData) { error in
            if let error = error {
                print("Error saving user data: \(error.localizedDescription)")
            }
            else {
                print("User data saved successfully")
                                }
        }
    }
}
