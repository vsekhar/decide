import DecideCore
import Foundation

/// The `decide` executable. All logic lives in `DecideCore`, so tests can
/// reach it with `@testable import`.
@main
struct DecideCommand {
    static func main() async {
        let code = await Decide.run()
        exit(code)
    }
}
