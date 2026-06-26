import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if let selectedServer = appState.selectedServer {
                ServerWorkspaceView(profile: selectedServer)
                    .id(selectedServer.id)
            } else {
                ServerBrowserView()
            }
        }
        .alert(L10n.string("Startup Error"), isPresented: startupErrorBinding) {
            Button(L10n.string("OK")) {
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
