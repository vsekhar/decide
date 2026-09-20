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
