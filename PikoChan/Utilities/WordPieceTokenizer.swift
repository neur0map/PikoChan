import Foundation

/// Minimal BERT WordPiece tokenizer. Loads vocab.txt and produces input_ids + attention_mask.
struct WordPieceTokenizer {
    private let vocab: [String: Int32]  // token → id
    private let unkId: Int32 = 100
    private let clsId: Int32 = 101
    private let sepId: Int32 = 102
    private let padId: Int32 = 0
    let maxLength: Int

    init?(vocabURL: URL, maxLength: Int = 128) {
        guard let text = try? String(contentsOf: vocabURL, encoding: .utf8) else { return nil }
        var map: [String: Int32] = [:]
        for (i, line) in text.components(separatedBy: .newlines).enumerated() {
            let token = line.trimmingCharacters(in: .whitespaces)
            guard !token.isEmpty else { continue }
            map[token] = Int32(i)
        }
        guard !map.isEmpty else { return nil }
        self.vocab = map
        self.maxLength = maxLength
    }

    struct Encoded {
        let inputIds: [Int32]
        let attentionMask: [Int32]
    }

    func encode(_ text: String) -> Encoded {
        let tokens = tokenize(text)
        // Truncate to maxLength - 2 (reserve space for [CLS] and [SEP])
        let maxTokens = maxLength - 2
        let truncated = Array(tokens.prefix(maxTokens))

        var ids: [Int32] = [clsId]
        for token in truncated {
            ids.append(vocab[token] ?? unkId)
        }
        ids.append(sepId)

        var mask = [Int32](repeating: 1, count: ids.count)

        // Pad to maxLength
        while ids.count < maxLength {
            ids.append(padId)
            mask.append(0)
        }

        return Encoded(inputIds: ids, attentionMask: mask)
    }

    // MARK: - WordPiece Tokenization

    private func tokenize(_ text: String) -> [String] {
        let words = preTokenize(text)
        var tokens: [String] = []

        for word in words {
            let subTokens = wordPiece(word)
            tokens.append(contentsOf: subTokens)
        }
        return tokens
    }

    /// Basic pre-tokenization: lowercase, split on whitespace and punctuation.
    private func preTokenize(_ text: String) -> [String] {
        let lowered = text.lowercased()
        var words: [String] = []
        var current = ""

        for char in lowered {
            if char.isWhitespace {
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
            } else if char.isPunctuation || char.isSymbol {
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
                words.append(String(char))
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            words.append(current)
        }
        return words
    }

    /// WordPiece: greedily match the longest subword in vocab.
    private func wordPiece(_ word: String) -> [String] {
        if vocab[word] != nil { return [word] }

        var tokens: [String] = []
        var start = word.startIndex
        var isFirst = true

        while start < word.endIndex {
            var end = word.endIndex
            var matched: String?

            while start < end {
                let substr = String(word[start..<end])
                let candidate = isFirst ? substr : "##\(substr)"
                if vocab[candidate] != nil {
                    matched = candidate
                    break
                }
                end = word.index(before: end)
            }

            guard let token = matched else {
                tokens.append("[UNK]")
                return tokens
            }

            tokens.append(token)
            start = end
            isFirst = false
        }
        return tokens
    }
}
