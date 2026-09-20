import DecideCore
import Foundation

/// The `decide` executable. All logic lives in `DecideCore`, so tests can
/// reach it with `@testable import`.
@main
struct DecideCommand {
    static func main() async {
        var stdout = StandardOutput()
        var stderr = StandardError()
        let code = await Decide.run(
            arguments: Array(CommandLine.arguments.dropFirst()),
            environment: ProcessInfo.processInfo.environment,
            stdout: &stdout,
            stderr: &stderr
        )
        exit(code)
    }
}
