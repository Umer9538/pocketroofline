import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct Model: Identifiable {
    var id = UUID()
    var name: String
    var url: String
    var filename: String
    var status: String?
}

@MainActor
class LlamaState: ObservableObject {
    @Published var messageLog = ""
    @Published var cacheCleared = false
    @Published var downloadedModels: [Model] = []
    @Published var undownloadedModels: [Model] = []
    let NS_PER_S = 1_000_000_000.0

    private var llamaContext: LlamaContext?
    private var defaultModelUrl: URL? {
        Bundle.main.url(forResource: "ggml-model", withExtension: "gguf", subdirectory: "models")
        // Bundle.main.url(forResource: "llama-2-7b-chat", withExtension: "Q2_K.gguf", subdirectory: "models")
    }

    init() {
        loadModelsFromDisk()
        loadDefaultModels()
    }

    private func loadModelsFromDisk() {
        do {
            let documentsURL = getDocumentsDirectory()
            let modelURLs = try FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
            for modelURL in modelURLs {
                let modelName = modelURL.deletingPathExtension().lastPathComponent
                downloadedModels.append(Model(name: modelName, url: "", filename: modelURL.lastPathComponent, status: "downloaded"))
            }
        } catch {
            print("Error loading models from disk: \(error)")
        }
    }

    private func loadDefaultModels() {
        do {
            try loadModel(modelUrl: defaultModelUrl)
        } catch {
            messageLog += "Error!\n"
        }

        for model in defaultModels {
            let fileURL = getDocumentsDirectory().appendingPathComponent(model.filename)
            if FileManager.default.fileExists(atPath: fileURL.path) {

            } else {
                var undownloadedModel = model
                undownloadedModel.status = "download"
                undownloadedModels.append(undownloadedModel)
            }
        }
    }

    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    private let defaultModels: [Model] = [
        Model(name: "TinyLlama-1.1B (Q4_0, 0.6 GiB)",url: "https://huggingface.co/TheBloke/TinyLlama-1.1B-1T-OpenOrca-GGUF/resolve/main/tinyllama-1.1b-1t-openorca.Q4_0.gguf?download=true",filename: "tinyllama-1.1b-1t-openorca.Q4_0.gguf", status: "download"),
        Model(
            name: "TinyLlama-1.1B Chat (Q8_0, 1.1 GiB)",
            url: "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q8_0.gguf?download=true",
            filename: "tinyllama-1.1b-chat-v1.0.Q8_0.gguf", status: "download"
        ),

        Model(
            name: "TinyLlama-1.1B (F16, 2.2 GiB)",
            url: "https://huggingface.co/ggml-org/models/resolve/main/tinyllama-1.1b/ggml-model-f16.gguf?download=true",
            filename: "tinyllama-1.1b-f16.gguf", status: "download"
        ),

        Model(
            name: "Phi-2.7B (Q4_0, 1.6 GiB)",
            url: "https://huggingface.co/ggml-org/models/resolve/main/phi-2/ggml-model-q4_0.gguf?download=true",
            filename: "phi-2-q4_0.gguf", status: "download"
        ),

        Model(
            name: "Phi-2.7B (Q8_0, 2.8 GiB)",
            url: "https://huggingface.co/ggml-org/models/resolve/main/phi-2/ggml-model-q8_0.gguf?download=true",
            filename: "phi-2-q8_0.gguf", status: "download"
        ),

        Model(
            name: "Mistral-7B-v0.1 (Q4_0, 3.8 GiB)",
            url: "https://huggingface.co/TheBloke/Mistral-7B-v0.1-GGUF/resolve/main/mistral-7b-v0.1.Q4_0.gguf?download=true",
            filename: "mistral-7b-v0.1.Q4_0.gguf", status: "download"
        ),
        Model(
            name: "OpenHermes-2.5-Mistral-7B (Q3_K_M, 3.52 GiB)",
            url: "https://huggingface.co/TheBloke/OpenHermes-2.5-Mistral-7B-GGUF/resolve/main/openhermes-2.5-mistral-7b.Q3_K_M.gguf?download=true",
            filename: "openhermes-2.5-mistral-7b.Q3_K_M.gguf", status: "download"
        )
    ]
    func loadModel(modelUrl: URL?) throws {
        if let modelUrl {
            messageLog += "Loading model...\n"
            llamaContext = try LlamaContext.create_context(path: modelUrl.path())
            messageLog += "Loaded model \(modelUrl.lastPathComponent)\n"

            // Assuming that the model is successfully loaded, update the downloaded models
            updateDownloadedModels(modelName: modelUrl.lastPathComponent, status: "downloaded")
        } else {
            messageLog += "Load a model from the list below\n"
        }
    }


    private func updateDownloadedModels(modelName: String, status: String) {
        undownloadedModels.removeAll { $0.name == modelName }
    }


    func complete(text: String) async {
        guard let llamaContext else {
            return
        }

        let t_start = DispatchTime.now().uptimeNanoseconds
        await llamaContext.completion_init(text: text)
        let t_heat_end = DispatchTime.now().uptimeNanoseconds
        let t_heat = Double(t_heat_end - t_start) / NS_PER_S

        messageLog += "\(text)"

        Task.detached {
            while await !llamaContext.is_done {
                let result = await llamaContext.completion_loop()
                await MainActor.run {
                    self.messageLog += "\(result)"
                }
            }

            let t_end = DispatchTime.now().uptimeNanoseconds
            let t_generation = Double(t_end - t_heat_end) / self.NS_PER_S
            let tokens_per_second = Double(await llamaContext.n_len) / t_generation

            await llamaContext.clear()

            await MainActor.run {
                self.messageLog += """
                    \n
                    Done
                    Heat up took \(t_heat)s
                    Generated \(tokens_per_second) t/s\n
                    """
            }
        }
    }

    func bench() async {
        guard let llamaContext else {
            return
        }

        messageLog += "\n"
        messageLog += "Running benchmark...\n"
        messageLog += "Model info: "
        messageLog += await llamaContext.model_info() + "\n"

        let t_start = DispatchTime.now().uptimeNanoseconds
        let _ = await llamaContext.bench(pp: 8, tg: 4, pl: 1) // heat up
        let t_end = DispatchTime.now().uptimeNanoseconds

        let t_heat = Double(t_end - t_start) / NS_PER_S
        messageLog += "Heat up time: \(t_heat) seconds, please wait...\n"

        // if more than 5 seconds, then we're probably running on a slow device
        if t_heat > 5.0 {
            messageLog += "Heat up time is too long, aborting benchmark\n"
            return
        }

        let result = await llamaContext.bench(pp: 512, tg: 128, pl: 1, nr: 3)

        messageLog += "\(result)"
        messageLog += "\n"
    }

    func clear() async {
        guard let llamaContext else {
            return
        }

        await llamaContext.clear()
        messageLog = ""
    }

    // MARK: - PocketRoofline

    private func thermalString() -> String {
        #if canImport(UIKit)
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "nominal"
        }
        #else
        return "nominal"
        #endif
    }

    private func residentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.resident_size) / 1024.0 / 1024.0 : 0
    }

    /// Runs the PocketRoofline matrix v1 regimes and writes a JSON capture to
    /// the app's Documents directory (retrievable via Files app or Xcode's
    /// "Download Container"), and copies it to the clipboard. Uses fixed
    /// synthetic-token regimes for pure-compute timing, N repeats each.
    func pocketRoofline(modelId: String, quant: String) async {
        guard let llamaContext else {
            messageLog += "\nPocketRoofline: load a model first.\n"
            return
        }

        // Matrix v1 regimes (short/long in, short/long out) and repeat count.
        let regimes: [(label: String, pp: Int, tg: Int)] = [
            ("SISO", 128, 128),
            ("LISO", 2048, 128),
            ("SILO", 128, 1024),
        ]
        let repeats = 5

        messageLog += "\n=== PocketRoofline run ===\n"
        let params = await llamaContext.prModelParams()
        let sizeBytes = await llamaContext.prModelSizeBytes()
        messageLog += "model \(modelId) \(quant) · \(String(format: "%.3f", params))B · \(sizeBytes) bytes\n"

        // Warm up (unrecorded), per methodology.
        _ = await llamaContext.prBenchOnce(promptTokens: 32, generateTokens: 16)

        var regimeBlocks: [String] = []
        let iso = ISO8601DateFormatter()

        for regime in regimes {
            var repeatObjs: [String] = []
            messageLog += "\n[\(regime.label)] pp=\(regime.pp) tg=\(regime.tg)\n"
            for idx in 0..<repeats {
                let thermalStart = thermalString()
                let r = await llamaContext.prBenchOnce(promptTokens: regime.pp, generateTokens: regime.tg)
                let thermalEnd = thermalString()
                let mem = residentMemoryMB()
                messageLog += "  #\(idx): prefill \(String(format: "%.1f", r.prefill)) t/s · decode \(String(format: "%.2f", r.decode)) t/s · \(thermalStart)->\(thermalEnd)\n"
                repeatObjs.append("""
                        {"index": \(idx), "prefillTokensPerSec": \(r.prefill), "decodeTokensPerSec": \(r.decode), "ttftMs": \(r.ttftMs), "peakResidentMB": \(mem), "thermalStateStart": "\(thermalStart)", "thermalStateEnd": "\(thermalEnd)"}
                """)
                // Cooldown between repeats (short in-app; the full 10-min ambient
                // cooldown from METHODOLOGY §5 is enforced between full sessions).
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
            regimeBlocks.append("""
                {"label": "\(regime.label)", "promptTokens": \(regime.pp), "generateTokens": \(regime.tg), "repeats": [
            \(repeatObjs.joined(separator: ",\n"))
                ]}
            """)
        }

        #if canImport(UIKit)
        let deviceModel = UIDevice.current.model
        let osName = UIDevice.current.systemName
        let osVersion = UIDevice.current.systemVersion
        #else
        let deviceModel = "unknown"; let osName = "unknown"; let osVersion = "unknown"
        #endif
        var sysinfo = utsname(); uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(validatingUTF8: $0) ?? "?" }
        }

        let json = """
        {
          "schemaVersion": 1,
          "capturedAt": "\(iso.string(from: Date()))",
          "matrixVersion": "v1",
          "device": {"model": "\(deviceModel)", "identifier": "\(machine)", "soc": "FILL-IN", "ramGB": 0},
          "os": {"name": "\(osName)", "version": "\(osVersion)", "build": "FILL-IN-sw_vers"},
          "backend": {"name": "llama.cpp-metal", "version": "FILL-IN", "commit": "FILL-IN"},
          "model": {"id": "\(modelId)", "params": \(params), "quant": "\(quant)", "fileSha256": "FILL-IN"},
          "conditions": {"charging": false, "airplaneMode": true},
          "regimes": [
        \(regimeBlocks.joined(separator: ",\n"))
          ]
        }
        """

        let outURL = getDocumentsDirectory().appendingPathComponent("pocketroofline-\(Int(Date().timeIntervalSince1970)).json")
        do {
            try json.write(to: outURL, atomically: true, encoding: .utf8)
            messageLog += "\nWrote \(outURL.lastPathComponent) to app Documents.\n"
        } catch {
            messageLog += "\nWrite failed: \(error)\n"
        }
        #if canImport(UIKit)
        UIPasteboard.general.string = json
        messageLog += "Copied full JSON to clipboard.\n"
        #endif
        messageLog += "=== PocketRoofline done ===\n"
    }
}
