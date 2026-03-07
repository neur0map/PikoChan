import Foundation

/// Fetches and caches fal.ai model input schemas so PikoChan can
/// dynamically adapt to each model's text field, voice options, etc.
@MainActor
final class FalAISchema {
    static let shared = FalAISchema()

    struct ModelSchema {
        /// The field name that accepts text input ("text", "prompt", etc).
        let textFieldName: String
        /// A separate prompt/style field for emotion/tone (e.g. "Very happy.").
        /// nil if the model doesn't have one distinct from the text field.
        let promptFieldName: String?
        /// The field name for voice selection, if any.
        let voiceFieldName: String?
        /// Available voice options (from enum), empty if freeform.
        let voices: [String]
        /// Default voice value, if specified.
        let defaultVoice: String?
        /// Whether the model accepts a "speed" parameter.
        let hasSpeed: Bool
    }

    private var cache: [String: ModelSchema] = [:]
    private var inFlight: [String: Task<ModelSchema?, Never>] = [:]

    /// Returns cached schema or fetches it. Returns nil on failure.
    func schema(for modelId: String) async -> ModelSchema? {
        if let cached = cache[modelId] { return cached }

        // Deduplicate concurrent fetches for the same model.
        if let existing = inFlight[modelId] {
            return await existing.value
        }

        let task = Task<ModelSchema?, Never> {
            await fetchSchema(for: modelId)
        }
        inFlight[modelId] = task
        let result = await task.value
        inFlight[modelId] = nil
        if let result { cache[modelId] = result }
        return result
    }

    /// Force-fetch (bypasses cache). Used when user changes model ID.
    func fetchAndCache(modelId: String) async -> ModelSchema? {
        cache[modelId] = nil
        return await schema(for: modelId)
    }

    private func fetchSchema(for modelId: String) async -> ModelSchema? {
        guard var components = URLComponents(string: "https://api.fal.ai/v1/models") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "endpoint_id", value: modelId),
            URLQueryItem(name: "expand", value: "openapi-3.0"),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else { return nil }

        return parseSchema(from: data)
    }

    private func parseSchema(from data: Data) -> ModelSchema? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = root["models"] as? [[String: Any]],
              let first = models.first,
              let openapi = first["openapi"] as? [String: Any],
              let components = openapi["components"] as? [String: Any],
              let schemas = components["schemas"] as? [String: Any]
        else { return nil }

        // Find the *Input schema.
        guard let (_, inputSchema) = schemas.first(where: { key, _ in key.hasSuffix("Input") }),
              let schemaDict = inputSchema as? [String: Any],
              let properties = schemaDict["properties"] as? [String: Any]
        else { return nil }

        let required = schemaDict["required"] as? [String] ?? []

        // Discover text field: prefer "text" if it exists, then "prompt", "input", "transcript".
        let textCandidates = ["text", "prompt", "input", "transcript"]
        let textFieldName = textCandidates.first { properties[$0] != nil } ?? "prompt"

        // Discover separate prompt/style field: only if model has BOTH "text" and "prompt".
        // The "prompt" field is for emotion/tone guidance (e.g. "Very happy.").
        var promptFieldName: String?
        if textFieldName == "text", properties["prompt"] != nil {
            promptFieldName = "prompt"
        }

        // Discover voice field and options.
        // Handle both direct enum and anyOf-wrapped enum patterns.
        var voiceFieldName: String?
        var voices: [String] = []
        var defaultVoice: String?

        if let voiceProp = properties["voice"] as? [String: Any] {
            voiceFieldName = "voice"

            // Direct enum: {"enum": ["a", "b"]}
            if let enumValues = voiceProp["enum"] as? [String] {
                voices = enumValues
            }
            // anyOf pattern: {"anyOf": [{"enum": [...]}, {"type": "null"}]}
            else if let anyOf = voiceProp["anyOf"] as? [[String: Any]] {
                for variant in anyOf {
                    if let enumValues = variant["enum"] as? [String] {
                        voices = enumValues
                        break
                    }
                }
            }
            // Fallback: examples as suggestions.
            if voices.isEmpty, let examples = voiceProp["examples"] as? [String] {
                voices = examples
            }
            if let def = voiceProp["default"] as? String {
                defaultVoice = def
            }
            // If no explicit default but examples exist, use first example.
            if defaultVoice == nil, let examples = voiceProp["examples"] as? [String], let first = examples.first {
                defaultVoice = first
            }
        }

        let hasSpeed = properties["speed"] != nil

        return ModelSchema(
            textFieldName: textFieldName,
            promptFieldName: promptFieldName,
            voiceFieldName: voiceFieldName,
            voices: voices,
            defaultVoice: defaultVoice,
            hasSpeed: hasSpeed
        )
    }
}
