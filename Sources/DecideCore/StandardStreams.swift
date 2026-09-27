import Foundation

/// The process's standard output, for `print(_:to:)`.
public struct StandardOutput: TextOutputStream {
    public init() {}
    public mutating func write(_ string: String) {
        FileHandle.standardOutput.write(Data(string.utf8))
    }
}

/// The process's standard error, for `print(_:to:)`.
public struct StandardError: TextOutputStream {
    public init() {}
    public mutating func write(_ string: String) {
        FileHandle.standardError.write(Data(string.utf8))
    }
}

/// Standard input as the run reads it: whole, or one line at a time. A run
/// does one or the other, never both.
public protocol StandardInputReading {
    /// Every byte up to end of file, as text. A descriptor that does not
    /// read is `.unreadable`, and bytes that are not UTF-8 are `.notUTF8`.
    func readToEnd() throws(ConfigReadError) -> String
    /// The next line without its line ending, or nil at end of file. A line
    /// ends at a line feed, and a carriage return before it is dropped. A
    /// last line with no line feed is still a line. A descriptor that does
    /// not read is `.unreadable`. A line that is not UTF-8 is `.notUTF8`,
    /// and the reader has moved past it, so the next call gives the next
    /// line.
    func readLine() throws(ConfigReadError) -> String?
}

/// The process's standard input, read whole or one line at a time.
public final class StandardInput: StandardInputReading {
    /// Bytes read from the descriptor. Those before `start` belong to lines
    /// already given.
    private var buffer: [UInt8] = []
    /// The index in `buffer` of the first byte no line has taken yet.
    private var start = 0
    /// The index in `buffer` up to which no line feed was found since
    /// `start`; the next search begins there.
    private var scanned = 0
    /// Whether the descriptor has reached end of file.
    private var atEnd = false
    /// The bytes one `read(2)` gives, reused for every read.
    private var chunk = [UInt8](repeating: 0, count: 65536)

    public init() {}

    /// Every byte up to end of file, as text. A descriptor that does not
    /// read is `.unreadable`, and bytes that are not UTF-8 are `.notUTF8`,
    /// decoded here so both platforms give the same words. Waits for end
    /// of file, so a terminal needs Ctrl-D, as `cat -` does.
    public func readToEnd() throws(ConfigReadError) -> String {
        let data: Data?
        do {
            data = try FileHandle.standardInput.readToEnd()
        } catch {
            throw .unreadable
        }
        guard let data else { return "" }
        guard let text = String(data: data, encoding: .utf8) else { throw .notUTF8 }
        return text
    }

    /// The next line, as the protocol describes. Reads with `read(2)`, which
    /// gives what the pipe holds as soon as any byte is ready, so a line is
    /// decided when its line feed arrives, not at end of file.
    /// `FileHandle.read(upToCount:)` would wait for the count or end of file.
    public func readLine() throws(ConfigReadError) -> String? {
        while true {
            if let feed = buffer[max(start, scanned)...].firstIndex(of: 0x0A) {
                let bytes = buffer[start..<feed]
                start = feed + 1
                return try Self.decode(bytes)
            }
            if atEnd {
                guard start < buffer.count else { return nil }
                let bytes = buffer[start...]
                buffer = []
                start = 0
                scanned = 0
                return try Self.decode(bytes)
            }
            scanned = buffer.count
            let count = chunk.withUnsafeMutableBytes { raw in
                var count: Int
                repeat {
                    count = read(STDIN_FILENO, raw.baseAddress, raw.count)
                } while count == -1 && errno == EINTR
                return count
            }
            if count < 0 { throw .unreadable }
            if count == 0 {
                atEnd = true
            } else {
                // Each byte moves at most once.
                buffer.removeFirst(start)
                scanned -= start
                start = 0
                buffer.append(contentsOf: chunk[..<count])
            }
        }
    }

    /// One line's bytes as text, with one trailing carriage return dropped.
    /// Bytes that are not UTF-8 are `.notUTF8`.
    private static func decode(_ bytes: ArraySlice<UInt8>) throws(ConfigReadError) -> String {
        var bytes = bytes
        if bytes.last == 0x0D { bytes.removeLast() }
        guard let text = String(validating: bytes, as: UTF8.self) else { throw .notUTF8 }
        return text
    }
}
