import Foundation

/// Walks configured directories, extracts text from markdown/PDF files,
/// and indexes them into SQLite FTS5 for knowledge fusion.
final class DocumentIndexer {
    private let documentStore = DocumentStore()
    private let knowledgeIndex = KnowledgeIndex()
    private var isIndexing = false

    var onProgress: ((Int, Int) -> Void)?  // (completed, total)
    var onComplete: ((Int) -> Void)?        // total indexed

    private let supportedExtensions = Set(["md", "markdown", "txt", "pdf"])
    private let maxFileSize = 10 * 1024 * 1024 // 10MB

    /// Index all configured directories
    func indexAll() {
        guard !isIndexing else { return }
        isIndexing = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            let directories = AppSettings.knowledgeDirectories
            var allFiles: [URL] = []

            for dir in directories {
                let url = URL(fileURLWithPath: dir)
                allFiles.append(contentsOf: self.discoverFiles(in: url))
            }

            SessionDebugLogger.log("indexer", "Found \(allFiles.count) files to index")

            var indexed = 0
            for (i, fileURL) in allFiles.enumerated() {
                if self.indexFile(at: fileURL) {
                    indexed += 1
                }
                if i % 10 == 0 {
                    DispatchQueue.main.async {
                        self.onProgress?(i, allFiles.count)
                    }
                }
            }

            DispatchQueue.main.async {
                self.isIndexing = false
                self.onComplete?(indexed)
                SessionDebugLogger.log("indexer", "Indexing complete: \(indexed) files indexed")
            }
        }
    }

    /// Index a single file. Returns true if indexed/updated.
    @discardableResult
    func indexFile(at url: URL) -> Bool {
        let path = url.path
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { return false }

        // Check file size
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int, size <= maxFileSize else { return false }

        // Extract text
        let title: String?
        let content: String

        switch ext {
        case "md", "markdown":
            guard let result = MarkdownExtractor.extractText(from: url) else { return false }
            title = result.title
            content = result.content
        case "pdf":
            guard let text = PDFExtractor.extractText(from: url) else { return false }
            title = url.deletingPathExtension().lastPathComponent
            content = text
        case "txt":
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            title = url.deletingPathExtension().lastPathComponent
            content = text
        default:
            return false
        }

        // Check if content changed
        let hash = DocumentStore.sha256(content)
        if !documentStore.needsReindex(path: path, currentHash: hash) {
            return false // Already indexed with same content
        }

        let modDate = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date ?? Date()
        let now = ISO8601DateFormatter().string(from: Date())
        let modDateStr = ISO8601DateFormatter().string(from: modDate)

        let doc = IndexedDocument(
            id: documentStore.getByPath(path)?.id ?? UUID().uuidString,
            filePath: path,
            fileName: url.lastPathComponent,
            fileType: ext == "pdf" ? "pdf" : "markdown",
            title: title,
            contentText: String(content.prefix(50000)), // Cap at 50K chars
            contentHash: hash,
            indexedAt: now,
            fileModifiedAt: modDateStr
        )

        documentStore.upsert(doc)
        knowledgeIndex.indexDocument(doc)
        return true
    }

    /// Discover all indexable files in a directory recursively
    private func discoverFiles(in directory: URL) -> [URL] {
        var files: [URL] = []
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        while let url = enumerator.nextObject() as? URL {
            let ext = url.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { continue }

            // Skip node_modules, .git, build directories
            let pathStr = url.path
            if pathStr.contains("/node_modules/") || pathStr.contains("/.git/") ||
               pathStr.contains("/build/") || pathStr.contains("/.next/") ||
               pathStr.contains("/dist/") { continue }

            files.append(url)
        }

        return files
    }
}
