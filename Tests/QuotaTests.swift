import XCTest
import AppKit
#if SWIFT_PACKAGE
@testable import QuotaCore
#else
@testable import CodexQuotaRing
#endif

final class QuotaParserTests: XCTestCase {
    func fixture(_ name: String) throws -> [String: Any] {
        #if SWIFT_PACKAGE
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        #else
        let url = Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        #endif
        return (try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any])["result"] as! [String: Any]
    }
    func testDualAndSwapped() throws {
        for name in ["dual", "swapped"] {
            let windows = QuotaParser.parse(try fixture(name)).windows
            XCTAssertEqual(windows.map(\.kind), [.fiveHour, .weekly]); XCTAssertEqual(windows.map(\.remaining), [72, 43])
        }
    }
    func testSingleWindowsAndNulls() throws {
        XCTAssertEqual(QuotaParser.parse(try fixture("weekly")).windows.map(\.kind), [.weekly])
        XCTAssertEqual(QuotaParser.parse(try fixture("weekly")).windows.first?.remaining, 50)
        XCTAssertEqual(QuotaParser.parse(try fixture("fiveHour")).windows.map(\.remaining), [25])
        XCTAssertTrue(QuotaParser.parse(try fixture("empty")).windows.isEmpty)
        XCTAssertTrue(QuotaParser.parse(try fixture("unknown")).windows.isEmpty)
        XCTAssertTrue(QuotaParser.parse(try fixture("nullUsed")).windows.isEmpty)
    }
    func testExtremesMissingAndReset() throws {
        XCTAssertEqual(QuotaParser.parse(try fixture("zeroFull")).windows.map(\.remaining), [0, 100])
        let windows = QuotaParser.parse(try fixture("missing")).windows
        XCTAssertEqual(windows.count, 1); XCTAssertNil(windows.first?.resetsAt)
        XCTAssertEqual(QuotaParser.parse(try fixture("dual")).windows.first?.resetsAt?.timeIntervalSince1970, 1790000000)
        let raw: [String: Any] = ["rateLimits": ["primary": ["usedPercent": -20, "windowDurationMins": 300], "secondary": ["usedPercent": 140, "windowDurationMins": 10080]]]
        XCTAssertEqual(QuotaParser.parse(raw).windows.map(\.remaining), [100, 0])
    }
    func testBucketIsolationAndPermissions() throws {
        let dual = try fixture("dual")["rateLimits"]!
        let foreign: [String: Any] = ["limitId": "codex_other", "primary": ["usedPercent": 1, "windowDurationMins": 300]]
        XCTAssertEqual(QuotaParser.parse(["rateLimitsByLimitId": ["codex": dual], "rateLimits": foreign]).windows.map(\.remaining), [72, 43])
        XCTAssertTrue(QuotaParser.parse(["rateLimits": foreign]).windows.isEmpty)
        XCTAssertTrue(QuotaParser.parse(["rateLimitsByLimitId": ["codex_other": foreign], "rateLimits": ["primary": ["usedPercent": 1, "windowDurationMins": 300]]]).windows.isEmpty)
        XCTAssertEqual(QuotaParser.parse(["rateLimits": dual, "ordinaryUsageAllowed": false]).ordinaryUsageAllowed, false)
        XCTAssertEqual(QuotaParser.parse(["rateLimits": ["limitId":"codex", "spendControlReached":true]]).restriction, "spend_control_reached")
    }
    func testInvalidNumericAndTooltip() {
        let raw: [String: Any] = ["rateLimits": ["primary": ["usedPercent": false, "windowDurationMins": 300]]]
        XCTAssertTrue(QuotaParser.parse(raw).windows.isEmpty)
        XCTAssertEqual(QuotaSnapshot(windows: [.init(kind:.weekly, remaining:50)]).tooltip, "7d: 50% remaining")
        XCTAssertEqual(QuotaSnapshot(windows: []).tooltip, "Codex quota unavailable")
    }
    func testAccountIdentityAndLogin() throws {
        func account(_ email: String) -> [String: Any] { ["account": ["type":"chatgpt", "email": email]] }
        let first = try QuotaParser.identity(account("first@example.invalid"))
        let second = try QuotaParser.identity(account("second@example.invalid"))
        XCTAssertNotEqual(first, second); XCTAssertFalse(first!.contains("example"))
        XCTAssertThrowsError(try QuotaParser.identity(["account": NSNull()]))
        XCTAssertThrowsError(try QuotaParser.identity(["account": ["type": "apiKey"]]))
        XCTAssertNil(try QuotaParser.identity(["account": ["type":"chatgpt", "email":NSNull()]]))
    }
    func testFramingPartialAndMultiple() throws {
        var framer = JSONLineFramer()
        XCTAssertTrue(try framer.append(Data("{\"id\":".utf8)).isEmpty)
        let lines = try framer.append(Data("1}\n{\"id\":2}\npartial".utf8))
        XCTAssertEqual(lines.count, 2); XCTAssertEqual(String(data: lines[0], encoding: .utf8), "{\"id\":1}")
        XCTAssertThrowsError(try framer.append(Data(repeating: 65, count: 8 * 1024 * 1024)))
    }
    func testRetryBackoff() {
        var policy = RetryPolicy()
        XCTAssertEqual((0..<7).map { _ in policy.failed() }, [5,15,30,60,120,120,120])
        policy.succeeded(); XCTAssertEqual(policy.failed(), 5)
    }
}
@MainActor final class RingRendererTests: XCTestCase {
    func testLayoutAndRendering() {
        let dual: [QuotaWindow] = [.init(kind:.weekly, remaining:43), .init(kind:.fiveHour, remaining:72)]
        let specs = RingIconRenderer.layout(dual)
        XCTAssertEqual(specs.map(\.kind), [.fiveHour, .weekly]); XCTAssertEqual(specs.map(\.fraction), [0.72,0.43])
        XCTAssertGreaterThan(specs[0].radius - specs[1].radius, 2)
        XCTAssertEqual(RingIconRenderer.layout([dual[0]]).first?.radius, 8)
        for state in [QuotaState.ready, .loading, .stale, .error, .unauthenticated, .cliUnavailable, .noQuotaData] {
            let image = RingIconRenderer.render(windows: state == .ready ? dual : [], state: state)
            XCTAssertEqual(image.size.width,20); XCTAssertNotNil(image.tiffRepresentation)
        }
        XCTAssertEqual(RingIconRenderer.color(.init(kind:.weekly,remaining:9)), .systemRed)
        XCTAssertEqual(RingIconRenderer.color(.init(kind:.weekly,remaining:10)), .systemOrange)
        XCTAssertEqual(RingIconRenderer.color(.init(kind:.weekly,remaining:30)), .systemOrange)
        XCTAssertEqual(RingIconRenderer.color(.init(kind:.weekly,remaining:31)), .systemGreen)
    }
}
@MainActor final class AppServerClientTests: XCTestCase {
    var fixturePath: String {
        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: "server", withExtension: "py", subdirectory: "Fixtures")!.path
        #else
        return Bundle(for: Self.self).url(forResource: "server", withExtension: "py", subdirectory: "Fixtures")!.path
        #endif
    }
    func waitFor(_ predicate: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<150 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Service did not reach expected state")
    }
    func testServiceInitialAuthNotificationStaleAndAccountSwitch() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let scenario = folder.appendingPathComponent("scenario.json")
        func write(_ value: [String: Any]) throws { try JSONSerialization.data(withJSONObject:value).write(to:scenario,options:.atomic) }
        try write(["email":"a@example.invalid"])
        let suite = "ServiceTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!; defer { defaults.removePersistentDomain(forName:suite) }
        let settings = AppSettings(defaults:defaults); settings.cliPath = "/usr/bin/python3"
        let service = QuotaService(settings:settings, cacheFile:folder.appendingPathComponent("cache.json"), serverArguments:[fixturePath,"scenario",scenario.path])
        service.start(); defer { service.stop() }
        try await waitFor { service.state == .ready && !service.refreshing }
        XCTAssertEqual(service.snapshot?.windows.map(\.remaining),[50]); XCTAssertEqual(service.snapshot?.ordinaryUsageAllowed,false)
        XCTAssertTrue(FileManager.default.fileExists(atPath:folder.appendingPathComponent("cache.json").path))
        try write(["email":"a@example.invalid","error":true]); service.refresh()
        try await waitFor { service.state == .stale && !service.refreshing }
        XCTAssertEqual(service.snapshot?.windows.map(\.remaining),[50]); XCTAssertTrue(service.message?.contains("unverified") == true)
        try write(["email":"b@example.invalid","error":true]); service.refresh()
        try await waitFor { service.state == .error && !service.refreshing }
        XCTAssertNil(service.snapshot)
        XCTAssertFalse(FileManager.default.fileExists(atPath:folder.appendingPathComponent("cache.json").path))
        try write(["loggedOut":true]); service.refresh()
        try await waitFor { service.state == .unauthenticated && !service.refreshing }
        XCTAssertNil(service.snapshot)
    }
    func testServiceCrashAutomaticallyRecoversWithBackoff() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let scenario=folder.appendingPathComponent("scenario.json")
        try JSONSerialization.data(withJSONObject:["crashOnce":true]).write(to:scenario)
        let suite="RecoveryTests-"+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!; defer { defaults.removePersistentDomain(forName:suite) }
        let settings=AppSettings(defaults:defaults);settings.cliPath="/usr/bin/python3"
        let service=QuotaService(settings:settings,cacheFile:folder.appendingPathComponent("cache.json"),serverArguments:[fixturePath,"scenario",scenario.path])
        let start=Date();service.start();defer { service.stop() }
        try await waitFor { service.state == .ready && !service.refreshing }
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start),4.8)
        XCTAssertEqual(service.snapshot?.windows.map(\.remaining),[50])
    }
    func makeClient() async throws -> CodexAppServerClient {
        let client = CodexAppServerClient()
        try await client.start(executable: URL(fileURLWithPath:"/usr/bin/python3"), arguments: [fixturePath])
        return client
    }
    func testHandshakeConcurrentResponsesAndNotification() async throws {
        let client = try await makeClient(); defer { client.stop() }
        let event = expectation(description:"quota notification")
        client.onNotification = { method, params in
            XCTAssertEqual(method,"account/rateLimits/updated")
            XCTAssertEqual(QuotaParser.parse(params).windows.map(\.remaining), [50]); event.fulfill()
        }
        async let first = client.request("first")
        async let second = client.request("second")
        let responses = try await (first, second)
        XCTAssertEqual(responses.0["echo"] as? String, "first"); XCTAssertEqual(responses.1["echo"] as? String, "second")
        _ = try await client.request("events")
        await fulfillment(of: [event], timeout: 2)
    }
    func testTimeoutThenRecovery() async throws {
        let client = try await makeClient(); defer { client.stop() }
        do { _ = try await client.request("timeout", timeout:0.1); XCTFail("Expected timeout") }
        catch { guard case QuotaError.timeout = error else { return XCTFail("Unexpected error") } }
        let result = try await client.request("recovered"); XCTAssertEqual(result["echo"] as? String, "recovered")
    }
    func testCrashAndRestart() async throws {
        let client = try await makeClient(); defer { client.stop() }
        do { _ = try await client.request("crash", timeout:2); XCTFail("Expected disconnect") } catch { }
        try await client.start(executable: URL(fileURLWithPath:"/usr/bin/python3"), arguments:[fixturePath])
        XCTAssertTrue(client.isRunning)
        _ = try await client.request("restarted")
    }
    func testStopReapsChild() async throws {
        let client = try await makeClient()
        let result = try await client.request("pid"); let pid = result["pid"] as! Int32
        client.stop()
        for _ in 0..<40 {
            if kill(pid, 0) != 0 { return }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        XCTFail("Child remained alive after shutdown")
    }
}
@MainActor final class SettingsTests: XCTestCase {
    func testPersistence() {
        let name = "QuotaTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName:name)!; defer { defaults.removePersistentDomain(forName:name) }
        let settings = AppSettings(defaults:defaults)
        XCTAssertEqual(settings.interval,60); XCTAssertTrue(settings.launchHidden); XCTAssertFalse(settings.diagnostics)
        settings.interval = 300; settings.theme = "Dark"; settings.cliPath = "/tmp/test-codex"
        let reloaded = AppSettings(defaults:defaults)
        XCTAssertEqual(reloaded.interval,300); XCTAssertEqual(reloaded.theme,"Dark"); XCTAssertEqual(reloaded.cliPath,"/tmp/test-codex")
    }
    func testInvalidCLIOverride() { XCTAssertThrowsError(try CodexCLIResolver.resolve(override:"/nonexistent/codex")) }
}
