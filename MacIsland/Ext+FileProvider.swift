//
//  Ext+FileProvider.swift
//  MacIsland
//
//  Created by Ravindra Singh on 10/08/24.
//

import Cocoa
import Foundation
import UniformTypeIdentifiers

extension NSItemProvider {
    /// Stage a dragged file under our temporary drop area, preserving the
    /// original filename. We try `public.file-url` first because it points
    /// at the real file on disk, then fall back to a `public.item` file
    /// representation. We deliberately avoid `public.data`: providers that
    /// materialize data on demand can synthesize a generic "data" filename,
    /// which is what was dropping the original name.
    func stageDroppedFile() -> URL? {
        // Capture before any callback hop — providers may invalidate state mid-load.
        let suggestedFileName = suggestedName?.nilIfEmpty

        if hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let originalURL = loadFileURLSynchronously() {
            return try? Self.copyToStaging(from: originalURL, fallbackName: suggestedFileName)
        }

        return loadFileRepresentationSynchronously(
            typeIdentifier: UTType.item.identifier,
            fallbackName: suggestedFileName
        )
    }

    private func loadFileURLSynchronously() -> URL? {
        var result: URL?
        let semaphore = DispatchSemaphore(value: 0)
        loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            defer { semaphore.signal() }
            if let data = item as? Data {
                result = URL(dataRepresentation: data, relativeTo: nil)
            } else if let url = item as? URL {
                result = url
            }
        }
        semaphore.wait()
        return result
    }

    private func loadFileRepresentationSynchronously(
        typeIdentifier: String,
        fallbackName: String?
    ) -> URL? {
        var result: URL?
        let semaphore = DispatchSemaphore(value: 0)
        // The temp URL is only valid inside the closure; copy out before signaling.
        _ = loadFileRepresentation(forTypeIdentifier: typeIdentifier) { tempURL, _ in
            defer { semaphore.signal() }
            guard let tempURL else { return }
            result = try? Self.copyToStaging(from: tempURL, fallbackName: fallbackName)
        }
        semaphore.wait()
        return result
    }

    fileprivate static func copyToStaging(from sourceURL: URL, fallbackName: String?) throws -> URL {
        let fileName = resolveFileName(from: sourceURL, fallback: fallbackName)
        let destination = temporaryDirectory
            .appendingPathComponent("TemporaryDrop")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(fileName)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }

    private static func resolveFileName(from sourceURL: URL, fallback: String?) -> String {
        let sourceName = sourceURL.lastPathComponent
        if !sourceName.isEmpty { return sourceName }
        if let fallback { return fallback }
        return UUID().uuidString
    }
}

extension [NSItemProvider] {
    /// Stage all dragged providers. Returns nil and surfaces an alert if any
    /// provider fails — the drop is treated as atomic.
    func stageDroppedFiles() -> [URL]? {
        let urls = compactMap { $0.stageDroppedFile() }
        guard urls.count == count else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSAlert.popError(NSLocalizedString("One or more files failed to load", comment: ""))
            }
            return nil
        }
        return urls
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
