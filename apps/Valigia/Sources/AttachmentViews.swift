import SwiftUI
import PhotosUI
import QuickLook
import QuickLookThumbnailing
import VisionKit
import UniformTypeIdentifiers
import ValigiaCore

// MARK: - Thumbnails

/// Thumbnail of any attachment (images and PDFs rendered by iOS).
struct AttachmentThumb: View {
    @Environment(\.m3) private var m3
    @Environment(\.displayScale) private var displayScale
    let attachment: Attachment
    var size: CGFloat = 36
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            m3.surfaceContainerHighest
            if let image, DocumentLock.shared.canShow {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: attachment.kind.symbol)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(m3.onSurfaceVariant)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .task(id: attachment.fileName) {
            image = await AttachmentThumbnails.image(for: attachment.fileName, side: size, scale: displayScale)
        }
    }
}

@MainActor
enum AttachmentThumbnails {
    private static var cache: [String: UIImage] = [:]

    static func image(for fileName: String, side: CGFloat, scale: CGFloat) async -> UIImage? {
        let key = "\(fileName)@\(Int(side))"
        if let hit = cache[key] { return hit }
        let url = AttachmentStore.url(named: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side), scale: scale, representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        let img = rep.uiImage
        if cache.count > 300 { cache.removeAll() }
        cache[key] = img
        return img
    }
}

// MARK: - Full screen preview (QuickLook)

/// Opens attachments in the system QuickLook viewer (swipe between them, zoom,
/// share, print). Shown titles are the attachment titles, not the stored names.
@MainActor
enum AttachmentPreview {
    private final class Item: NSObject, QLPreviewItem {
        let url: URL
        let title: String
        init(url: URL, title: String) { self.url = url; self.title = title }
        var previewItemURL: URL? { url }
        var previewItemTitle: String? { title }
    }

    private final class Source: NSObject, QLPreviewControllerDataSource {
        let items: [Item]
        init(items: [Item]) { self.items = items }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { items.count }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { items[index] }
    }

    /// The controller keeps its data source weak: hold it here while visible.
    private static var source: Source?

    static func open(_ attachments: [Attachment], at index: Int) {
        Task { @MainActor in
            guard await DocumentLock.shared.unlock() else { return }
            present(attachments, at: index)
        }
    }

    private static func present(_ attachments: [Attachment], at index: Int) {
        let items = attachments
            .filter { AttachmentStore.exists($0.fileName) }
            .map { Item(url: AttachmentStore.url(named: $0.fileName), title: $0.title) }
        guard !items.isEmpty else {
            AppModel.shared.errorMessage = "Il file non è disponibile su questo iPhone."
            return
        }
        let wanted = attachments.indices.contains(index) ? attachments[index].fileName : nil
        let start = items.firstIndex { $0.url.lastPathComponent == wanted } ?? 0
        let src = Source(items: items)
        source = src
        let controller = QLPreviewController()
        controller.dataSource = src
        controller.currentPreviewItemIndex = start
        topController()?.present(controller, animated: true)
    }

    static func topController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

// MARK: - Editor

/// "Attachments" section: grid with previews, add from gallery / camera /
/// document scanner / Files, rename, reorder, delete. Works on a binding so it
/// can edit an item draft or a trip's documents.
struct AttachmentsEditor: View {
    @Environment(\.m3) private var m3
    @Binding var attachments: [Attachment]
    var emptyText = "Foto, PDF e altri file: biglietti, prenotazioni, istruzioni, ricevute."

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showPhotos = false
    @State private var showCamera = false
    @State private var showScanner = false
    @State private var showFiles = false
    @State private var renaming: Attachment?
    @State private var renameText = ""
    @State private var importing = false

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if attachments.isEmpty {
                Text(emptyText)
                    .font(.m3BodySmall)
                    .foregroundStyle(m3.onSurfaceVariant)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Array(attachments.enumerated()), id: \.element.id) { index, a in
                        tile(a, index: index)
                    }
                }
            }
            HStack {
                addMenu
                if importing { ProgressView().padding(.leading, 6) }
                Spacer()
                if !attachments.isEmpty {
                    Text(ByteFormat.string(attachments.reduce(0) { $0 + $1.byteSize }))
                        .font(.m3LabelMedium).foregroundStyle(m3.onSurfaceVariant)
                }
            }
        }
        .padding(.vertical, 4)
        .photosPicker(isPresented: $showPhotos, selection: $pickerItems, maxSelectionCount: 20, matching: .images)
        .onChange(of: pickerItems) { _, items in importPhotos(items) }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .image, .item], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            let added = urls.compactMap { AttachmentStore.importFile(at: $0) }
            if added.count < urls.count { AppModel.shared.errorMessage = "Alcuni file non sono stati letti." }
            attachments += added
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in
                if let img, let a = AttachmentStore.importImage(img) { attachments.append(a) }
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScanner { pdf in
                if let pdf, let a = AttachmentStore.importData(pdf, originalName: "Scansione.pdf", title: "Scansione") {
                    attachments.append(a)
                }
                showScanner = false
            }
            .ignoresSafeArea()
        }
        .alert("Rinomina allegato", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Titolo", text: $renameText)
            Button("Annulla", role: .cancel) { renaming = nil }
            Button("Salva") {
                if let r = renaming { attachments.rename(r.id, to: renameText) }
                renaming = nil
            }
        }
    }

    private var addMenu: some View {
        Menu {
            Button { showPhotos = true } label: { Label("Foto dalla galleria", systemImage: "photo.on.rectangle") }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: { Label("Scatta una foto", systemImage: "camera") }
            }
            if VNDocumentCameraViewController.isSupported {
                Button { showScanner = true } label: { Label("Scansiona documento", systemImage: "doc.viewfinder") }
            }
            Button { showFiles = true } label: { Label("Da File (PDF, immagini…)", systemImage: "folder") }
        } label: {
            Label("Aggiungi", systemImage: "paperclip")
                .font(.m3LabelLarge)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .foregroundStyle(m3.onSecondaryContainer)
                .background(m3.secondaryContainer, in: Capsule())
        }
    }

    private func tile(_ a: Attachment, index: Int) -> some View {
        Button {
            AttachmentPreview.open(attachments, at: index)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                AttachmentThumb(attachment: a, size: 92)
                    .overlay(alignment: .bottomLeading) {
                        Text(a.kind.label)
                            .font(.m3LabelSmall)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .foregroundStyle(m3.onSurface)
                            .background(.thinMaterial, in: Capsule())
                            .padding(5)
                    }
                Text(a.title)
                    .font(.m3LabelMedium)
                    .foregroundStyle(m3.onSurface)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(width: 92)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { renameText = a.title; renaming = a } label: { Label("Rinomina", systemImage: "pencil") }
            if index > 0 {
                Button { withAnimation { _ = attachments.shift(a.id, by: -1) } } label: { Label("Sposta prima", systemImage: "arrow.left") }
            }
            if index < attachments.count - 1 {
                Button { withAnimation { _ = attachments.shift(a.id, by: 1) } } label: { Label("Sposta dopo", systemImage: "arrow.right") }
            }
            Button(role: .destructive) { withAnimation { _ = attachments.remove(a.id) } } label: { Label("Elimina", systemImage: "trash") }
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        importing = true
        Task {
            var added: [Attachment] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data),
                   let a = AttachmentStore.importImage(img) {
                    added.append(a)
                }
            }
            attachments += added
            pickerItems = []
            importing = false
        }
    }
}

// MARK: - Document scanner (VisionKit) → PDF

struct DocumentScanner: UIViewControllerRepresentable {
    let onFinish: (Data?) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: (Data?) -> Void
        init(onFinish: @escaping (Data?) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var pages: [UIImage] = []
            for i in 0..<scan.pageCount { pages.append(scan.imageOfPage(at: i)) }
            onFinish(Self.pdf(from: pages))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { onFinish(nil) }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { onFinish(nil) }

        /// One PDF page per scanned page (A4-ish width, aspect ratio kept).
        static func pdf(from pages: [UIImage]) -> Data? {
            guard !pages.isEmpty else { return nil }
            let width: CGFloat = 595
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: width, height: 842))
            return renderer.pdfData { ctx in
                for page in pages {
                    let h = width * page.size.height / max(page.size.width, 1)
                    let rect = CGRect(x: 0, y: 0, width: width, height: h)
                    ctx.beginPage(withBounds: rect, pageInfo: [:])
                    page.draw(in: rect)
                }
            }
        }
    }
}
