import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

enum MLXConciergeError: LocalizedError {
    case notLoaded

    var errorDescription: String? {
        "The local concierge model is not loaded yet."
    }
}

/// Download-on-demand local LLM used when Apple Intelligence is unavailable.
/// Runs Qwen3-1.7B (4-bit) via MLX — roughly a 1 GB one-time download from
/// Hugging Face, cached in Application Support and excluded from backups.
actor MLXConciergeEngine {
    static let shared = MLXConciergeEngine()

    private static let modelID = "mlx-community/Qwen3-1.7B-4bit"

    // MLX needs Metal on Apple silicon; the iOS simulator can't run it.
    nonisolated static var isSupported: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    nonisolated static var modelsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ConciergeModels", isDirectory: true)
    }

    nonisolated static var isModelDownloaded: Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: modelsDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return false
        }

        for case let url as URL in enumerator where url.pathExtension == "safetensors" {
            return true
        }

        return false
    }

    private var container: ModelContainer?

    /// Downloads the model on first call (reporting 0...1 progress), then
    /// keeps the loaded container for the rest of the session.
    func prepare(progressHandler: (@Sendable (Double) -> Void)? = nil) async throws {
        guard container == nil else { return }

        // Keep the GPU cache small on iPhone so generation stays inside
        // the app's memory limit.
        MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)

        let hub = HubClient(cache: HubCache(cacheDirectory: Self.modelsDirectory))
        let configuration = ModelConfiguration(id: Self.modelID)

        container = try await LLMModelFactory.shared.loadContainer(
            from: #hubDownloader(hub),
            using: #huggingFaceTokenizerLoader(),
            configuration: configuration
        ) { progress in
            progressHandler?(progress.fractionCompleted)
        }

        excludeModelsFromBackup()
    }

    func respond(instructions: String, prompt: String) async throws -> String {
        try await prepare()

        guard let container else {
            throw MLXConciergeError.notLoaded
        }

        let session = ChatSession(
            container,
            instructions: instructions,
            generateParameters: GenerateParameters(maxTokens: 900, temperature: 0.6),
            additionalContext: ["enable_thinking": false]
        )

        return try await session.respond(to: prompt)
    }

    private nonisolated func excludeModelsFromBackup() {
        var directory = Self.modelsDirectory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
    }
}
