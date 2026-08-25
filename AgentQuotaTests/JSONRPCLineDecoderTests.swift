import Foundation
import XCTest
@testable import AgentQuota

final class JSONRPCLineDecoderTests: XCTestCase {
    func testFramesMultipleLinesAndRetainsPartialLine() {
        var decoder = JSONRPCLineDecoder()

        XCTAssertEqual(
            decoder.append(Data("{\"id\":1}\n{\"id\":".utf8)),
            [.text("{\"id\":1}")]
        )
        XCTAssertEqual(
            decoder.append(Data("2}\r\n".utf8)),
            [.text("{\"id\":2}")]
        )
    }

    func testIncrementalUTF8Decoding() {
        var decoder = JSONRPCLineDecoder()
        let data = Data("{\"message\":\"Quota ⚡️\"}\n".utf8)
        let split = data.count - 5

        XCTAssertTrue(decoder.append(data.prefix(split)).isEmpty)
        XCTAssertEqual(
            decoder.append(data.suffix(from: split)),
            [.text("{\"message\":\"Quota ⚡️\"}")]
        )
    }

    func testMalformedUTF8IsReportedWithoutCrashing() {
        var decoder = JSONRPCLineDecoder()
        XCTAssertEqual(decoder.append(Data([0xFF, 0x0A])), [.invalidUTF8])
    }

    func testFinishReturnsAnUnterminatedFinalLine() {
        var decoder = JSONRPCLineDecoder()
        XCTAssertTrue(decoder.append(Data("{\"id\":1}".utf8)).isEmpty)
        XCTAssertEqual(decoder.finish(), [.text("{\"id\":1}")])
    }
}
