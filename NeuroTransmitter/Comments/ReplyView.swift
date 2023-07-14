//
//  ReplyView.swift
//  NeuroTransmitter
//
//  Created by Zayeem Zaki on 6/24/23.
//

import SwiftUI
import Firebase
import FirebaseAuth
import FirebaseFirestore

struct ReplyView: View {
    @Binding var commentMessages: [CommentMessage]
    let selectedCommentIndex: Int
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack {
            Text("Replies of \(selectedCommentIndex + 1)")
                .font(.title)
                .padding()
            List {
                ForEach(commentMessages[selectedCommentIndex].replies.indices, id: \.self) { replyIndex in
                    let reply = commentMessages[selectedCommentIndex].replies[replyIndex]
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("#\(replyIndex + 1)")
                                .foregroundColor(.pink)

                            Text(reply.senderName)
                                .fontWeight(.bold)
                                .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))

                            Text(formatTimestamp(reply.timestamp))
                                .font(.caption)
                                .foregroundColor(.gray)

                            Spacer()
                        }
                        Text(reply.content)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.trailing)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                    .padding(.vertical, 5)
                }
            }
        }
    }
        
    
    
    // Helper function to format the timestamp as a string
    func formatTimestamp(_ timestamp: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}




/*
 import SwiftUI

 struct ReplyView: View {
     @Binding var commentMessages: [CommentMessage]
     let selectedCommentIndex: Int
     @Environment(\.colorScheme) var colorScheme

     var body: some View {
         VStack {
             Text("Replies of \(selectedCommentIndex + 1)")
                 .font(.title)
                 .padding()
             List {
                 ForEach(commentMessages[selectedCommentIndex].replies.indices, id: \.self) { replyIndex in
                     let reply = commentMessages[selectedCommentIndex].replies[replyIndex]
                     VStack(alignment: .leading, spacing: 5) {
                         HStack {
                             Text("#\(replyIndex + 1)")
                                 .foregroundColor(.pink)

                             Text(reply.senderName)
                                 .fontWeight(.bold)
                                 .foregroundColor(Color(red: 0.2, green: 0.5, blue: 0.3))

                             Text(formatTimestamp(reply.timestamp))
                                 .font(.caption)
                                 .foregroundColor(.gray)

                             Spacer()
                         }
                         Text(reply.content)
                             .fixedSize(horizontal: false, vertical: true)
                             .padding(.trailing)
                             .foregroundColor(colorScheme == .dark ? .white : .black)
                     }
                     .padding(.vertical, 5)
                 }
             }
         }
     }
     
     // Helper function to format the timestamp as a string
     func formatTimestamp(_ timestamp: Date) -> String {
         let formatter = DateFormatter()
         formatter.dateStyle = .short
         formatter.timeStyle = .short
         return formatter.string(from: timestamp)
     }
 }
 */
