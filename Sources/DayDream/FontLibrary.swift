import AppKit
import Combine
import CoreText

struct ImportedFont: Identifiable, Equatable {
    let postScriptName: String
    let displayName: String

    var id: String { postScriptName }
}

enum FontLibraryError: LocalizedError {
    case unsupportedFormat
    case invalidFont

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            L10n.t("请选择 TTF、OTF 或 TTC 字体文件。", "Choose a TTF, OTF, or TTC font file.")
        case .invalidFont:
            L10n.t("无法读取这个字体文件。", "This font file could not be read.")
        }
    }
}

final class FontLibrary: ObservableObject {
    static let shared = FontLibrary()

    @Published private(set) var fonts: [ImportedFont] = []

    let directoryURL: URL
    private let fileManager: FileManager
    private let supportedExtensions: Set<String> = ["ttf", "otf", "ttc"]

    init(
        directoryURL: URL = FontLibrary.defaultDirectoryURL(),
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        reload()
    }

    @discardableResult
    func importFont(from sourceURL: URL) throws -> [ImportedFont] {
        guard supportedExtensions.contains(sourceURL.pathExtension.lowercased()) else {
            throw FontLibraryError.unsupportedFormat
        }
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let destination = uniqueDestination(for: sourceURL)
        try fileManager.copyItem(at: sourceURL, to: destination)

        let imported = descriptors(at: destination)
        guard !imported.isEmpty else {
            try? fileManager.removeItem(at: destination)
            throw FontLibraryError.invalidFont
        }
        _ = CTFontManagerRegisterFontsForURL(destination as CFURL, .process, nil)
        reload()
        return imported.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func reload() {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        var byName: [String: ImportedFont] = [:]
        for url in urls where supportedExtensions.contains(url.pathExtension.lowercased()) {
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            for font in descriptors(at: url) {
                byName[font.postScriptName] = font
            }
        }
        fonts = byName.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    nonisolated static func defaultDirectoryURL(
        fileManager: FileManager = .default
    ) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return base.appending(path: "DayDream/Fonts", directoryHint: .isDirectory)
    }

    private func descriptors(at url: URL) -> [ImportedFont] {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)
            as? [CTFontDescriptor] else { return [] }
        return descriptors.compactMap { descriptor in
            guard let name = CTFontDescriptorCopyAttribute(
                descriptor,
                kCTFontNameAttribute
            ) as? String else { return nil }
            let displayName = CTFontDescriptorCopyAttribute(
                descriptor,
                kCTFontDisplayNameAttribute
            ) as? String ?? name
            return ImportedFont(postScriptName: name, displayName: displayName)
        }
    }

    private func uniqueDestination(for sourceURL: URL) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let pathExtension = sourceURL.pathExtension
        var candidate = directoryURL.appending(path: sourceURL.lastPathComponent)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directoryURL.appending(path: "\(baseName) \(suffix).\(pathExtension)")
            suffix += 1
        }
        return candidate
    }
}
