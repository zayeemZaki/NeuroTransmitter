//
//  LoadingView.swift
//  NeuroTransmitter
//
//  Created by Zayeem Zaki on 6/22/23.
//

import SwiftUI

struct LoadingView: View {
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack {
            Spacer()
            
            // Neuro Transmitter 
            HStack {
                Text("Neuro")
                    .bold()
                    .font(.largeTitle)
                    .padding(.trailing, -13)
                
                Text("Transmitter")
                    .italic()
                    .bold()
                    .font(.largeTitle)
            }
            .foregroundColor(.white)
            
            
            // Developer information
            Text("Developed by Zayeem")
                .font(.title3)
                .fontWeight(.bold)
                .padding()
                .foregroundColor(.white)
            
            Spacer()
            
            // Loading indicator
            HStack {
                Text("Loading")
                Image(systemName: "circle.dotted")
            }
            .foregroundColor(.white)
            Spacer()
            
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.2, green: 0.5, blue: 0.3))
        .edgesIgnoringSafeArea(.all)
    }
}

struct LoadingView_Previews: PreviewProvider {
    static var previews: some View {
        LoadingView()
    }
}
