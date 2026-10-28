import SwiftUI
import Carbon.HIToolbox

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Snipping") {
                Toggle(isOn: $settings.autoCopyChanges) {
                    Text("Automatically copy changes")
                    Text("Copy the screenshot to the clipboard again after every edit.")
                }
                Toggle(isOn: $settings.askToSaveEdits) {
                    Text("Ask to save edited screenshots")
                    Text("When you close an edited screenshot without saving it.")
                }
            }
            Section("Shortcuts") {
                LabeledContent("New snip") {
                    HStack {
                        ShortcutRecorder(shortcut: $settings.snipShortcut)
                        Button("Reset") {
                            settings.snipShortcut = .defaultSnip
                        }
                        .disabled(settings.snipShortcut == .defaultSnip)
                    }
                }
                if !settings.snipShortcutIsAvailable {
                    Text("This shortcut is already used by macOS or another app. Choose a different one.")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
    }
}

/// Click, then press the new key combination. Esc cancels.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stopRecording() : startRecording()
        } label: {
            Text(isRecording ? "Type shortcut…" : shortcut.displayString)
                .frame(minWidth: 110)
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        isRecording = true
        // Let the current shortcut be typed again without triggering a snip.
        HotKeyCenter.shared.unregister()

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            let candidate = Shortcut(event: event)
            guard candidate.isFunctionKey || !candidate.modifiers.subtracting(.shift).isEmpty else {
                NSSound.beep()
                return nil
            }
            stopRecording()
            shortcut = candidate
            return nil
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        AppSettings.shared.registerHotKey()
    }
}
