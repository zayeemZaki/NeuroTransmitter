import SwiftUI

struct LoadingView: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // Neuro Transmitter
            Text("Neuro Transmitter")
                .font(.largeTitle)
                .fontWeight(.bold)
                .italic()
                .foregroundColor(.white)
            
            // Developer Information
            Text("Developed by Zayeem")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.white.opacity(0.9))
            
            Spacer()
            
            // Animated Loading Indicator
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(gradient: Gradient(colors: [Color.green.opacity(0.8), Color.blue.opacity(0.8)]), startPoint: .topLeading, endPoint: .bottomTrailing))
        .edgesIgnoringSafeArea(.all)
    }
}


struct LoadingView_Previews: PreviewProvider {
    static var previews: some View {
        LoadingView()
    }
}





/*
 import SwiftUI

 struct LoadingView: View {
     @Environment(\.colorScheme) var colorScheme
     
     var body: some View {
         VStack(spacing: 20) {
             Spacer()
             
             // Neuro Transmitter
             Text("Neuro Transmitter")
                 .font(.largeTitle)
                 .fontWeight(.bold)
                 .italic()
                 .foregroundColor(.white)
             
             // Developer Information
             Text("Developed by Zayeem")
                 .font(.title3)
                 .fontWeight(.medium)
                 .foregroundColor(.white.opacity(0.9))
             
             Spacer()
             
             // Animated Loading Indicator
             ProgressView()
                 .progressViewStyle(CircularProgressViewStyle(tint: .white))
                 .scaleEffect(1.5)

             Spacer()
         }
         .frame(maxWidth: .infinity, maxHeight: .infinity)
         .background(LinearGradient(gradient: Gradient(colors: [Color.green.opacity(0.8), Color.blue.opacity(0.8)]), startPoint: .topLeading, endPoint: .bottomTrailing))
         .edgesIgnoringSafeArea(.all)
     }
 }


 struct LoadingView_Previews: PreviewProvider {
     static var previews: some View {
         LoadingView()
     }
 }
 */





/*

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

 */
