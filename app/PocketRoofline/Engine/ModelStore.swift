import CryptoKit
import Foundation
import Observation
import os

/// The one model matrix v1 runs, pinned by content hash so every device benchmarks identical weights.
struct BenchmarkModel: Sendable {
    let id: String
    let displayName: String
    let quant: String
    let fileName: String
    let downloadURL: URL
    let sha256: String
    let sizeBytes: Int64

    static let tinyLlama = BenchmarkModel(
        id: "TinyLlama-1.1B-1T-OpenOrca",
        displayName: "TinyLlama 1.1B",
        quant: "Q4_0",
        fileName: "tinyllama-1.1b-1t-openorca.Q4_0.gguf",
        downloadURL: URL(string: "https://huggingface.co/TheBloke/TinyLlama-1.1B-1T-OpenOrca-GGUF/resolve/main/tinyllama-1.1b-1t-openorca.Q4_0.gguf?download=true")!,
        sha256: "bd07d1c53b833d422272259b17b393270b8f81c937d14332dfa044fe1b349884",
        sizeBytes: 636_725_728
    )
}

/// Downloads the benchmark model, verifies its SHA-256, and refuses to hand out a file that fails.
@MainActor
@Observable
final class ModelStore {
    enum State: Equatable {
        case checking
        case absent
        case downloading(received: Int64, expected: Int64)
        case verifying
        case ready(fileURL: URL, sha256: String)
        case failed(message: String)
    }

    let model: BenchmarkModel
    private(set) var state: State = .checking

    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    /// Lets a retry pick up where a dropped connection left off instead of restarting 600 MB.
    @ObservationIgnored private var resumeData: Data?

    init(model: BenchmarkModel = .tinyLlama) {
        self.model = model
    }

    var verifiedFile: (url: URL, sha256: String)? {
        if case .ready(let url, let sha) = state { (url, sha) } else { nil }
    }

    private var fileURL: URL {
        get throws {
            let directory = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appending(path: "Models", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appending(path: model.fileName)
        }
    }

    /// Re-hashes any file already on disk: a model that was swapped or corrupted after its
    /// first check must not produce numbers attributed to the pinned weights.
    func refresh() async {
        guard downloadTask == nil else { return }
        do {
            let url = try fileURL
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                await verify(url)
            } else {
                state = .absent
            }
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    func download() {
        guard downloadTask == nil else { return }
        state = .downloading(received: 0, expected: model.sizeBytes)
        downloadTask = Task {
            defer { downloadTask = nil }
            do {
                let destination = try fileURL
                let temporary = try await fetch()
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: temporary, to: destination)
                await verify(destination)
            } catch is CancellationError {
                state = .absent
            } catch {
                state = .failed(message: Self.describe(error))
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    private func fetch() async throws -> URL {
        let delegate = DownloadProgressObserver { [weak self] received, expected in
            Task { @MainActor in
                guard let self, case .downloading = self.state else { return }
                self.state = .downloading(received: received, expected: expected > 0 ? expected : self.model.sizeBytes)
            }
        }
        do {
            let (url, response): (URL, URLResponse)
            if let resumeData {
                self.resumeData = nil
                (url, response) = try await URLSession.shared.download(resumeFrom: resumeData, delegate: delegate)
            } else {
                (url, response) = try await URLSession.shared.download(from: model.downloadURL, delegate: delegate)
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                try? FileManager.default.removeItem(at: url)
                throw ModelStoreError.httpStatus(http.statusCode)
            }
            return url
        } catch let error as URLError {
            resumeData = error.downloadTaskResumeData
            if error.code == .cancelled { throw CancellationError() }
            throw error
        }
    }

    private func verify(_ url: URL) async {
        state = .verifying
        do {
            let digest = try await Self.sha256(of: url)
            guard digest == model.sha256 else {
                // Never keep a mismatched file around: the next launch would just reject it again.
                try? FileManager.default.removeItem(at: url)
                state = .failed(message: "The downloaded file didn't match the pinned SHA-256, so it was deleted. Try downloading again.")
                return
            }
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = url
            try mutableURL.setResourceValues(values)
            state = .ready(fileURL: url, sha256: digest)
        } catch {
            state = .failed(message: Self.describe(error))
        }
    }

    /// Streams the file through SHA-256 in 4 MB chunks, keeping memory flat for a 600 MB file.
    @concurrent
    private static func sha256(of url: URL) async throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func describe(_ error: any Error) -> String {
        if let urlError = error as? URLError, urlError.code == .notConnectedToInternet {
            return "No internet connection. The model download needs a network; you can switch to airplane mode afterwards."
        }
        return error.localizedDescription
    }
}

enum ModelStoreError: LocalizedError {
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code): "The model server responded with HTTP \(code)."
        }
    }
}

/// Reports byte counts for URLSession's async download API.
///
/// That API doesn't forward `didWriteData` to a task delegate, but it does report the task it
/// creates, whose `Progress` can be observed instead. Progress changes on every network read,
/// so reports are throttled here, before they reach the main actor, to one per megabyte.
private final class DownloadProgressObserver: NSObject, URLSessionTaskDelegate, Sendable {
    private static let reportingStep: Int64 = 1 << 20

    private let onProgress: @Sendable (Int64, Int64) -> Void
    private let observation = OSAllocatedUnfairLock<NSKeyValueObservation?>(uncheckedState: nil)
    private let lastReported = OSAllocatedUnfairLock<Int64>(initialState: 0)

    init(onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        // Both weak: the task retains this delegate, which owns the observation.
        let token = task.progress.observe(\.fractionCompleted) { [weak self, weak task] _, _ in
            guard let self, let task else { return }
            report(received: task.countOfBytesReceived, expected: task.countOfBytesExpectedToReceive)
        }
        observation.withLockUnchecked { $0 = token }
    }

    private func report(received: Int64, expected: Int64) {
        let isDue = lastReported.withLock { last in
            guard received - last >= Self.reportingStep || received == expected else { return false }
            last = received
            return true
        }
        if isDue { onProgress(received, expected) }
    }
}
