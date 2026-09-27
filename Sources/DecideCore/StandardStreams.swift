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

/// Standard input as the run reads it: whole, one line at a time, or one
/// secret line. A run does one of these, never two.
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
    /// Whether standard input is a terminal, so a key can be asked for with
    /// a prompt and echo off.
    var isTerminal: Bool { get }
    /// One line with the terminal's echo off when standard input is a
    /// terminal, else one line as `readLine` gives it. nil at end of file.
    func readSecretLine() throws(ConfigReadError) -> String?
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

    public var isTerminal: Bool { isatty(STDIN_FILENO) == 1 }

    /// One line, as the protocol describes. At a terminal it clears `ECHO`
    /// for the read and restores the attributes it found, even when the
    /// read throws or a signal ends the process at the prompt. Canonical
    /// mode stays on, so Enter still ends the line. A terminal whose
    /// attributes do not read or set is `.unreadable`.
    public func readSecretLine() throws(ConfigReadError) -> String? {
        guard isTerminal else { return try readLine() }
        var saved = termios()
        guard tcgetattr(STDIN_FILENO, &saved) == 0 else { throw .unreadable }
        // The handlers go in before echo goes off, so no signal finds the
        // terminal changed with nothing to put it back.
        Self.attributesToRestore = saved
        let previous = Self.fatalSignals.map { ($0, signal($0, Self.restoreOnSignal)) }
        defer {
            _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &saved)
            for (number, handler) in previous { _ = signal(number, handler) }
            Self.attributesToRestore = nil
        }
        var quiet = saved
        // `ECHO` is an Int32 and `c_lflag` a `tcflag_t` on both platforms.
        quiet.c_lflag &= ~tcflag_t(ECHO)
        guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &quiet) == 0 else { throw .unreadable }
        return try readLine()
    }

    /// The signals that end the process at the prompt: Ctrl-C, a kill, and
    /// a closed terminal. Each runs `restoreOnSignal` during a secret read.
    private static let fatalSignals = [SIGINT, SIGTERM, SIGHUP]

    /// The attributes `restoreOnSignal` puts back, set for the length of a
    /// secret read and nil otherwise. Only the reading thread writes it,
    /// before the handlers go in and after they come out, and the handler
    /// only reads it, so no lock is needed.
    nonisolated(unsafe) private static var attributesToRestore: termios?

    /// Puts the terminal back, then lets the signal end the process as it
    /// would have: the default action is restored and the signal raised
    /// again. `TCSANOW`, because nothing here waits for output. Every call
    /// is async-signal-safe.
    private static let restoreOnSignal: @convention(c) (Int32) -> Void = { number in
        if var attributes = StandardInput.attributesToRestore {
            _ = tcsetattr(STDIN_FILENO, TCSANOW, &attributes)
        }
        _ = signal(number, SIG_DFL)
        _ = raise(number)
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
