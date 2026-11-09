import UIKit
import SwiftUI
import UniformTypeIdentifiers
import DailyCore

@objc(ShareViewController)
public final class ShareViewController: UIViewController {

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let host = UIHostingController(
            rootView: PrismShareExtensionView(
                extensionContext: extensionContext,
                onComplete: { [weak self] in
                    self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                }
            )
        )
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }
}

private struct PrismShareExtensionView: View {
    let extensionContext: NSExtensionContext?
    let onComplete: () -> Void

    @State private var extractedUrl: String = ""
    @State private var extractedTitle: String = ""
    @State private var extractedText: String = ""
    @State private var extractedImageData: Data? = nil
    @State private var userNote: String = ""
    @State private var isExtracting: Bool = true

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    onComplete()
                }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    HStack(spacing: 7) {
                        Image(systemName: "safari.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(red: 0, green: 0.9, blue: 1.0))
                        Text("Save to Prism Vault")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Button("Cancel") {
                        onComplete()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                }

                if isExtracting {
                    HStack(spacing: 10) {
                        ProgressView().tint(.cyan)
                        Text("Reading shared content...")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.75))
                    }
                    .padding(.vertical, 12)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        if !extractedTitle.isEmpty {
                            Text(extractedTitle)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(2)
                        }
                        if !extractedUrl.isEmpty {
                            Text(extractedUrl)
                                .font(.system(size: 12))
                                .foregroundColor(.cyan.opacity(0.9))
                                .lineLimit(1)
                        }
                        if !extractedText.isEmpty && extractedText != extractedUrl {
                            Text(extractedText)
                                .font(.system(size: 12.5))
                                .foregroundColor(.white.opacity(0.85))
                                .lineLimit(3)
                        }
                        if let data = extractedImageData, let uiImg = UIImage(data: data) {
                            Image(uiImage: uiImg)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 130)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))

                    TextField("Optional note or #tags...", text: $userNote)
                        .font(.system(size: 13.5))
                        .foregroundColor(.white)
                        .padding(11)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                    HStack(spacing: 10) {
                        Button {
                            enqueueAndFinish(openImmediately: false)
                        } label: {
                            Label("Save to Vault", systemImage: "tray.and.arrow.down.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(red: 0, green: 0.9, blue: 1.0), in: Capsule())
                        }

                        if !extractedUrl.isEmpty {
                            Button {
                                enqueueAndFinish(openImmediately: true)
                            } label: {
                                Label("Open in Prism", systemImage: "arrow.up.right.circle.fill")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(Color.white.opacity(0.12), in: Capsule())
                            }
                        }
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color(red: 0.05, green: 0.08, blue: 0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
            )
            .padding(12)
        }
        .task {
            await extractSharedItems()
        }
    }

    @MainActor
    private func extractSharedItems() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            isExtracting = false
            return
        }

        for item in items {
            if let attr = item.attributedContentText?.string, !attr.isEmpty, extractedText.isEmpty {
                extractedText = attr
            }
            if let title = item.attributedTitle?.string, !title.isEmpty, extractedTitle.isEmpty {
                extractedTitle = title
            }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let urlItem = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier),
                       let url = (urlItem as? URL) ?? (urlItem as? NSURL as URL?) {
                        extractedUrl = url.absoluteString
                        if extractedTitle.isEmpty {
                            extractedTitle = PrismSearchEngine.extractCleanDomain(from: url.absoluteString)
                        }
                    }
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let txtItem = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier),
                       let str = txtItem as? String {
                        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                        if (trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://")) && !trimmed.contains(" ") && extractedUrl.isEmpty {
                            extractedUrl = trimmed
                        } else if extractedText.isEmpty {
                            extractedText = trimmed
                        }
                    }
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier), extractedImageData == nil {
                    if let imgItem = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) {
                        if let url = imgItem as? URL, let data = try? Data(contentsOf: url) {
                            extractedImageData = data
                        } else if let img = imgItem as? UIImage {
                            extractedImageData = img.jpegData(compressionQuality: 0.85)
                        } else if let data = imgItem as? Data {
                            extractedImageData = data
                        }
                    }
                }
            }
        }
        isExtracting = false
    }

    private func enqueueAndFinish(openImmediately: Bool) {
        let clipType: PrismClipType
        var savedFileName: String? = nil

        if let rawImg = extractedImageData {
            clipType = .image
            let id = UUID()
            let compressed = PrismAttachmentManager.shared.compressImageData(rawImg)
            let fileName = "shared_\(id.uuidString.lowercased()).jpg"
            let targetUrl = PrismAttachmentManager.shared.cacheDirectoryURL.appendingPathComponent(fileName)
            try? (compressed?.data ?? rawImg).write(to: targetUrl, options: .atomic)
            savedFileName = fileName
        } else if !extractedText.isEmpty && extractedUrl.isEmpty {
            clipType = .quote
        } else {
            clipType = .link
        }

        let combinedNote = [extractedText, userNote]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != extractedUrl }
            .joined(separator: "\n")

        let pending = PrismPendingShareItem(
            clipType: clipType,
            url: extractedUrl,
            title: extractedTitle,
            text: clipType == .quote ? extractedText : combinedNote,
            localImageFileName: savedFileName,
            openImmediatelyInPrism: openImmediately
        )
        PrismStore.enqueueSharedItem(pending)

        // Also hand off via URL query + expiring UIPasteboard fallback so physical devices using wildcard extension profiles sync 100% losslessly
        if let rawImg = extractedImageData, let uiImg = UIImage(data: rawImg) {
            UIPasteboard.general.image = uiImg
        }
        var comps = URLComponents(string: "daily://prism")!
        var q: [URLQueryItem] = [
            URLQueryItem(name: "share_type", value: clipType.rawValue),
            URLQueryItem(name: "open", value: openImmediately ? "1" : "0")
        ]
        if !extractedUrl.isEmpty { q.append(URLQueryItem(name: "url", value: extractedUrl)) }
        if !extractedTitle.isEmpty { q.append(URLQueryItem(name: "title", value: String(extractedTitle.prefix(200)))) }
        let bodyTxt = clipType == .quote ? extractedText : combinedNote
        if !bodyTxt.isEmpty { q.append(URLQueryItem(name: "text", value: String(bodyTxt.prefix(1200)))) }
        comps.queryItems = q
        if let deepUrl = comps.url {
            openHostAppURL(deepUrl)
        }
        onComplete()
    }

    private func openHostAppURL(_ url: URL) {
        var responder: UIResponder? = UIApplication.value(forKeyPath: #keyPath(UIApplication.shared)) as? UIResponder
        let selector = sel_registerName("openURL:")
        while let r = responder {
            if r.responds(to: selector) {
                r.perform(selector, with: url)
                return
            }
            responder = r.next
        }
    }
}
