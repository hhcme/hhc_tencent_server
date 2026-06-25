import XCTest
@testable import HHCServerManager

final class OpenSSHClientTests: XCTestCase {
    func testRsyncProgressUpdateParsesByteCountAndPercent() {
        let progress = OpenSSHClient.rsyncProgressUpdate(fromLine: "      1,024  50%  100.00kB/s    0:00:01")

        XCTAssertEqual(progress?.completedBytes, 1_024)
        XCTAssertEqual(progress?.totalBytes, 2_048)
        XCTAssertEqual(progress?.fraction, 0.5)
    }

    func testRsyncProgressUpdatesParseCarriageReturnDelimitedOutput() {
        let output = "\r          512  25%   50.00kB/s    0:00:03\r        2,048 100%  100.00kB/s    0:00:00\n"

        let progress = OpenSSHClient.rsyncProgressUpdates(from: output)

        XCTAssertEqual(progress.map(\.completedBytes), [512, 2_048])
        XCTAssertEqual(progress.map(\.fraction), [0.25, 1])
    }

    func testRsyncProgressUpdateIgnoresNonProgressLines() {
        XCTAssertNil(OpenSSHClient.rsyncProgressUpdate(fromLine: "sending incremental file list"))
        XCTAssertNil(OpenSSHClient.rsyncProgressUpdate(fromLine: "large.log"))
    }
}
