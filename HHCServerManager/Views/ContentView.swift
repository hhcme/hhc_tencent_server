import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if let selectedServer = appState.selectedServer {
                ServerWorkspaceView(profile: selectedServer)
            } else {
                ServerBrowserView()
            }
        }
        .alert("Startup Error", isPresented: startupErrorBinding) {
            Button("OK") {
                appState.startupError = nil
            }
        } message: {
            Text(appState.startupError ?? "")
        }
    }

    private var startupErrorBinding: Binding<Bool> {
        Binding(
            get: { appState.startupError != nil },
            set: { isPresented in
                if !isPresented {
                    appState.startupError = nil
                }
            }
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
