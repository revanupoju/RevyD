import SwiftUI

struct SettingsView: View {
    @State private var knowledgeDirs: [String] = AppSettings.knowledgeDirectories
    @State private var granolaAutoSync: Bool = AppSettings.granolaAutoSync
    @State private var deepgramKey: String = AppSettings.deepgramAPIKey ?? ""
    @State private var meetingCount: Int = MeetingStore().count()
    @State private var peopleCount: Int = PersonStore().count()
    @State private var docCount: Int = DocumentStore().count()
    @State private var commitmentCount: Int = CommitmentStore().openCount()

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            knowledgeTab
                .tabItem { Label("Knowledge", systemImage: "doc.text.magnifyingglass") }
            recordingTab
                .tabItem { Label("Recording", systemImage: "mic.circle") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 400)
    }

    // MARK: - General

    var generalTab: some View {
        Form {
            Section("Granola") {
                Toggle("Auto-sync meetings", isOn: $granolaAutoSync)
                    .onChange(of: granolaAutoSync) { _, newValue in
                        AppSettings.granolaAutoSync = newValue
                    }

                HStack {
                    Text("Status:")
                    if GranolaClient.isAvailable {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Connected")
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("Not found")
                    }
                }

                if let lastSync = AppSettings.granolaLastSyncDate {
                    Text("Last sync: \(lastSync, style: .relative) ago")
                        .foregroundColor(.secondary)
                }
            }

            Section("Claude Code") {
                HStack {
                    Text("Status:")
                    if AppSettings.claudeCodePath() != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Found")
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("Not installed")
                    }
                }
            }

            Section("Data") {
                LabeledContent("Meetings", value: "\(meetingCount)")
                LabeledContent("People", value: "\(peopleCount)")
                LabeledContent("Documents indexed", value: "\(docCount)")
                LabeledContent("Open commitments", value: "\(commitmentCount)")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Knowledge

    var knowledgeTab: some View {
        Form {
            Section("Indexed Directories") {
                ForEach(knowledgeDirs.indices, id: \.self) { index in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundColor(.secondary)
                        Text(knowledgeDirs[index])
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(role: .destructive) {
                            knowledgeDirs.remove(at: index)
                            AppSettings.knowledgeDirectories = knowledgeDirs
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button("Add Directory...") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 20)
                    if panel.runModal() == .OK, let url = panel.url {
                        knowledgeDirs.append(url.path)
                        AppSettings.knowledgeDirectories = knowledgeDirs
                    }
                }
            }

            Section("Info") {
                Text("RevyD indexes markdown (.md), PDF, and text files from these directories. Files are searched with FTS5 full-text search and cross-referenced with your meeting data.")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Recording

    var recordingTab: some View {
        Form {
            Section("Deepgram API Key") {
                SecureField("Enter Deepgram API key", text: $deepgramKey)
                    .onChange(of: deepgramKey) { _, newValue in
                        AppSettings.deepgramAPIKey = newValue.isEmpty ? nil : newValue
                    }
                Text("Get a free API key at deepgram.com. Used for meeting transcription when self-recording.")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }

            Section("Self-Recording") {
                Text("Record meetings directly without Granola. Uses ScreenCaptureKit to capture audio and Deepgram for real-time transcription.")
                    .foregroundColor(.secondary)
                    .font(.caption)

                HStack {
                    Text("Status:")
                    if AppSettings.deepgramAPIKey != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Ready")
                    } else {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.yellow)
                        Text("API key required")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - About

    var aboutTab: some View {
        VStack(spacing: 16) {
            if let resourceURL = Bundle.main.resourceURL,
               let img = NSImage(contentsOfFile: resourceURL.appendingPathComponent("CharacterSprites/revy-front@2x.png").path) {
                Image(nsImage: img)
                    .resizable()
                    .frame(width: 80, height: 80)
            }

            Text("RevyD")
                .font(.title.bold())

            Text("AI Chief of Staff")
                .foregroundColor(.secondary)

            Text("v0.1.0")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.6))

            Divider()

            Text("Built with Swift + AppKit + SQLite\nPowered by Claude\nZero external dependencies")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .font(.caption)

            Spacer()
        }
        .padding(32)
    }
}
