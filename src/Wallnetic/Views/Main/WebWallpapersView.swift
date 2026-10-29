import SwiftUI
import AppKit

struct WebWallpapersView: View {
    @ObservedObject private var engine = WebWallpaperEngine.shared
    @State private var address = ""
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Web wallpapers").font(.largeTitle.bold())
                    Text("A living desktop that follows your pointer.")
                        .font(.title3).foregroundStyle(.secondary)
                }
                HStack(alignment: .center, spacing: 24) {
                    OrbitPreview()
                        .frame(width: 252, height: 156)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Orbit wallpaper preview")
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Orbit").font(.title2.bold())
                        Text("Quiet orbital light, distant stars, and depth that moves with your mouse. Works offline.")
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Use Orbit") { apply(.orbit) }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                    }
                    Spacer(minLength: 0)
                }
                .padding(20).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Use a website").font(.headline)
                    HStack(spacing: 10) {
                        TextField("https://example.com/wallpaper", text: $address)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Website address")
                            .onSubmit { applyAddress() }
                        Button("Apply website") { applyAddress() }
                            .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }.controlSize(.large)
                    Text("Use a site you trust. It can access the internet; browsing data is kept only for this session.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Use a local HTML background").font(.headline)
                        Text("Choose a folder containing index.html and its images or scripts.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open HTML folder…") { importFolder() }.controlSize(.large)
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Label(engine.status, systemImage: engine.isRunning ? "play.circle.fill" : "pause.circle")
                        .font(.headline).accessibilityIdentifier("webWallpaperStatus")
                    if engine.source != nil {
                        HStack {
                            Button(engine.manuallyPaused ? "Resume" : "Pause") {
                                engine.setPaused(!engine.manuallyPaused)
                            }
                            Button("Turn off web wallpaper") { engine.stop() }
                        }.controlSize(.large)
                    }
                    Toggle("React to mouse movement", isOn: $engine.pointerEnabled)
                    Toggle("Restore the active web wallpaper when Wallnetic opens", isOn: $engine.restoreAtLaunch)
                    Text("Desktop icons stay clickable. Motion pauses with the app’s power settings; pages reload when playback resumes. Mouse response depends on the page. Applying a web background turns off video auto-switching.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }.padding(32).frame(maxWidth: 880, alignment: .leading).frame(maxWidth: .infinity)
        }
    }

    private func applyAddress() {
        do { apply(try .website(address)) } catch { self.error = error.localizedDescription }
    }

    private func apply(_ source: WebWallpaperSource) {
        do { try engine.apply(source); error = nil } catch { self.error = error.localizedDescription }
    }

    private func importFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the background folder containing index.html."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        do {
            guard let index = ["index.html", "index.htm"].map({ folder.appendingPathComponent($0) })
                .first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
                throw WebWallpaperSource.SourceError.missingIndex
            }
            var source = try WebWallpaperSource.local(index)
            guard source.url.path.hasPrefix(folder.resolvingSymlinksInPath().standardizedFileURL.path + "/") else {
                throw WebWallpaperSource.SourceError.document
            }
            source.folderBookmark = try folder.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess])
            apply(source)
        } catch { self.error = error.localizedDescription }
    }
}

/// A lightweight still preview: the live WebKit scene only runs after Apply.
private struct OrbitPreview: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.03, green: 0.06, blue: 0.12)))
            for i in 0..<40 {
                let x = CGFloat((i * 73) % 251), y = CGFloat((i * 31) % 151)
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(.white.opacity(0.55)))
            }
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.rotate(by: .degrees(-20))
            for i in 0..<4 {
                let w = CGFloat(120 + i * 24), h = CGFloat(42 + i * 10)
                context.stroke(Path(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h)), with: .color(.cyan.opacity(0.4)), lineWidth: 0.8)
            }
            context.fill(Path(ellipseIn: CGRect(x: 65, y: 13, width: 5, height: 5)), with: .color(.orange.opacity(0.9)))
        }
    }
}
