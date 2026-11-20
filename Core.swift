import Foundation

enum DownloadKind: String, CaseIterable {
    case video = "Video · MP4"
    case audio = "Audio · M4A"
}

struct VideoPreview: Decodable {
    let id: String
    let title: String
    let duration: Double?
    let channel: String?
    let uploader: String?
    let thumbnail: String?
    let extractor: String?
    let playlist_count: Int?
    var formats: [VideoFormat]?
    var creator: String { channel ?? uploader ?? extractor ?? "YouTube" }
    var thumbnailURL: URL? { DownloadCore.remoteImageURL(thumbnail) }
    var availableHeights: [Int] {
        Array(Set((formats ?? []).filter { $0.vcodec != "none" && $0.has_drm != true }.compactMap(\.height).filter { $0 > 0 })).sorted()
    }
    var maxHeight: Int? { availableHeights.last }
    func expectedHeight(for quality: VideoQuality) -> Int? {
        quality == .best ? maxHeight : availableHeights.filter { $0 <= quality.height }.last
    }
    var durationLabel: String? {
        guard let duration, duration.isFinite, duration >= 0, duration < 31536000 else { return nil }
        let seconds = Int(duration)
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct VideoFormat: Decodable {
    let height: Int?
    let vcodec: String?
    let has_drm: Bool?
}

struct SelectedVideo: Decodable {
    let width: Int?
    let height: Int?
    let vcodec: String?
    var label: String { height.map(DownloadCore.resolutionLabel) ?? "Original" }
}

struct RecentDownload: Codable, Identifiable {
    let id: UUID
    let title: String
    let path: String
    let source: String
    let kind: String
    let date: Date
    var thumbnail: String? = nil
    var fileURL: URL { URL(fileURLWithPath: path) }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }
}

enum VideoQuality: String, CaseIterable {
    case hd = "720p"
    case fullHD = "1080p"
    case qhd = "1440p"
    case ultraHD = "4K · 2160p"
    case best = "Best available"
    var height: Int {
        switch self { case .hd: return 720; case .fullHD: return 1080; case .qhd: return 1440; case .ultraHD: return 2160; case .best: return Int.max }
    }
    var shortLabel: String { self == .ultraHD ? "4K" : self == .best ? "Best" : rawValue }
    var subtitle: String {
        switch self { case .hd: return "Small files"; case .fullHD: return "Full HD"; case .qhd: return "Quad HD"; case .ultraHD: return "Ultra HD"; case .best: return "Highest source quality" }
    }
}

enum LinkError: LocalizedError {
    case invalid
    var errorDescription: String? { "Paste a YouTube video link or an Instagram Reel or video post link." }
}

enum DownloadCore {
    static func isInstagram(_ input: String) -> Bool {
        guard let canonical = try? canonicalURL(input) else { return false }
        return URLComponents(string: canonical)?.host == "www.instagram.com"
    }
    static func sourceName(_ input: String) -> String { isInstagram(input) ? "Instagram" : "YouTube" }
    static func remoteImageURL(_ input: String?) -> URL? {
        guard let input, let url = URL(string: input), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
    static func engineURL(_ tools: URL) -> URL {
        tools.appendingPathComponent("yt-dlp-runtime/yt-dlp_macos")
    }
    static func resolutionLabel(_ height: Int) -> String {
        height == 2160 ? "4K" : height == 4320 ? "8K" : "\(height)p"
    }
    static func thumbnailURL(_ input: String, highQuality: Bool = false) -> URL? {
        guard let canonical = try? canonicalURL(input),
              let id = URLComponents(string: canonical)?.queryItems?.first(where: { $0.name == "v" })?.value else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(id)/\(highQuality ? "hq720" : "mqdefault").jpg")
    }

    static func previewArguments(url: String, tools: URL) -> [String] {
        ["--ignore-config", "--no-playlist", "--no-colors", "--no-warnings", "--no-cache-dir",
         "--simulate", "--playlist-items", "1", "--socket-timeout", "15", "--retries", "0",
         "--js-runtimes", "deno:" + tools.appendingPathComponent("deno").path,
         "--print", "LD_META:%(.{id,title,duration,channel,uploader,thumbnail,extractor,playlist_count})j",
         "--print", "LD_FORMATS:%(formats.:.{height,vcodec,has_drm})j", "--", url]
    }

    static func friendlyError(_ log: String, source: String = "YouTube") -> String {
        let lower = log.lowercased()
        if lower.contains("unable to obtain file audio codec") || lower.contains("does not contain any stream") {
            return "No usable audio track was found in this video. Try saving it as MP4 instead."
        }
        if lower.contains("no video") || lower.contains("only images") || lower.contains("no formats found") {
            return "No downloadable video was found. Photo-only posts aren’t supported."
        }
        if lower.contains("rate-limit") || lower.contains("rate limit") || lower.contains("too many requests") || lower.contains("http error 429") {
            return "\(source) is limiting requests. Wait a while, then try again."
        }
        if lower.contains("sign in") || lower.contains("login") || lower.contains("logged-in") || lower.contains("private video") {
            return "\(source) requires access or sign-in for this video. This app currently supports videos available without signing in."
        }
        if lower.contains("requested format") {
            return "This format isn’t available. Try another quality or switch between video and audio."
        }
        if lower.contains("unavailable") || lower.contains("removed") || lower.contains("not available") {
            return "This video isn’t available. Check that it plays on \(source), then try another link."
        }
        if lower.contains("timed out") || lower.contains("resolve") || lower.contains("network") {
            return "Couldn’t reach \(source). Check your connection and try again."
        }
        if lower.contains("permission denied") || lower.contains("no space") {
            return "Couldn’t save the file. Check free space or choose a different folder."
        }
        return "\(source) couldn’t provide this download. Try again or open Details for more information."
    }

    static func canonicalURL(_ input: String) throws -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.contains("://") { value = "https://" + value }
        guard let url = URLComponents(string: value),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil, url.port == nil,
              let host = url.host?.lowercased() else { throw LinkError.invalid }
        let parts = url.path.split(separator: "/").map(String.init)
        if ["instagram.com", "www.instagram.com", "m.instagram.com"].contains(host) {
            let media = parts.count == 3 ? Array(parts.suffix(2)) : parts
            guard media.count == 2, ["p", "reel", "reels", "tv"].contains(media[0]),
                  media[1].range(of: "^[A-Za-z0-9_-]{6,64}$", options: .regularExpression) != nil,
                  parts.count != 3 || (parts[0] != "share" && parts[0].range(of: "^[A-Za-z0-9_.]+$", options: .regularExpression) != nil)
            else { throw LinkError.invalid }
            return "https://www.instagram.com/\(media[0] == "reels" ? "reel" : media[0])/\(media[1])/"
        }
        var id: String?
        if ["youtu.be", "www.youtu.be"].contains(host), parts.count == 1 {
            id = parts.first
        } else if ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"].contains(host) {
            if url.path == "/watch" { id = url.queryItems?.first(where: { $0.name == "v" })?.value }
            else if parts.count == 2, ["shorts", "embed", "live"].contains(parts[0]) { id = parts[1] }
        }
        guard let videoID = id, videoID.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil else { throw LinkError.invalid }
        return "https://www.youtube.com/watch?v=" + videoID
    }

    static func arguments(url: String, folder: URL, tools: URL, kind: DownloadKind, quality: VideoQuality, fast: Bool = true) -> [String] {
        var args = ["--ignore-config", "--no-playlist", "--no-colors", "--newline", "--progress", "--no-simulate",
                    "--no-overwrites", "--windows-filenames", "--trim-filenames", "160", "--no-cache-dir",
                    "--socket-timeout", "20", "--retries", "3", "--fragment-retries", "3",
                    "--concurrent-fragments", fast ? "8" : "1", "--continue", "--progress-delta", "0.25",
                    "--match-filters", "!is_live", "--ffmpeg-location", tools.path,
                    "--js-runtimes", "deno:" + tools.appendingPathComponent("deno").path,
                    "--paths", folder.path,
                    "--progress-template", "download:LD_PROGRESS:%(progress)j",
                    "--print", "before_dl:LD_TITLE:%(title)j",
                    "--print", "before_dl:LD_THUMB:%(thumbnail)j",
                    "--print", "before_dl:LD_SELECTED:%(.{width,height,vcodec})j",
                    "--print", "after_move:LD_FILE:%(filepath)j"]
        if kind == .video {
            let cap = quality == .best ? "" : "[height<=\(quality.height)]"
            // Permit VP9/AV1 sources: restricting video to MP4 can hide 4K WebM streams.
            // Prefer AVC only at equal resolution; preserve the original video without upscaling.
            args += ["--format", "bv\(cap)+ba[ext=m4a]/bv\(cap)+ba/b\(cap)",
                     "--format-sort", "res,vcodec:h264", "--merge-output-format", "mp4", "--remux-video", "mp4",
                     "--output", "%(title)s [%(id)s] [%(height)sp].%(ext)s",
                     "--postprocessor-args", "Merger+ffmpeg_o:-movflags +faststart"]
        } else if isInstagram(url) {
            // Instagram commonly combines AAC audio and video in one MP4.
            // Extract AAC without re-encoding; convert other audio codecs to M4A.
            args += ["--format", "ba[ext=m4a]/ba/b", "--extract-audio", "--audio-format", "m4a",
                     "--audio-quality", "0", "--output", "%(title)s [%(id)s].%(ext)s"]
        } else {
            // YouTube provides native M4A, so audio downloads need no lossy conversion.
            args += ["--format", "ba[ext=m4a]", "--output", "%(title)s [%(id)s].%(ext)s"]
        }
        return args + ["--", url]
    }

    static func jsonString(_ value: String) -> String? {
        guard let data = value.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) as? String
    }
}
