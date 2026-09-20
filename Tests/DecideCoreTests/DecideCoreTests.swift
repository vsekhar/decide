import Testing

@testable import DecideCore

@Suite("DecideCore")
struct DecideCoreTests {
    @Test("The stub exits 0")
    func stubExitsZero() async {
        let code = await Decide.run()
        #expect(code == 0)
    }
}
