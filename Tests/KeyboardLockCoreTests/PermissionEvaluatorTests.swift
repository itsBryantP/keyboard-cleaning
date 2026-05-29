import XCTest
@testable import KeyboardLockCore

/// Unit coverage for the silent-check / probe combiner (PERM-4, REV-10). The
/// raw system calls can't be made deterministic in CI, so we test the pure
/// `PermissionEvaluator` against a fake `PermissionProbing` (TEST-C).
final class PermissionEvaluatorTests: XCTestCase {

    /// Fake that records how many times the (expensive) tap probe was consulted,
    /// so we can assert the short-circuit when a permission is missing.
    private final class FakeProbe: PermissionProbing {
        var accessibility: Bool
        var inputMonitoring: Bool
        var probeResult: Bool
        private(set) var probeCallCount = 0

        init(accessibility: Bool, inputMonitoring: Bool, probeResult: Bool) {
            self.accessibility = accessibility
            self.inputMonitoring = inputMonitoring
            self.probeResult = probeResult
        }

        func isAccessibilityGranted() -> Bool { accessibility }
        func isInputMonitoringGranted() -> Bool { inputMonitoring }
        func tapCreationProbeSucceeds() -> Bool {
            probeCallCount += 1
            return probeResult
        }
    }

    func testBothGrantedAndProbePasses_isReady() {
        let probe = FakeProbe(accessibility: true, inputMonitoring: true, probeResult: true)
        XCTAssertEqual(PermissionEvaluator.evaluate(using: probe), .ready)
        XCTAssertTrue(PermissionStatus.ready.canLock)
        XCTAssertEqual(probe.probeCallCount, 1)
    }

    func testBothGrantedButProbeFails_needsRelaunch() {
        let probe = FakeProbe(accessibility: true, inputMonitoring: true, probeResult: false)
        XCTAssertEqual(PermissionEvaluator.evaluate(using: probe), .needsRelaunch)
        XCTAssertFalse(PermissionStatus.needsRelaunch.canLock)
        XCTAssertEqual(probe.probeCallCount, 1)
    }

    func testAccessibilityMissing_reportsMissingAndSkipsProbe() {
        let probe = FakeProbe(accessibility: false, inputMonitoring: true, probeResult: true)
        XCTAssertEqual(
            PermissionEvaluator.evaluate(using: probe),
            .missingPermissions(accessibility: false, inputMonitoring: true)
        )
        // REV-10: the probe is meaningless without permissions and must not run.
        XCTAssertEqual(probe.probeCallCount, 0)
    }

    func testInputMonitoringMissing_reportsMissingAndSkipsProbe() {
        let probe = FakeProbe(accessibility: true, inputMonitoring: false, probeResult: true)
        XCTAssertEqual(
            PermissionEvaluator.evaluate(using: probe),
            .missingPermissions(accessibility: true, inputMonitoring: false)
        )
        XCTAssertEqual(probe.probeCallCount, 0)
    }

    func testBothMissing_reportsBothAndSkipsProbe() {
        let probe = FakeProbe(accessibility: false, inputMonitoring: false, probeResult: true)
        XCTAssertEqual(
            PermissionEvaluator.evaluate(using: probe),
            .missingPermissions(accessibility: false, inputMonitoring: false)
        )
        XCTAssertEqual(probe.probeCallCount, 0)
        XCTAssertFalse(
            PermissionStatus.missingPermissions(accessibility: false, inputMonitoring: false).canLock
        )
    }
}
