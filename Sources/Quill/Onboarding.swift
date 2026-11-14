import AppKit
import SwiftUI

/// The first-run welcome window: what Quill does, the two permissions it needs and why,
/// the speech model's progress, a field to try dictation, and the hotkey choice.
/// Opens by itself on a first launch (`onboardingDone` unset) and from the menu after that.
struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var tryText = ""
    @State private var worked = false
    @FocusState private var tryFocused: Bool

    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            VStack(spacing: 0) {
                microphoneRow
                Divider()
                accessibilityRow
                Divider()
                modelRow
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            tryIt
            HStack {
                Picker("Hold to talk", selection: $model.hotkeyKey) {
                    ForEach(HotkeyKey.allCases) { Text($0.name).tag($0) }
                }
                .fixedSize()
                Spacer()
                Button("Done") {
                    UserDefaults.standard.set(true, forKey: "onboardingDone")
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.refreshPermissions() }
        .onReceive(poll) { _ in model.refreshPermissions() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to Quill").font(.title2.weight(.semibold))
                Text("Hold \(model.hotkeyKey.name), talk, let go: your words appear where you're typing.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var microphoneRow: some View {
        let status = Permissions.microphoneStatus
        return step(
            title: "Microphone",
            why: "Quill listens only while you hold the key, and transcribes on this Mac.",
            granted: model.microphoneGranted,
            statusText: model.microphoneGranted ? "Granted" : status == .denied ? "Denied" : "Not yet"
        ) {
            if !model.microphoneGranted {
                Button(status == .denied ? "Open Settings…" : "Allow Microphone") {
                    if status == .denied { Permissions.openMicrophoneSettings() }
                    else { Task { await model.requestMicrophone() } }
                }
            }
        }
    }

    private var accessibilityRow: some View {
        step(
            title: "Accessibility",
            why: "To notice the key and paste your words into the app you're using.",
            granted: model.accessibilityTrusted,
            statusText: model.accessibilityTrusted ? "Granted" : "Not yet",
            hint: model.accessibilityTrusted ? nil : "Turn Quill on in the list. If the key doesn't respond afterward, quit and reopen Quill."
        ) {
            if !model.accessibilityTrusted {
                Button("Open Settings…") {
                    _ = Permissions.accessibility(prompt: true)
                    Permissions.openAccessibilitySettings()
                }
            }
        }
    }

    private var modelRow: some View {
        let (done, text): (Bool, String) = switch model.state {
        case .loading: (false, "Downloading…")
        case .failed: (false, "Problem")
        default: (true, "Ready")
        }
        return step(
            title: "Speech model",
            why: "About 0.5 GB, once. After that Quill works offline.",
            granted: done,
            statusText: text
        ) { EmptyView() }
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Try it").font(.headline)
                Spacer()
                if worked {
                    Label("It works.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            TextField("Click here, hold \(model.hotkeyKey.name), and say something.", text: $tryText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .focused($tryFocused)
                // A dictation arrives as one paste; typing arrives a character at a time.
                .onChange(of: tryText) { old, new in
                    if new.count - old.count > 2 { worked = true }
                }
        }
    }

    private func step<Action: View>(
        title: String, why: String, granted: Bool, statusText: String, hint: String? = nil,
        @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .font(.title3)
                .foregroundStyle(granted ? Color.green : Color.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title).font(.headline)
                    Text(statusText).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(why).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let hint {
                    Text(hint).font(.caption).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            action()
        }
        .padding(12)
    }
}

/// Lives in the always-built menu-bar label: opens the welcome window once, on a first launch.
/// (The menu's own content isn't built until the menu is clicked, so it can't do this.)
@MainActor
enum FirstLaunch {
    private static var opened = false

    static func openIfNeeded(_ open: () -> Void) {
        guard !opened, !UserDefaults.standard.bool(forKey: "onboardingDone") else { return }
        opened = true
        NSApp.activate(ignoringOtherApps: true)
        open()
    }
}
