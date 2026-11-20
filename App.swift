import SwiftUI
import AppKit

@MainActor
final class DownloadModel: ObservableObject {
    @Published var link = "" { didSet { schedulePreview() } }
    @Published var kind: DownloadKind = .video { didSet { UserDefaults.standard.set(kind.rawValue, forKey: "downloadKind"); if kind != oldValue { resetRetryState() } } }
    @Published var quality: VideoQuality = .fullHD { didSet { UserDefaults.standard.set(quality.rawValue, forKey: "videoQuality"); if quality != oldValue { resetRetryState() } } }
    @Published var folder: URL
    @Published var busy = false
    @Published var cancelling = false
    @Published var progress: Double = 0
    @Published var streamLabel = "Video"
    @Published var status = "Ready when you are"
    @Published var detail = "Paste a YouTube or Instagram link to get started."
    @Published var videoTitle = ""
    @Published var error: String?
    @Published var savedFile: URL?
    @Published var log = ""
    @Published var showDetails = false
    @Published var preview: VideoPreview?
    @Published var loadingPreview = false
    @Published var previewMessage: String?
    @Published var recent: [RecentDownload] = []
    @Published var selectedVideo: SelectedVideo?
    @Published var showingAllRecent = false
    @Published var fastDownloads = true { didSet { UserDefaults.standard.set(fastDownloads, forKey: "fastDownloads") } }
    @Published var transferred = ""
    private var previewCache: [String: (date: Date, preview: VideoPreview)] = [:]
    private var process: Process?
    private var activeID: UUID?
    private var previewProcess: Process?
    private var previewWork: DispatchWorkItem?
    private var previewID: UUID?
    private var previewURL: String?
    private var downloadingURL = ""
    private var completedFiles: [URL] = []
    private var downloadingThumbnail: String?

    var validLink: Bool { (try? DownloadCore.canonicalURL(link)) != nil }
    var thumbnailURL: URL? { preview?.thumbnailURL ?? DownloadCore.thumbnailURL(link, highQuality: true) }
    var sourceName: String { DownloadCore.sourceName(link) }
    var instagram: Bool { DownloadCore.isInstagram(link) }
    var toolsURL: URL? { Bundle.main.resourceURL?.appendingPathComponent("Tools") }
    var downloadButtonTitle: String {
        if busy { return "Downloading…" }
        if status == "Download cancelled" { return "Resume download" }
        if error != nil { return "Try again" }
        return kind == .video ? "Download \(expectedResolution)" : "Download audio"
    }
    var expectedResolution: String {
        if kind == .audio { return "Original audio" }
        if let height = preview?.expectedHeight(for: quality) { return DownloadCore.resolutionLabel(height) }
        return quality == .best ? "best quality" : "up to \(quality.shortLabel)"
    }
    var qualityNote: String {
        guard kind == .video else {
            return instagram ? "Saves audio as M4A. Original AAC is preserved; other codecs are converted." : "Original M4A audio, with no extra compression."
        }
        guard let preview, let max = preview.maxHeight else {
            return loadingPreview ? "Checking available resolutions…" : "Downloads the best source up to your selected resolution."
        }
        if quality != .best && max < quality.height {
            return "This source tops out at \(DownloadCore.resolutionLabel(max)). That’s the quality you’ll get."
        }
        if let height = preview.expectedHeight(for: quality) {
            return "Available in \(DownloadCore.resolutionLabel(height)). Original quality, with no upscaling."
        }
        return "This source has no video at or below this setting. Choose Best."
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: "saveFolder") {
            folder = URL(fileURLWithPath: saved, isDirectory: true)
        } else {
            folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent("Youtube Downloader", isDirectory: true)
        }
        if let data = UserDefaults.standard.data(forKey: "recentDownloads"),
           let saved = try? JSONDecoder().decode([RecentDownload].self, from: data) { recent = Array(saved.prefix(8)) }
        if let value = UserDefaults.standard.string(forKey: "downloadKind"), let kind = DownloadKind(rawValue: value) { self.kind = kind }
        if let value = UserDefaults.standard.string(forKey: "videoQuality"), let quality = VideoQuality(rawValue: value) { self.quality = quality }
        if UserDefaults.standard.object(forKey: "fastDownloads") != nil { fastDownloads = UserDefaults.standard.bool(forKey: "fastDownloads") }
        if let last = UserDefaults.standard.string(forKey: "lastLink"), (try? DownloadCore.canonicalURL(last)) != nil {
            link = last
            DispatchQueue.main.async { self.schedulePreview() }
        }
    }

    func stopPreview() {
        previewWork?.cancel(); previewWork = nil; previewID = nil
        if let task = previewProcess, task.isRunning { task.terminate() }
        previewProcess = nil; loadingPreview = false
    }

    private func schedulePreview() {
        guard !busy else { return }
        let canonical = try? DownloadCore.canonicalURL(link)
        UserDefaults.standard.set(canonical ?? "", forKey: "lastLink")
        guard canonical != previewURL || (canonical == nil && previewURL == nil) else { return }
        stopPreview()
        previewURL = canonical; preview = nil; previewMessage = nil; error = nil; savedFile = nil
        progress = 0; videoTitle = ""; selectedVideo = nil; status = "Ready when you are"; detail = "Paste a YouTube or Instagram link to get started."
        guard let canonical else { return }
        if let cached = previewCache[canonical], Date().timeIntervalSince(cached.date) < 300 {
            preview = cached.preview
            return
        }
        loadingPreview = true
        let id = UUID(); previewID = id
        let work = DispatchWorkItem { [weak self] in self?.fetchPreview(canonical, id: id) }
        previewWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: work)
    }

    private func fetchPreview(_ canonical: String, id: UUID) {
        guard previewID == id, let tools = toolsURL else { return }
        let task = Process(), pipe = Pipe()
        task.executableURL = DownloadCore.engineURL(tools)
        task.arguments = DownloadCore.previewArguments(url: canonical, tools: tools)
        task.standardOutput = pipe; task.standardError = pipe; task.standardInput = FileHandle.nullDevice
        previewProcess = task
        do { try task.run() }
        catch { loadingPreview = false; previewMessage = "Preview unavailable. You can still try downloading."; return }
        DispatchQueue.global(qos: .utility).async {
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            task.waitUntilExit()
            let line = output.split(separator: "\n").first(where: { $0.hasPrefix("LD_META:") })
            var parsed = line.flatMap { String($0.dropFirst("LD_META:".count)).data(using: .utf8) }
                .flatMap { try? JSONDecoder().decode(VideoPreview.self, from: $0) }
            if let formats = output.split(separator: "\n").first(where: { $0.hasPrefix("LD_FORMATS:") }),
               let data = String(formats.dropFirst("LD_FORMATS:".count)).data(using: .utf8) {
                parsed?.formats = try? JSONDecoder().decode([VideoFormat].self, from: data)
            }
            let result = parsed
            DispatchQueue.main.async {
                guard self.previewID == id else { return }
                self.previewProcess = nil; self.loadingPreview = false
                self.preview = result
                if let result {
                    if self.previewCache.count >= 12 { self.previewCache.removeAll() }
                    self.previewCache[canonical] = (Date(), result)
                }
                self.previewMessage = result == nil ? DownloadCore.friendlyError(output, source: DownloadCore.sourceName(canonical)) : nil
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { [weak self] in
            guard let self, self.previewID == id, self.loadingPreview else { return }
            self.stopPreview()
            self.previewMessage = "Preview took too long. You can still try downloading."
        }
    }

    func clearLink() { guard !busy else { return }; link = "" }
    private func resetRetryState() {
        guard !busy else { return }
        if status == "Download cancelled" || error != nil { status = "Ready when you are"; error = nil }
    }
    func openFolder() { NSWorkspace.shared.open(folder) }
    func openSaved() { if let file = savedFile { NSWorkspace.shared.open(file) } }
    func openRecent(_ item: RecentDownload) { if item.exists { NSWorkspace.shared.open(item.fileURL) } }
    func revealRecent(_ item: RecentDownload) { if item.exists { NSWorkspace.shared.activateFileViewerSelecting([item.fileURL]) } }
    func clearRecent() { recent = []; UserDefaults.standard.removeObject(forKey: "recentDownloads") }

    private func remember(_ file: URL) {
        let title = videoTitle.isEmpty ? (preview?.title ?? file.deletingPathExtension().lastPathComponent) : videoTitle
        recent.removeAll(where: { $0.path == file.path })
        recent.insert(RecentDownload(id: UUID(), title: title, path: file.path, source: downloadingURL, kind: kind == .video ? "MP4 · \(selectedVideo?.label ?? "Video")" : "M4A audio", date: Date(), thumbnail: downloadingThumbnail), at: 0)
        recent = Array(recent.prefix(8))
        if let data = try? JSONEncoder().encode(recent) { UserDefaults.standard.set(data, forKey: "recentDownloads") }
    }

    func paste() { if let value = NSPasteboard.general.string(forType: .string) { link = value; error = nil } }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Save here"
        panel.directoryURL = folder
        if panel.runModal() == .OK, let choice = panel.url {
            folder = choice
            UserDefaults.standard.set(choice.path, forKey: "saveFolder")
        }
    }

    func download() {
        guard !busy else { return }
        error = nil
        let canonical: String
        do { canonical = try DownloadCore.canonicalURL(link) }
        catch { self.error = error.localizedDescription; return }
        guard let resources = Bundle.main.resourceURL else { error = "The app bundle is incomplete."; return }
        let tools = resources.appendingPathComponent("Tools")
        for executable in [DownloadCore.engineURL(tools), tools.appendingPathComponent("ffmpeg"), tools.appendingPathComponent("deno")] {
            guard FileManager.default.isExecutableFile(atPath: executable.path) else {
                error = "Missing download tool: \(executable.lastPathComponent). Reinstall Youtube Downloader."
                return
            }
        }
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { self.error = "Cannot save to this folder. Choose another folder.\n" + error.localizedDescription; return }

        let task = Process()
        let pipe = Pipe()
        stopPreview()
        task.executableURL = DownloadCore.engineURL(tools)
        task.arguments = DownloadCore.arguments(url: canonical, folder: folder, tools: tools, kind: kind, quality: quality, fast: fastDownloads)
        task.standardOutput = pipe
        task.standardError = pipe
        task.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = tools.path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PYTHONUNBUFFERED"] = "1"
        task.environment = environment
        downloadingURL = canonical
        completedFiles = []; downloadingThumbnail = preview?.thumbnail
        UserDefaults.standard.set(kind.rawValue, forKey: "downloadKind")
        UserDefaults.standard.set(quality.rawValue, forKey: "videoQuality")
        busy = true; cancelling = false; progress = 0; savedFile = nil; videoTitle = ""; selectedVideo = nil; log = ""; transferred = ""
        status = "Finding your video…"
        detail = "Checking available formats. This can take a moment."
        let id = UUID()
        activeID = id
        process = task
        do { try task.run() }
        catch {
            busy = false; process = nil; activeID = nil
            self.error = error.localizedDescription
            status = "Couldn’t start download"
            return
        }
        // Drain output off the UI thread. Finish only after the pipe is drained,
        // so the final filename cannot arrive after the success notification.
        DispatchQueue.global(qos: .userInitiated).async {
            var pending = Data()
            while true {
                let data = pipe.fileHandleForReading.availableData
                if data.isEmpty { break }
                pending.append(data)
                while let index = pending.firstIndex(of: 10) {
                    let line = String(decoding: pending[..<index], as: UTF8.self)
                    pending.removeSubrange(...index)
                    DispatchQueue.main.async { self.consume(line, id: id) }
                }
            }
            if !pending.isEmpty {
                let line = String(decoding: pending, as: UTF8.self)
                DispatchQueue.main.async { self.consume(line, id: id) }
            }
            task.waitUntilExit()
            let code = task.terminationStatus
            DispatchQueue.main.async { self.finish(code: code, id: id) }
        }
    }

    private func consume(_ line: String, id: UUID) {
        guard activeID == id else { return }
        if line.hasPrefix("LD_PROGRESS:") {
            guard !cancelling,
                  let data = String(line.dropFirst("LD_PROGRESS:".count)).data(using: .utf8),
                  let info = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
            let downloaded = (info["downloaded_bytes"] as? Double) ?? 0
            let total = (info["total_bytes"] as? Double) ?? (info["total_bytes_estimate"] as? Double) ?? 0
            progress = total > 0 ? min(1, downloaded / total) : 0
            let received = ByteCountFormatter.string(fromByteCount: Int64(downloaded), countStyle: .file)
            transferred = total > 0 ? received + " / " + ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file) : received
            let finished = info["status"] as? String == "finished"
            let filename = (info["filename"] as? String) ?? ""
            streamLabel = kind == .audio || filename.hasSuffix(".m4a") ? "Audio" : "Video"
            status = finished ? "Preparing your file…" : "Downloading \(streamLabel.lowercased())…"
            let speed = (info["speed"] as? Double).map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) + "/s" }
            let eta = (info["eta"] as? Double).map { "\(Int($0))s remaining" }
            detail = finished ? "Finishing this stream and preparing the next step." : [speed, eta].compactMap { $0 }.joined(separator: " · ")
        } else if line.hasPrefix("LD_TITLE:") {
            videoTitle = DownloadCore.jsonString(String(line.dropFirst("LD_TITLE:".count))) ?? "Your video"
            progress = 0; transferred = ""; selectedVideo = nil; downloadingThumbnail = nil
        } else if line.hasPrefix("LD_THUMB:") {
            downloadingThumbnail = DownloadCore.jsonString(String(line.dropFirst("LD_THUMB:".count)))
        } else if line.hasPrefix("LD_SELECTED:") {
            if let data = String(line.dropFirst("LD_SELECTED:".count)).data(using: .utf8) {
                selectedVideo = try? JSONDecoder().decode(SelectedVideo.self, from: data)
            }
        } else if line.hasPrefix("LD_FILE:") {
            if let path = DownloadCore.jsonString(String(line.dropFirst("LD_FILE:".count))), FileManager.default.fileExists(atPath: path) {
                let file = URL(fileURLWithPath: path)
                savedFile = file
                if !completedFiles.contains(file) { completedFiles.append(file) }
                remember(file)
            }
        } else {
            log += line + "\n"
            if log.count > 20000 { log = String(log.suffix(20000)) }
            if line.contains("[Merger]"), !cancelling { status = "Combining video and audio…"; detail = "Almost there." }
            if line.contains("[ExtractAudio]"), !cancelling { status = "Preparing M4A audio…"; detail = "Extracting the audio from your video." }
        }
    }

    private func finish(code: Int32, id: UUID) {
        guard activeID == id else { return }
        process = nil; activeID = nil; busy = false
        if cancelling {
            cancelling = false; savedFile = nil; status = "Download cancelled"
            detail = completedFiles.isEmpty ? "You can try again. Partial files are kept so downloads can resume." : "\(completedFiles.count) completed file(s) are in Recent downloads. Resume to continue the post."
        } else if code == 0, let file = savedFile, FileManager.default.fileExists(atPath: file.path) {
            progress = 1; status = kind == .video ? "Saved in \(selectedVideo?.label ?? "original quality")" : "Audio saved"; detail = file.lastPathComponent
            if completedFiles.count > 1 { status = "Saved \(completedFiles.count) files"; detail = "All completed files are in your save folder. The latest are in Recent downloads." }
        } else {
            savedFile = completedFiles.last
            status = completedFiles.isEmpty ? "Couldn’t download this video" : "Saved \(completedFiles.count) files; some items failed"
            detail = "Check the link and try again."
            error = log.isEmpty ? "No video was saved. Try a public video post or Reel." : DownloadCore.friendlyError(log, source: DownloadCore.sourceName(downloadingURL))
        }
    }

    func cancel() {
        guard let task = process, task.isRunning, !cancelling else { return }
        cancelling = true; status = "Cancelling…"; detail = "Stopping the download safely."
        task.interrupt()
    }

    func reveal() { if let file = savedFile { NSWorkspace.shared.activateFileViewerSelecting([file]) } }
    func copyLog() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(log, forType: .string) }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: DownloadModel?
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.activate(ignoringOtherApps: true) }
    func applicationWillTerminate(_ notification: Notification) { model?.stopPreview() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.busy else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "A download is still running"
        alert.informativeText = "Cancel the download before quitting Youtube Downloader."
        alert.addButton(withTitle: "Keep downloading")
        alert.addButton(withTitle: "Cancel download")
        if alert.runModal() == .alertSecondButtonReturn { model.cancel() }
        return .terminateCancel
    }
}

@main
struct YoutubeDownloaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = DownloadModel()
    var body: some Scene {
        Window("Youtube Downloader", id: "main") {
            ContentView(model: model).onAppear { delegate.model = model }
        }.windowResizability(.contentSize).defaultSize(width: 860, height: 720)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}
