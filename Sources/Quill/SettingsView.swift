import ServiceManagement
import SwiftUI

/// The Settings window: hotkey, live preview, launch at login, engine, permissions.
struct SettingsView: View {
    @State private var meetingEngine = MeetingEngine.saved
    @State private var micWarmSeconds = Recorder.keepWarmSeconds
    @ObservedObject var model: AppModel
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Hotkey") {
                Picker("Hold to talk", selection: $model.hotkeyKey) {
                    ForEach(HotkeyKey.allCases) { Text($0.name).tag($0) }
                }
                Text("Another key or a click in the first half second cancels (a chord, not dictation).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Dictation") {
                Toggle("Live preview while talking", isOn: $model.livePreview)
                Picker("Keep the mic ready after dictating", selection: $micWarmSeconds) {
                    Text("Off").tag(0.0)
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                    Text("5 minutes").tag(300.0)
                }
                .onChange(of: micWarmSeconds) { _, seconds in
                    UserDefaults.standard.set(seconds, forKey: "micWarmSeconds")
                }
                Text("Quill listens only while the feather is red. Between dictations the mic stays warm so the next one starts instantly; macOS shows its mic indicator, but nothing is recorded until you press the key. Off: the mic opens only while you hold it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginStatus == .enabled },
                    set: setLaunchAtLogin
                ))
                LabeledContent("Status", value: loginText)
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Speech") {
                LabeledContent("Dictation", value: "Parakeet TDT v2 (English)")
                Picker("Meetings", selection: $meetingEngine) {
                    ForEach(MeetingEngine.allCases) { Text($0.name).tag($0) }
                }
                .onChange(of: meetingEngine) { _, engine in
                    UserDefaults.standard.set(engine.rawValue, forKey: "meetingEngine")
                }
            }
            Section("Permissions") {
                permissionRow("Microphone", granted: model.microphoneGranted, open: Permissions.openMicrophoneSettings)
                permissionRow("Accessibility", granted: model.accessibilityTrusted, open: Permissions.openAccessibilitySettings)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: refresh)
        .onReceive(poll) { _ in refresh() }
    }

    private func permissionRow(_ name: String, granted: Bool, open: @escaping () -> Void) -> some View {
        LabeledContent(name) {
            HStack {
                Text(granted ? "Granted" : "Not granted")
                    .foregroundStyle(granted ? Color.secondary : Color.red)
                Button("Open Settings…", action: open)
            }
        }
    }

    private var loginText: String {
        switch loginStatus {
        case .enabled: "Enabled"
        case .notRegistered: "Not registered"
        case .requiresApproval: "Needs approval in System Settings > Login Items"
        case .notFound: "Not found (run the installed app)"
        @unknown default: "Unknown"
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            Log.write("launch at login failed: \(error)")
        }
        loginStatus = SMAppService.mainApp.status
    }

    private func refresh() {
        loginStatus = SMAppService.mainApp.status
        model.refreshPermissions()
    }
}
