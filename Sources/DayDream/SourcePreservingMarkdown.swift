import Foundation

/// 把编辑器的规范化 Markdown 与加载时的原文对齐。
/// 未改变的行使用原始字节内容；新增或改变的行使用当前规范化结果。
struct SourcePreservingMarkdown {
    private let originalMarkdown: String
    private let canonicalBaseline: String
    private let originalLines: [String]
    private let baselineLines: [String]
    private let usesCRLF: Bool

    init(original: String, canonicalBaseline: String) {
        originalMarkdown = original
        self.canonicalBaseline = canonicalBaseline
        originalLines = Self.lines(in: original)
        baselineLines = Self.lines(in: canonicalBaseline)
        usesCRLF = original.contains("\r\n")
    }

    func merge(canonicalCurrent: String) -> String {
        guard canonicalCurrent != canonicalBaseline else {
            return originalMarkdown
        }

        guard originalLines.count == baselineLines.count else {
            return canonicalWithPreferredLineEndings(canonicalCurrent)
        }

        let currentLines = Self.lines(in: canonicalCurrent)
        let difference = currentLines.difference(from: baselineLines)
        let removedOffsets = Set(difference.compactMap { change -> Int? in
            guard case let .remove(offset, _, _) = change else { return nil }
            return offset
        })
        let insertedOffsets = Set(difference.compactMap { change -> Int? in
            guard case let .insert(offset, _, _) = change else { return nil }
            return offset
        })

        var output: [String] = []
        output.reserveCapacity(currentLines.count)
        var baselineIndex = 0
        var currentIndex = 0

        while currentIndex < currentLines.count {
            if insertedOffsets.contains(currentIndex) {
                output.append(canonicalLine(
                    currentLines[currentIndex],
                    at: currentIndex,
                    totalCount: currentLines.count
                ))
                currentIndex += 1
                continue
            }

            while baselineIndex < baselineLines.count,
                  removedOffsets.contains(baselineIndex) {
                baselineIndex += 1
            }

            guard baselineIndex < baselineLines.count,
                  baselineLines[baselineIndex] == currentLines[currentIndex] else {
                output.append(canonicalLine(
                    currentLines[currentIndex],
                    at: currentIndex,
                    totalCount: currentLines.count
                ))
                currentIndex += 1
                continue
            }

            output.append(originalLines[baselineIndex])
            baselineIndex += 1
            currentIndex += 1
        }

        return output.joined(separator: "\n")
    }

    private func canonicalWithPreferredLineEndings(_ markdown: String) -> String {
        let lines = Self.lines(in: markdown)
        return lines.enumerated().map { index, line in
            canonicalLine(line, at: index, totalCount: lines.count)
        }.joined(separator: "\n")
    }

    private func canonicalLine(_ line: String, at index: Int, totalCount: Int) -> String {
        guard usesCRLF, index < totalCount - 1, !line.hasSuffix("\r") else { return line }
        return line + "\r"
    }

    private static func lines(in markdown: String) -> [String] {
        markdown.components(separatedBy: "\n")
    }
}
