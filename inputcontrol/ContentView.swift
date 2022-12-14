//
//  ContentView.swift
//  inputcontrol
//
//  Created by Spotlight Deveaux on 2022-09-05.
//

import SwiftUI

struct ContentView: View {
    @State private var status: String = "⏳ Running..."
    @State private var makeshiftLog: String = "Starting..."
    let logNotification = NotificationCenter.default.publisher(for: Notification.Name("NewLogEntry"))

    var body: some View {
        VStack(alignment: .center) {
            Text(status)
            TextEditor(text: .constant(makeshiftLog))
                .onAppear {
                    Task.detached {
                        do {
                            try attemptRequest()
                            status = "✅ Complete!"
                        } catch let e {
                            log(entry: "Encountered an error: \(e)")
                            status = "❌ Failure"
                        }
                    }
                }
                .onReceive(logNotification) { notification in
                    let entry = notification.object as! String
                    makeshiftLog += "\n" + entry
                }
                .font(.custom("Monaco", size: 13))
        }
        .padding()
    }
}

func log(entry: String) {
    DispatchQueue.main.async {
        NotificationCenter.default.post(name: Notification.Name("NewLogEntry"), object: entry)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
