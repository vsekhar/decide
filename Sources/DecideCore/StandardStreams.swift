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

/// The process's standard input, read whole.
public struct StandardInput {
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
}
