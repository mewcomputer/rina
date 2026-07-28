import Foundation

struct ServerSentEvent: Equatable, Sendable {
    let data: String
}

struct ServerSentEventParser: Sendable {
    private var lineBuffer = Data()
    private var dataLines: [String] = []

    mutating func append(_ bytes: [UInt8]) -> [ServerSentEvent] {
        lineBuffer.append(contentsOf: bytes)

        var events: [ServerSentEvent] = []
        while let newlineIndex = lineBuffer.firstIndex(of: 0x0A) {
            let lineData = lineBuffer.prefix(upTo: newlineIndex)
            lineBuffer.removeSubrange(...newlineIndex)
            events.append(contentsOf: consume(line: String(decoding: lineData, as: UTF8.self)))
        }
        return events
    }

    mutating func finish() -> [ServerSentEvent] {
        var events: [ServerSentEvent] = []
        if !lineBuffer.isEmpty {
            events.append(contentsOf: consume(line: String(decoding: lineBuffer, as: UTF8.self)))
            lineBuffer.removeAll(keepingCapacity: false)
        }
        if !dataLines.isEmpty {
            events.append(ServerSentEvent(data: dataLines.joined(separator: "\n")))
            dataLines.removeAll(keepingCapacity: false)
        }
        return events
    }

    private mutating func consume(line rawLine: String) -> [ServerSentEvent] {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        guard !line.isEmpty else {
            guard !dataLines.isEmpty else { return [] }
            let event = ServerSentEvent(data: dataLines.joined(separator: "\n"))
            dataLines.removeAll(keepingCapacity: true)
            return [event]
        }

        guard !line.hasPrefix(":") else { return [] }
        guard line.hasPrefix("data:") else { return [] }

        var value = String(line.dropFirst(5))
        if value.first == " " {
            value.removeFirst()
        }
        dataLines.append(value)
        return []
    }
}
