//
//  SecureFieldWithEyeIcon.swift
//  NeuroTransmitter
//
//  Created by Zayeem on 12/30/23.
//
import SwiftUI

struct SecureFieldWithEyeIcon: View {
    @Binding var text: String
    var placeholder: String
    var color: Color
    var isSecure: Bool
    
    @State private var isTextSecure = true
    
    var body: some View {
        HStack {
            if isSecure {
                if isTextSecure {
                    SecureField(placeholder, text: $text)
                        .foregroundColor(color)
                }
                else {
                    TextField(placeholder, text: $text)
                        .foregroundColor(color)
                }
                Button(action: {
                    isTextSecure.toggle()
                }){
                    Image(systemName: isTextSecure ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(color)
                }
            }
            else {
                SecureField(placeholder, text: $text)
                    .foregroundColor(color)
            }
        }
    }
}
