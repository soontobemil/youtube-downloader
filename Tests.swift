import Foundation

@main
struct CoreTests {
    static func main() throws {
        let expected = "https://www.youtube.com/watch?v=BaW_jenozKc"
        for input in [expected, "  https://youtu.be/BaW_jenozKc?t=3\n", "youtube.com/shorts/BaW_jenozKc", "https://m.youtube.com/watch?v=BaW_jenozKc&list=unwanted", "https://www.youtube.com/live/BaW_jenozKc"] {
            let result = try DownloadCore.canonicalURL(input)
            assert(result == expected)
        }
        for input in ["", "https://evil.test/watch?v=BaW_jenozKc", "https://youtube.com.evil.test/watch?v=BaW_jenozKc", "file:///etc/passwd", "https://youtube.com/playlist?list=123", "https://user@youtube.com/watch?v=BaW_jenozKc", "https://youtube.com:123/watch?v=BaW_jenozKc", "https://youtu.be/--exec", "https://youtube.com/watch?v=abc", "$(touch /tmp/bad)"] {
            do { _ = try DownloadCore.canonicalURL(input); fatalError("Accepted invalid URL: \(input)") } catch LinkError.invalid {} catch { throw error }
        }
        let folder = URL(fileURLWithPath: "/tmp/Folder with spaces & quotes'")
        let reel = "https://www.instagram.com/reel/Chunk8-jurw/"
        for input in [reel, "instagram.com/reels/Chunk8-jurw/?igsh=tracking", "https://www.instagram.com/instagram/reel/Chunk8-jurw/"] {
            let normalized = try DownloadCore.canonicalURL(input)
            assert(normalized == reel && DownloadCore.isInstagram(input))
        }
        assert((try? DownloadCore.canonicalURL("https://instagram.com/p/aye83DjauH/?img_index=2")) == "https://www.instagram.com/p/aye83DjauH/")
        for input in ["https://instagram.com/instagram/", "https://instagram.com/stories/instagram/12345", "https://instagram.com.evil.test/reel/Chunk8-jurw/", "https://user@instagram.com/reel/Chunk8-jurw/", "https://instagram.com:443/reel/Chunk8-jurw/", "https://instagram.com/share/reel/token", "https://instagram.com/reels/audio/123456", "https://instagram.com/p/a%2Fb123", "https://instagram.com/reel/Chunk8-jurw/extra/more"] {
            assert((try? DownloadCore.canonicalURL(input)) == nil, "Accepted invalid Instagram URL: \(input)")
        }
        assert(DownloadCore.sourceName(reel) == "Instagram" && !DownloadCore.isInstagram(expected))
        assert(DownloadCore.thumbnailURL(reel) == nil)
        assert(DownloadCore.remoteImageURL("file:///etc/passwd") == nil)
        let tools = URL(fileURLWithPath: "/tmp/tools")
        let video = DownloadCore.arguments(url: expected, folder: folder, tools: tools, kind: .video, quality: .hd)
        assert(video.suffix(2) == ["--", expected])
        assert(video.contains(folder.path))
        assert(video.contains("bv[height<=720]+ba[ext=m4a]/bv[height<=720]+ba/b[height<=720]"))
        assert(video.contains("%(title)s [%(id)s] [%(height)sp].%(ext)s"))
        assert(video.contains("--ignore-config") && video.contains("--no-playlist") && video.contains("--no-overwrites"))
        assert(video[video.firstIndex(of: "--concurrent-fragments")! + 1] == "8")
        assert(video.contains("--continue") && video.contains("--progress-delta"))
        let normal = DownloadCore.arguments(url: expected, folder: folder, tools: tools, kind: .video, quality: .hd, fast: false)
        assert(normal[normal.firstIndex(of: "--concurrent-fragments")! + 1] == "1")
        assert(DownloadCore.engineURL(tools).path == "/tmp/tools/yt-dlp-runtime/yt-dlp_macos")
        let audio = DownloadCore.arguments(url: expected, folder: folder, tools: tools, kind: .audio, quality: .best)
        assert(audio.contains("ba[ext=m4a]"))
        assert(!audio.contains("--merge-output-format"))
        let instagramAudio = DownloadCore.arguments(url: reel, folder: folder, tools: tools, kind: .audio, quality: .best)
        assert(instagramAudio.contains("--extract-audio") && instagramAudio.contains("ba[ext=m4a]/ba/b"))
        assert(instagramAudio.suffix(2) == ["--", reel])
        let instagramVideo = DownloadCore.arguments(url: reel, folder: folder, tools: tools, kind: .video, quality: .best)
        assert(!instagramVideo.contains("--playlist-items")) // All videos in a single carousel post.
        let fourK = DownloadCore.arguments(url: expected, folder: folder, tools: tools, kind: .video, quality: .ultraHD)
        assert(fourK.contains("bv[height<=2160]+ba[ext=m4a]/bv[height<=2160]+ba/b[height<=2160]"))
        assert(fourK.contains("--remux-video") && fourK.contains("res,vcodec:h264"))
        let best = DownloadCore.arguments(url: expected, folder: folder, tools: tools, kind: .video, quality: .best)
        assert(best.contains("bv+ba[ext=m4a]/bv+ba/b"))
        assert(DownloadCore.jsonString(#""A \"quoted\" title""#) == "A \"quoted\" title")
        assert(DownloadCore.thumbnailURL("https://youtube.com.evil.test/watch?v=BaW_jenozKc") == nil)
        assert(DownloadCore.thumbnailURL(expected)?.absoluteString == "https://i.ytimg.com/vi/BaW_jenozKc/mqdefault.jpg")
        let metadata = DownloadCore.previewArguments(url: expected, tools: tools)
        assert(metadata.contains("--simulate") && metadata.suffix(2) == ["--", expected])
        let preview = try JSONDecoder().decode(VideoPreview.self, from: Data(#"{"id":"BaW_jenozKc","title":"Example","duration":3661,"channel":null,"uploader":"Creator"}"#.utf8))
        assert(preview.durationLabel == "1:01:01" && preview.creator == "Creator")
        let short = try JSONDecoder().decode(VideoPreview.self, from: Data(#"{"id":"BaW_jenozKc","title":"Short","duration":19}"#.utf8))
        assert(short.durationLabel == "0:19" && short.creator == "YouTube")
        let qualities = try JSONDecoder().decode(VideoPreview.self, from: Data(#"{"id":"sample","title":"4K sample","formats":[{"height":720,"vcodec":"avc1"},{"height":1080,"vcodec":"avc1"},{"height":2160,"vcodec":"vp9","has_drm":false},{"height":4320,"vcodec":"av01","has_drm":true},{"height":9000,"vcodec":"none"}]}"#.utf8))
        let igPreview = try JSONDecoder().decode(VideoPreview.self, from: Data(#"{"id":"reel","title":"Video","extractor":"Instagram","thumbnail":"https://cdninstagram.com/image.jpg","playlist_count":2,"formats":[{"height":1280}]}"#.utf8))
        assert(igPreview.creator == "Instagram" && igPreview.maxHeight == 1280 && igPreview.playlist_count == 2)
        assert(igPreview.thumbnailURL?.scheme == "https")
        assert(qualities.maxHeight == 2160)
        assert(qualities.expectedHeight(for: .ultraHD) == 2160)
        assert(qualities.expectedHeight(for: .qhd) == 1080)
        assert(qualities.expectedHeight(for: .best) == 2160)
        assert(DownloadCore.resolutionLabel(2160) == "4K")
        let record = RecentDownload(id: UUID(), title: "Title", path: "/not/a/file.mp4", source: expected, kind: "MP4 video", date: Date())
        let restored = try JSONDecoder().decode(RecentDownload.self, from: JSONEncoder().encode(record))
        assert(restored.id == record.id && restored.path == record.path && !restored.exists)
        let legacy = try JSONDecoder().decode(RecentDownload.self, from: Data(#"{"id":"00000000-0000-0000-0000-000000000001","title":"Old","path":"/tmp/old.mp4","source":"YouTube","kind":"Video","date":0}"#.utf8))
        assert(legacy.thumbnail == nil)
        assert(DownloadCore.friendlyError("ERROR: Sign in to confirm your age").contains("sign-in"))
        assert(DownloadCore.friendlyError("ERROR: Requested format is not available").contains("format"))
        assert(DownloadCore.friendlyError("login required", source: "Instagram").contains("Instagram"))
        assert(DownloadCore.friendlyError("HTTP Error 429", source: "Instagram").contains("limiting"))
        assert(DownloadCore.friendlyError("There is no video in this post", source: "Instagram").contains("Photo-only"))
        print("Passed URL validation, command construction, metadata, thumbnail URLs, history persistence, and error-message checks.")
    }
}
