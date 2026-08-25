@preconcurrency import Foundation
import Darwin

enum AppServerEvent: Equatable, Sendable {
    case notification(method: String, params: JSONValue?)
    case malformedResponse(String)
    case unknownMessage(String)
    case processExited(status: Int32)
}

enum AppServerTransportError: LocalizedError, Sendable {
    case notRunning
    case launchFailed(String)
    case writeFailed(String)
    case timedOut(method: String)
    case rpc(code: Int, message: String, data: JSONValue?)
    case malformedResponse
    case processExited(status: Int32)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notRunning:
            return "The Codex app-server is not running."
        case let .launchFailed(message):
            return "Codex could not be started: \(message)"
        case let .writeFailed(message):
            return "AgentQuota could not send a request to Codex: \(message)"
        case let .timedOut(method):
            return "Codex did not respond to \(method) within 10 seconds."
        case let .rpc(_, message, _):
            return message
        case .malformedResponse:
            return "Codex returned a malformed response. AgentQuota will reconnect."
        case let .processExited(status):
            return "The Codex app-server exited unexpectedly (status \(status))."
        case .cancelled:
            return "The Codex request was cancelled."
        }
    }
}

protocol AppServerTransporting: AnyObject, Sendable {
    var events: AsyncStream<AppServerEvent> { get }
    func start() throws
    func request(method: String, params: JSONValue) async throws -> JSONValue
    func notify(method: String, params: JSONValue?) throws
    func stop()
}

final class AppServerTransport: AppServerTransporting, @unchecked Sendable {
    let events: AsyncStream<AppServerEvent>

    private struct PendingRequest {
        let continuation: CheckedContinuation<JSONValue, Error>
        let timeout: DispatchWorkItem
    }

    private let executableURL: URL
    private let timeout: Duration
    private let queue = DispatchQueue(label: "com.tsilva.AgentQuota.app-server-transport")
    private let queueKey = DispatchSpecificKey<Void>()
    private let eventContinuation: AsyncStream<AppServerEvent>.Continuation
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var process: Process?
    private var standardInput: FileHandle?
    private var standardOutput: FileHandle?
    private var standardError: FileHandle?
    private var lineDecoder = JSONRPCLineDecoder()
    private var pendingRequests: [Int64: PendingRequest] = [:]
    private var nextRequestID: Int64 = 1
    private var isStopping = false

    init(executableURL: URL, timeout: Duration = .seconds(10)) {
        self.executableURL = executableURL
        self.timeout = timeout
        let pair = AsyncStream<AppServerEvent>.makeStream(bufferingPolicy: .bufferingNewest(100))
        events = pair.stream
        eventContinuation = pair.continuation
        queue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        stop()
        eventContinuation.finish()
    }

    func start() throws {
        try onQueue {
            guard process?.isRunning != true else {
                return
            }

            isStopping = false
            lineDecoder = JSONRPCLineDecoder()

            let child = Process()
            let inputPipe = Pipe()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            child.executableURL = executableURL
            child.arguments = ["app-server", "--stdio"]
            child.standardInput = inputPipe
            child.standardOutput = outputPipe
            child.standardError = errorPipe

            outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                self?.queue.async { [weak self] in
                    self?.consumeStandardOutput(data)
                }
            }
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                _ = handle.availableData
            }
            child.terminationHandler = { [weak self] terminatedProcess in
                self?.queue.async { [weak self] in
                    self?.handleTermination(of: terminatedProcess)
                }
            }

            do {
                try child.run()
                process = child
                standardInput = inputPipe.fileHandleForWriting
                standardOutput = outputPipe.fileHandleForReading
                standardError = errorPipe.fileHandleForReading
            } catch {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                throw AppServerTransportError.launchFailed(error.localizedDescription)
            }
        }
    }

    func request(method: String, params: JSONValue) async throws -> JSONValue {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: AppServerTransportError.cancelled)
                    return
                }
                guard process?.isRunning == true else {
                    continuation.resume(throwing: AppServerTransportError.notRunning)
                    return
                }

                let requestID = nextRequestID
                nextRequestID += 1

                let timeoutWork = DispatchWorkItem { [weak self] in
                    guard let self,
                          let pending = pendingRequests.removeValue(forKey: requestID) else {
                        return
                    }
                    pending.continuation.resume(
                        throwing: AppServerTransportError.timedOut(method: method)
                    )
                }
                pendingRequests[requestID] = PendingRequest(
                    continuation: continuation,
                    timeout: timeoutWork
                )

                do {
                    try write(
                        .object([
                            "id": .integer(requestID),
                            "method": .string(method),
                            "params": params
                        ])
                    )
                    queue.asyncAfter(
                        deadline: .now() + timeout.timeInterval,
                        execute: timeoutWork
                    )
                } catch {
                    timeoutWork.cancel()
                    pendingRequests.removeValue(forKey: requestID)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func notify(method: String, params: JSONValue?) throws {
        try onQueue {
            guard process?.isRunning == true else {
                throw AppServerTransportError.notRunning
            }

            var message: [String: JSONValue] = ["method": .string(method)]
            if let params {
                message["params"] = params
            }
            try write(.object(message))
        }
    }

    func stop() {
        var processIdentifier: Int32?

        onQueue {
            isStopping = true
            processIdentifier = process?.processIdentifier
            process = nil

            standardOutput?.readabilityHandler = nil
            standardError?.readabilityHandler = nil
            try? standardInput?.close()
            try? standardOutput?.close()
            try? standardError?.close()
            standardInput = nil
            standardOutput = nil
            standardError = nil
            failAllPending(with: AppServerTransportError.cancelled)
        }

        guard let processIdentifier, processIdentifier > 0 else {
            return
        }

        Darwin.kill(processIdentifier, SIGTERM)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            if Darwin.kill(processIdentifier, 0) == 0 {
                Darwin.kill(processIdentifier, SIGKILL)
            }
        }
    }

    private func write(_ value: JSONValue) throws {
        guard let standardInput else {
            throw AppServerTransportError.notRunning
        }

        do {
            var data = try encoder.encode(value)
            data.append(0x0A)
            try standardInput.write(contentsOf: data)
        } catch let error as AppServerTransportError {
            throw error
        } catch {
            throw AppServerTransportError.writeFailed(error.localizedDescription)
        }
    }

    private func consumeStandardOutput(_ data: Data) {
        let lines = data.isEmpty ? lineDecoder.finish() : lineDecoder.append(data)
        for line in lines {
            switch line {
            case let .text(text):
                handleLine(text)
            case .invalidUTF8:
                handleMalformedResponse("Codex emitted non-UTF-8 output.")
            }
        }
    }

    private func handleLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let message = try? decoder.decode(WireMessage.self, from: data) else {
            handleMalformedResponse("Codex emitted malformed JSON.")
            return
        }

        if let requestID = message.id?.integerValue {
            guard let pending = pendingRequests.removeValue(forKey: requestID) else {
                eventContinuation.yield(.unknownMessage("Response for unknown request \(requestID)."))
                return
            }

            pending.timeout.cancel()
            if let error = message.error {
                pending.continuation.resume(
                    throwing: AppServerTransportError.rpc(
                        code: error.code,
                        message: error.message,
                        data: error.data
                    )
                )
            } else {
                pending.continuation.resume(returning: message.result ?? .null)
            }
            return
        }

        if let method = message.method {
            eventContinuation.yield(.notification(method: method, params: message.params))
            return
        }

        eventContinuation.yield(.unknownMessage("Codex emitted an unrecognized message."))
    }

    private func handleMalformedResponse(_ message: String) {
        failAllPending(with: AppServerTransportError.malformedResponse)
        eventContinuation.yield(.malformedResponse(message))
    }

    private func handleTermination(of terminatedProcess: Process) {
        guard process === terminatedProcess else {
            return
        }

        process = nil
        standardOutput?.readabilityHandler = nil
        standardError?.readabilityHandler = nil
        standardInput = nil
        standardOutput = nil
        standardError = nil
        failAllPending(with: AppServerTransportError.processExited(status: terminatedProcess.terminationStatus))

        if !isStopping {
            eventContinuation.yield(.processExited(status: terminatedProcess.terminationStatus))
        }
    }

    private func failAllPending(with error: Error) {
        let requests = pendingRequests.values
        pendingRequests.removeAll()
        for request in requests {
            request.timeout.cancel()
            request.continuation.resume(throwing: error)
        }
    }

    private func onQueue<T>(_ body: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return try body()
        }
        return try queue.sync(execute: body)
    }
}

private struct WireMessage: Decodable {
    let id: WireRequestID?
    let method: String?
    let params: JSONValue?
    let result: JSONValue?
    let error: WireError?
}

private enum WireRequestID: Decodable {
    case integer(Int64)
    case string(String)

    var integerValue: Int64? {
        switch self {
        case let .integer(value):
            return value
        case let .string(value):
            return Int64(value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Request IDs must be strings or integers."
            )
        }
    }
}

private struct WireError: Decodable {
    let code: Int
    let message: String
    let data: JSONValue?
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
