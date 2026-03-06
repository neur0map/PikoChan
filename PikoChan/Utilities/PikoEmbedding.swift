import CoreML
import Accelerate
import NaturalLanguage

/// Embedding engine: Snowflake Arctic Embed XS (384-dim, CoreML) with NLEmbedding fallback.
///
/// Arctic Embed XS is a retrieval-optimized 22M-param model that produces 384-dim
/// normalized embeddings. Queries are prefixed with a retrieval instruction.
/// Falls back to NLEmbedding (512-dim) if the CoreML model can't load.
enum PikoEmbedding {
    enum Embedder: String { case arctic = "arctic_embed_xs", nlEmbedding = "nl_embedding", none }

    static var isAvailable: Bool { activeEmbedder != .none }
    static var dimension: Int {
        switch activeEmbedder {
        case .arctic: 384
        case .nlEmbedding: sentenceEmbedding?.dimension ?? 0
        case .none: 0
        }
    }
    static private(set) var activeEmbedder: Embedder = {
        if arcticModel != nil && arcticTokenizer != nil { return .arctic }
        if sentenceEmbedding != nil { return .nlEmbedding }
        return .none
    }()

    /// Embed text for storage (documents/facts). No query prefix.
    static func embed(_ text: String) -> [Double]? {
        switch activeEmbedder {
        case .arctic: arcticEmbed(text, isQuery: false)
        case .nlEmbedding: sentenceEmbedding?.vector(for: text)
        case .none: nil
        }
    }

    /// Embed text for retrieval (queries). Adds retrieval instruction prefix for Arctic.
    static func embedQuery(_ text: String) -> [Double]? {
        switch activeEmbedder {
        case .arctic: arcticEmbed(text, isQuery: true)
        case .nlEmbedding: sentenceEmbedding?.vector(for: text)
        case .none: nil
        }
    }

    static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Double = 0
        var normA: Double = 0
        var normB: Double = 0
        vDSP_dotprD(a, 1, b, 1, &dot, vDSP_Length(a.count))
        vDSP_svesqD(a, 1, &normA, vDSP_Length(a.count))
        vDSP_svesqD(b, 1, &normB, vDSP_Length(b.count))
        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0 else { return 0 }
        return dot / denom
    }

    // MARK: - Arctic Embed XS (CoreML)

    private static let queryPrefix = "Represent this sentence for searching relevant passages: "

    private static func arcticEmbed(_ text: String, isQuery: Bool) -> [Double]? {
        guard let model = arcticModel, let tokenizer = arcticTokenizer else { return nil }
        let input = isQuery ? queryPrefix + text : text
        let encoded = tokenizer.encode(input)

        guard let idsArray = try? MLMultiArray(shape: [1, NSNumber(value: tokenizer.maxLength)], dataType: .int32),
              let maskArray = try? MLMultiArray(shape: [1, NSNumber(value: tokenizer.maxLength)], dataType: .int32)
        else { return nil }

        for i in 0..<tokenizer.maxLength {
            idsArray[[0, NSNumber(value: i)]] = NSNumber(value: encoded.inputIds[i])
            maskArray[[0, NSNumber(value: i)]] = NSNumber(value: encoded.attentionMask[i])
        }

        guard let provider = try? MLDictionaryFeatureProvider(dictionary: [
            "ids": MLFeatureValue(multiArray: idsArray),
            "mask": MLFeatureValue(multiArray: maskArray),
        ]) else { return nil }

        guard let prediction = try? model.prediction(from: provider) else { return nil }

        // Extract embedding from output (first feature that's a multi-array).
        for name in prediction.featureNames {
            if let arr = prediction.featureValue(for: name)?.multiArrayValue {
                let count = arr.count
                guard count > 0 else { continue }
                let ptr = arr.dataPointer.bindMemory(to: Float.self, capacity: count)
                return (0..<count).map { Double(ptr[$0]) }
            }
        }
        return nil
    }

    private static let arcticModel: MLModel? = {
        guard let url = Bundle.main.url(forResource: "ArcticEmbedXS", withExtension: "mlmodelc") else {
            return nil
        }
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        return try? MLModel(contentsOf: url, configuration: config)
    }()

    private static let arcticTokenizer: WordPieceTokenizer? = {
        guard let url = Bundle.main.url(forResource: "arctic_vocab", withExtension: "txt") else {
            return nil
        }
        return WordPieceTokenizer(vocabURL: url, maxLength: 128)
    }()

    // MARK: - NLEmbedding Fallback

    private static let sentenceEmbedding: NLEmbedding? = {
        NLEmbedding.sentenceEmbedding(for: .english)
    }()
}
