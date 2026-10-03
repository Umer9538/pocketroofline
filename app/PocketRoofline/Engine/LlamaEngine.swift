import Foundation
import llama

/// Live decode progress, reported every `LlamaEngine.tickInterval` generated tokens.
struct DecodeTick: Sendable {
    let tokensDone: Int
    let windowTokensPerSecond: Double
}

/// One measured repeat. Field meanings match the run schema.
struct BenchSample: Sendable {
    let prefillTokensPerSecond: Double
    let decodeTokensPerSecond: Double
    let ttftMs: Double
}

enum LlamaEngineError: LocalizedError {
    case modelLoadFailed
    case contextCreationFailed
    case decodeFailed(status: Int32)

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed: "The model file could not be loaded."
        case .contextCreationFailed: "llama.cpp could not create an inference context."
        case .decodeFailed(let status): "llama.cpp reported a decode failure (status \(status))."
        }
    }
}

/// The slice of llama.cpp the benchmark needs, ported from the harness's `LlamaContext`.
///
/// A measured repeat blocks for up to ~30 s and must not suspend mid-measurement, so the actor
/// runs on its own serial queue: the blocking stays off both the main actor and Swift's
/// cooperative thread pool.
actor LlamaEngine {
    /// Must cover the largest matrix v1 prefill (LISO, 2048). `llama_batch` is a set of
    /// fixed C arrays, so writing past this corrupts the heap.
    static let batchCapacity = 2048
    /// Headroom over LISO's 2048-token prefill and SILO's 128 + 1024.
    static let contextLength: UInt32 = 4096
    static let tickInterval = 16

    #if targetEnvironment(simulator)
    static let usesMetal = false
    #else
    static let usesMetal = true
    #endif

    // Provenance recorded in every capture. Must describe the linked llama.xcframework.
    static let pinnedCommit = "95ef7fc16054e63b427a3ef00188e055ef7586d8"
    static let backendVersion = "b1 (source build)"
    static var backendName: String { usesMetal ? "llama.cpp-metal" : "llama.cpp-cpu" }
    static var buildFlags: String {
        let offload = usesMetal ? "GGML_METAL=ON" : "GGML_METAL=ON; n_gpu_layers=0"
        return "build-xcframework.sh; \(offload); n_ctx=\(contextLength); batch=\(batchCapacity)"
    }

    private let handles: LlamaHandles
    private let queue = DispatchSerialQueue(label: "com.umer9538.pocketroofline.llama", qos: .userInitiated)

    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    let parametersInBillions: Double
    let tensorBytes: Int

    private var context: OpaquePointer { handles.context }

    private init(handles: LlamaHandles) {
        self.handles = handles
        self.parametersInBillions = Double(llama_model_n_params(handles.model)) / 1e9
        self.tensorBytes = Int(llama_model_size(handles.model))
    }

    /// Loads the weights and creates a context. Takes about a second, so it runs off the caller's actor.
    @concurrent
    static func load(modelAt url: URL) async throws -> LlamaEngine {
        _ = backendInitialized

        var modelParams = llama_model_default_params()
        if !usesMetal {
            // The simulator has no usable Metal backend for ggml.
            modelParams.n_gpu_layers = 0
        }
        guard let model = llama_model_load_from_file(url.path(percentEncoded: false), modelParams) else {
            throw LlamaEngineError.modelLoadFailed
        }

        let threads = Int32(max(1, min(8, ProcessInfo.processInfo.processorCount - 2)))
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = contextLength
        contextParams.n_threads = threads
        contextParams.n_threads_batch = threads

        guard let context = llama_init_from_model(model, contextParams) else {
            llama_model_free(model)
            throw LlamaEngineError.contextCreationFailed
        }
        return LlamaEngine(handles: LlamaHandles(model: model, context: context))
    }

    /// One measured repeat of a (prompt, generate) regime with synthetic tokens, so timings
    /// reflect pure compute, as llama-bench does. Prefill and decode are timed separately with
    /// exactly the same method as the harness's `prBenchOnce`, which produced the published runs.
    ///
    /// `progress` is called synchronously every `tickInterval` tokens. It stays inside the timed
    /// decode loop, as the cancellation check does, because both are negligible next to a
    /// ~25 ms token and timing around them would change the method.
    func benchOnce(
        prompt rawPromptTokens: Int,
        generate generateTokens: Int,
        progress: @Sendable (DecodeTick) -> Void
    ) throws -> BenchSample {
        let promptTokens = min(rawPromptTokens, Self.batchCapacity)
        let memory = llama_get_memory(context)

        // Prefill
        try Task.checkCancellation()
        clearBatch()
        for position in 0..<promptTokens {
            appendToBatch(token: 0, position: Int32(position), wantsLogits: false)
        }
        handles.batch.logits[Int(handles.batch.n_tokens) - 1] = 1
        llama_memory_clear(memory, false)

        let prefillStart = DispatchTime.now().uptimeNanoseconds
        try decodeBatch()
        let prefillEnd = DispatchTime.now().uptimeNanoseconds

        // Single-stream decode
        llama_memory_clear(memory, false)
        let decodeStart = DispatchTime.now().uptimeNanoseconds
        var windowStart = decodeStart
        for position in 0..<generateTokens {
            // Checked every token, not every window: once the app resigns active, iOS starts
            // refusing GPU work, so the loop must stop submitting as soon as possible.
            try Task.checkCancellation()
            clearBatch()
            appendToBatch(token: 0, position: Int32(position), wantsLogits: true)
            try decodeBatch()

            let tokensDone = position + 1
            if tokensDone.isMultiple(of: Self.tickInterval) {
                let now = DispatchTime.now().uptimeNanoseconds
                let windowSeconds = Double(now - windowStart) / 1e9
                progress(DecodeTick(
                    tokensDone: tokensDone,
                    windowTokensPerSecond: Double(Self.tickInterval) / windowSeconds
                ))
                windowStart = now
            }
        }
        let decodeEnd = DispatchTime.now().uptimeNanoseconds
        llama_memory_clear(memory, false)

        let prefillSeconds = Double(prefillEnd - prefillStart) / 1e9
        let decodeSeconds = Double(decodeEnd - decodeStart) / 1e9
        return BenchSample(
            prefillTokensPerSecond: Double(promptTokens) / prefillSeconds,
            decodeTokensPerSecond: Double(generateTokens) / decodeSeconds,
            ttftMs: prefillSeconds * 1000
        )
    }

    // MARK: - Batch helpers

    private func clearBatch() {
        handles.batch.n_tokens = 0
    }

    private func appendToBatch(token: llama_token, position: llama_pos, wantsLogits: Bool) {
        let index = Int(handles.batch.n_tokens)
        precondition(index < Self.batchCapacity, "llama_batch overflow")
        handles.batch.token[index] = token
        handles.batch.pos[index] = position
        handles.batch.n_seq_id[index] = 1
        handles.batch.seq_id[index]![0] = 0
        handles.batch.logits[index] = wantsLogits ? 1 : 0
        handles.batch.n_tokens += 1
    }

    /// Decodes and waits for the GPU, so the clock reads include the actual compute.
    private func decodeBatch() throws {
        let status = llama_decode(context, handles.batch)
        guard status == 0 else { throw LlamaEngineError.decodeFailed(status: status) }
        llama_synchronize(context)
    }

    /// `llama_backend_init` must run exactly once per process; a static `let` gives that for free.
    private static let backendInitialized: Void = llama_backend_init()
}

/// Owns the C-side llama.cpp objects and frees them together.
///
/// A class rather than actor state because an actor's deinit can't touch non-Sendable
/// stored properties; only `LlamaEngine` ever holds one, so access stays actor-isolated.
private final class LlamaHandles {
    let model: OpaquePointer
    let context: OpaquePointer
    var batch: llama_batch

    init(model: OpaquePointer, context: OpaquePointer) {
        self.model = model
        self.context = context
        self.batch = llama_batch_init(Int32(LlamaEngine.batchCapacity), 0, 1)
    }

    deinit {
        llama_batch_free(batch)
        llama_free(context)
        llama_model_free(model)
    }
}
