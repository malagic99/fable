import SwiftUI

/// Modal sheet for creating a new bottle, with name validation.
struct CreateBottleView: View {
    @EnvironmentObject private var bottleManager: BottleManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var windowsVersion: WindowsVersion = .win10
    @State private var errorMessage: String?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $name, prompt: Text("My Bottle"))
                    .onSubmit(create)

                Picker("Windows Version", selection: $windowsVersion) {
                    ForEach(WindowsVersion.allCases) { version in
                        Text(version.displayName).tag(version)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedName.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 380, height: 240)
        .navigationTitle("Create Bottle")
    }

    private func create() {
        guard !trimmedName.isEmpty else { return }
        do {
            try bottleManager.createBottle(name: trimmedName, windowsVersion: windowsVersion)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
