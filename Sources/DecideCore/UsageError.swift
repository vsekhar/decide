/// A command line the tool cannot run. The message names the problem and
/// carries no "Error: " prefix; the entry point adds it when printing.
public struct UsageError: Error, Equatable, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}
