import XCTest
import iOSViewerKit
import UltraViewerProtocol

final class ViewerKitTests: XCTestCase {
    func testMouseMoveUsesWindowsMessageAndThreeParameters() {
        let message = MouseMessage.move(wParam: 0, x: 12, y: 34)
        XCTAssertEqual(message.text(), "8|||512|||0|||12|||34")
    }

    func testPackedPositionKeepsTwoSignedWords() {
        let packed = MouseMessage.packedPosition(x: -1, y: 2)
        XCTAssertEqual(packed, Int32(bitPattern: 0x0002FFFF))
    }

    func testVerticalWheelKeepsSignedDeltaInHighWord() {
        XCTAssertEqual(MouseMessage.wheelWParam(delta: 120, keyFlags: 0), 120 << 16)
        XCTAssertEqual(MouseMessage.wheelWParam(delta: -120, keyFlags: 0), Int32(bitPattern: 0xFF880000))
        let message = MouseMessage.verticalWheel(
            wParam: MouseMessage.wheelWParam(delta: 120, keyFlags: 0),
            lParam: MouseMessage.packedPosition(x: 10, y: 20))
        XCTAssertEqual(message.windowsMessage, 0x20a)
        XCTAssertEqual(message.text().split(separator: "|||").count, 5)
    }

    func testOperatingSystemWireValue() {
        let version = OperatingSystemVersion(majorVersion: 16, minorVersion: 6, patchVersion: 0)
        XCTAssertEqual(IOSRegistrationProfile.operatingSystemWireValue(version), "0|16|0|6|0|0")
    }

    func testDefaultDictionaryURLIsInsideDocuments() {
        XCTAssertEqual(UltraViewerScreenDictionary.defaultFileURL()?.lastPathComponent, "8bit.dat")
    }

    func testNoEmbeddedDictionaryResourceInSwiftPackage() {
        let package = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Package.swift")
        let source = try String(contentsOf: package, encoding: .utf8)
        XCTAssertFalse(source.contains("8bit.dat"))
        XCTAssertTrue(source.contains(".iOS(.v16)"))
    }
}
