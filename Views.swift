import SwiftUI
import AppKit

private let violet = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(red: 1, green: 0.47, blue: 0.45, alpha: 1)
        : NSColor(red: 0.76, green: 0.11, blue: 0.15, alpha: 1)
})
private let actionViolet = Color(red: 0.82, green: 0.12, blue: 0.16)
private let cardColor = Color(nsColor: .controlBackgroundColor)

struct Thumbnail: View {
    let url: URL?
    var width: CGFloat = 192
    var height: CGFloat = 108
    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                artwork(image)
            } else if phase.error != nil, let url, url.lastPathComponent == "hq720.jpg" {
                AsyncImage(url: url.deletingLastPathComponent().appendingPathComponent("mqdefault.jpg")) { fallback in
                    if let image = fallback.image { artwork(image) }
                    else { placeholder }
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height).clipped().clipShape(RoundedRectangle(cornerRadius: width > 100 ? 12 : 7))
        .accessibilityLabel("Video thumbnail")
    }
    @ViewBuilder private func artwork(_ image: Image) -> some View {
        if width > 100 {
            ZStack {
                image.resizable().scaledToFill().frame(width: width, height: height)
                    .clipped().blur(radius: 20).overlay(.black.opacity(0.45))
                image.resizable().scaledToFit().frame(width: width, height: height)
            }.accessibilityHidden(true)
        } else {
            image.resizable().scaledToFill()
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [violet.opacity(0.20), violet.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "play.rectangle.fill").font(.system(size: width > 100 ? 32 : 19)).foregroundStyle(violet.opacity(0.6))
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: DownloadModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    linkInput
                    VStack(spacing: 18) {
                        HStack(alignment: .top, spacing: 26) {
                            VStack(alignment: .leading, spacing: 14) {
                                previewCard
                                if model.busy || model.savedFile != nil || model.error != nil || model.status == "Download cancelled" { statusCard.frame(width: 360) }
                            }.frame(maxWidth: .infinity, alignment: .topLeading)
                            VStack(alignment: .leading, spacing: 16) {
                                formatSettings
                                downloadBar
                            }.frame(width: 300)
                        }
                        Divider().opacity(0.45)
                        saveLocation
                    }.padding(20).background(cardColor, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.06)))
                    recentDownloads
                }.padding(24)
            }
        }
        .frame(minWidth: 820, idealWidth: 860, maxWidth: 1100, minHeight: 620, idealHeight: 720, maxHeight: 1000)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(violet)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.objectWillChange.send() }
        .sheet(isPresented: $model.showDetails) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Download details").font(.headline)
                ScrollView { Text(model.log).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                HStack { Button("Copy log", action: model.copyLog); Spacer(); Button("Done") { model.showDetails = false }.keyboardShortcut(.cancelAction) }
            }.padding(24).frame(width: 620, height: 380)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
                Image(nsImage: icon).resizable().frame(width: 44, height: 44).accessibilityHidden(true)
            } else {
                Image(systemName: "arrow.down.square.fill").font(.system(size: 38)).foregroundStyle(violet)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Youtube Downloader").font(.system(size: 21, weight: .bold, design: .rounded))
                HStack(spacing: 12) {
                    Label("YouTube", systemImage: "play.rectangle.fill")
                    Label("Instagram", systemImage: "camera")
                }.font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            speedControl
        }.padding(.horizontal, 24).padding(.vertical, 14)
    }

    private var speedControl: some View {
        HStack(spacing: 7) {
            Image(systemName: "bolt.fill").foregroundStyle(violet)
            Text("Fast downloads").font(.system(size: 11, weight: .medium))
            Toggle("Fast downloads", isOn: $model.fastDownloads).labelsHidden().toggleStyle(.switch).controlSize(.mini)
        }.disabled(model.busy).padding(.horizontal, 10).padding(.vertical, 7)
            .background(violet.opacity(0.05), in: Capsule())
            .help("Fetch up to 8 DASH/HLS chunks at once. Actual speed depends on the source and your connection.")
    }

    private var linkInput: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Video link")
            HStack(spacing: 10) {
                Image(systemName: "link").font(.system(size: 16, weight: .medium)).foregroundStyle(violet)
                TextField("Paste a YouTube or Instagram link…", text: $model.link).textFieldStyle(.plain)
                    .font(.system(size: 14)).accessibilityLabel("YouTube or Instagram video link")
                if !model.link.isEmpty {
                    Button(action: model.clearLink) { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(.plain).help("Clear link").accessibilityLabel("Clear link")
                }
                Button("Paste", action: model.paste).keyboardShortcut("v", modifiers: [.command, .shift]).controlSize(.large)
            }
            .padding(12).background(cardColor, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(violet.opacity(0.3), lineWidth: 1))
            .disabled(model.busy)
            if !model.link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.validLink {
                Label("Use a YouTube video link or an Instagram Reel or post link.", systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
            if model.instagram {
                Text("Videos in a carousel save as separate files.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private var previewCard: some View {
        Group {
            if model.validLink {
                VStack(alignment: .leading, spacing: 15) {
                    Thumbnail(url: model.thumbnailURL, width: 360, height: model.instagram ? 260 : 202.5)
                        .overlay(alignment: .bottomTrailing) {
                            if let duration = model.preview?.durationLabel {
                                Text(duration).font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 4)).padding(7)
                            }
                        }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(model.sourceName, systemImage: model.instagram ? "camera" : "play.rectangle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(model.instagram ? Color.pink : violet)
                            if let max = model.preview?.maxHeight {
                                Text("UP TO \(DownloadCore.resolutionLabel(max))").font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(violet).padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(violet.opacity(0.09), in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        Text(model.preview?.title ?? (model.videoTitle.isEmpty ? (model.loadingPreview ? "Getting video details…" : "Your video") : model.videoTitle))
                            .font(.system(size: 17, weight: .semibold)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        if let preview = model.preview {
                            Text(preview.creator).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                            if let count = preview.playlist_count, count > 1 {
                                Text("Post with \(count) items · Preview of the first video").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        } else if model.loadingPreview {
                            HStack(spacing: 7) { ProgressView().controlSize(.mini); Text("Loading preview").font(.system(size: 11)).foregroundStyle(.secondary) }
                        } else if let message = model.previewMessage {
                            Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(width: 360, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [violet.opacity(0.13), violet.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: "play.rectangle.on.rectangle").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(violet)
                    }.frame(width: 360, height: 202.5)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Video preview").font(.system(size: 21, weight: .semibold, design: .rounded))
                        Text("Paste a video link to see its thumbnail and available quality.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                    }
                }.frame(width: 360, alignment: .leading)
            }
        }
    }

    private var formatSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Save as")
            HStack(spacing: 8) {
                formatCard(.video, title: "Video", subtitle: "MP4", symbol: "play.rectangle")
                formatCard(.audio, title: "Audio", subtitle: "M4A", symbol: "waveform")
            }
            if model.kind == .video {
                Picker("Resolution", selection: $model.quality) {
                    ForEach([VideoQuality.best, .ultraHD, .qhd, .fullHD, .hd], id: \.self) { quality in
                        Text(quality.rawValue).tag(quality)
                    }
                }.pickerStyle(.menu).controlSize(.large)
            }
            Text(model.qualityNote).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.disabled(model.busy)
    }

    private func formatCard(_ kind: DownloadKind, title: String, subtitle: String, symbol: String) -> some View {
        let selected = model.kind == kind
        return Button { model.kind = kind } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(selected ? violet : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.padding(11).frame(maxWidth: .infinity)
                .background(selected ? violet.opacity(0.075) : cardColor, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? violet.opacity(0.75) : Color.secondary.opacity(0.13), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityLabel(title + " format").accessibilityValue(selected ? "Selected" : "Not selected")
    }

    private var saveLocation: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder").foregroundStyle(.secondary)
            Text("Save to").font(.system(size: 11)).foregroundStyle(.secondary)
            Button(action: model.openFolder) {
                Text(model.folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle)
            }.buttonStyle(.plain).help("Open save folder")
            Spacer(minLength: 0)
            Button("Change…", action: model.chooseFolder).font(.system(size: 11)).disabled(model.busy)
        }.padding(.vertical, 2)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                if model.busy && model.progress == 0 { ProgressView().controlSize(.small) }
                else { Image(systemName: model.error != nil ? "exclamationmark.circle.fill" : model.savedFile != nil && !model.busy ? "checkmark.circle.fill" : "arrow.down.circle").foregroundStyle(model.error != nil ? Color.orange : model.savedFile != nil && !model.busy ? Color.green : violet) }
                Text(model.status).font(.system(size: 12, weight: .semibold))
                Spacer()
                if !model.log.isEmpty { Button("Details") { model.showDetails = true }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            if model.busy && model.progress > 0 {
                ProgressView(value: model.progress).tint(violet)
                HStack {
                    Text(model.transferred)
                    Spacer()
                    Text("\(model.streamLabel) · \(Int(model.progress * 100))%")
                }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            }
            Text(model.error ?? model.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
            if model.savedFile != nil && !model.busy {
                HStack { Button("Open file", action: model.openSaved); Button("Show in Finder", action: model.reveal) }.controlSize(.small)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(model.error != nil ? Color.orange.opacity(0.07) : violet.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
    }

    private var recentDownloads: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionLabel("Recent downloads")
                Spacer()
                if model.recent.count > 2 {
                    Button(model.showingAllRecent ? "Show less" : "View all (\(model.recent.count))") { model.showingAllRecent.toggle() }
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(violet)
                }
                if !model.recent.isEmpty {
                    Button("Clear list", action: model.clearRecent).buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                        .help("Clear this history. Your downloaded files are kept.")
                }
            }
            if model.recent.isEmpty {
                HStack(spacing: 9) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 15))
                    Text("Your saved videos and audio will appear here.").font(.system(size: 11))
                }.foregroundStyle(.tertiary).padding(.vertical, 6)
            } else {
                ForEach(Array(model.recent.prefix(model.showingAllRecent ? 8 : 2))) { item in
                    HStack(spacing: 12) {
                        Thumbnail(url: DownloadCore.remoteImageURL(item.thumbnail) ?? DownloadCore.thumbnailURL(item.source), width: 64, height: 36)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            HStack(spacing: 7) {
                                Text(DownloadCore.sourceName(item.source))
                                Text("·")
                                Text(item.exists ? item.kind : "File moved or removed")
                                Text("·")
                                Text(item.date, style: .date)
                            }.font(.system(size: 10)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Button { model.openRecent(item) } label: { Image(systemName: "play.circle") }.help("Open file").accessibilityLabel("Open " + item.title).disabled(!item.exists)
                        Button { model.revealRecent(item) } label: { Image(systemName: "folder") }.help("Show in Finder").accessibilityLabel("Reveal " + item.title).disabled(!item.exists)
                    }.buttonStyle(.plain).padding(10).background(cardColor, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }.padding(.top, 1)
    }

    private var downloadBar: some View {
        VStack(spacing: 10) {
            if model.busy {
                Button(model.cancelling ? "Cancelling…" : "Cancel", action: model.cancel).disabled(model.cancelling).keyboardShortcut(.cancelAction)
            }
            Button(action: model.download) {
                Label(model.downloadButtonTitle, systemImage: model.status == "Download cancelled" ? "arrow.clockwise" : "arrow.down")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(actionViolet.gradient, in: RoundedRectangle(cornerRadius: 10))
                    .opacity(model.busy || !model.validLink ? 0.4 : 1)
            }.buttonStyle(.plain).keyboardShortcut(.defaultAction).disabled(model.busy || !model.validLink)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.headline)
    }
}
