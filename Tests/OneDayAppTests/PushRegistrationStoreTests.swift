import Foundation
import OneDayCore
import XCTest
@testable import OneDayApp

/// 推送登记状态机钉测（总表 138，DESIGN §397）：经可
/// 测缝（registerAction／environmentProvider／upload
/// ＋proceed/adoptConnection）驱动 PushRegistration-
/// Store——授权门、令牌落盘、上送分型、令牌轮换、终
/// 局失败不重试，全部对 §397 状态机口径
@MainActor
final class PushRegistrationStoreTests: XCTestCase {

    private final class UploadStub: @unchecked Sendable {
        var bodies: [PushTokenRegistrationBody] = []
        var error: Error?
        var response = PushTokenRegisteredResponse(
            registered: true
        )

        func upload(
            client: HermesClientProtocol,
            config: ServerConfig, apiKey: String,
            body: PushTokenRegistrationBody
        ) async throws -> PushTokenRegisteredResponse {
            bodies.append(body)
            if let error { throw error }
            return response
        }
    }

    private final class RegisterRecorder: @unchecked Sendable {
        var calls = 0
    }

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.push.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makeStore(
        recorder: RegisterRecorder,
        stub: UploadStub,
        environment: PushEnvironment? = .sandbox
    ) -> PushRegistrationStore {
        PushRegistrationStore(
            defaults: defaults,
            registerAction: { recorder.calls += 1 },
            environmentProvider: { environment },
            upload: stub.upload
        )
    }

    private func adoptStubConnection(
        _ store: PushRegistrationStore
    ) {
        store.adoptConnection(
            client: FailingHermesClient(),
            config: ServerConfig(
                rawInput: "https://hermes.didichou.site"
            )!,
            apiKey: "test-key"
        )
    }

    private func awaitPhase(
        _ store: PushRegistrationStore,
        _ expected: PushRegistrationPhase,
        timeoutSeconds: Double = 5
    ) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while store.phase != expected, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(store.phase, expected)
    }

    // MARK: 授权门

    func testGrantedProceedRegisters() async {
        let recorder = RegisterRecorder()
        let store = makeStore(
            recorder: recorder, stub: UploadStub()
        )
        await store.proceed(permission: .granted)
        XCTAssertEqual(recorder.calls, 1)
        XCTAssertEqual(store.phase, .registering)
    }

    func testDeniedAndNotDeterminedNeverRegister() async {
        let recorder = RegisterRecorder()
        let store = makeStore(
            recorder: recorder, stub: UploadStub()
        )
        await store.proceed(permission: .denied)
        XCTAssertEqual(recorder.calls, 0)
        XCTAssertEqual(
            store.readinessReport.rows[0].tone, .blocked
        )
        await store.proceed(permission: .notDetermined)
        XCTAssertEqual(recorder.calls, 0)
        XCTAssertEqual(
            store.readinessReport.rows[0].tone, .pending
        )
    }

    func testNoEntitlementFailureIsNotRetried() async {
        let recorder = RegisterRecorder()
        let store = makeStore(
            recorder: recorder, stub: UploadStub()
        )
        store.recordFailure(
            description:
                "no valid 'aps-environment' entitlement string found for application"
        )
        XCTAssertEqual(
            store.phase, .failed(.noEntitlement)
        )
        await store.proceed(permission: .granted)
        XCTAssertEqual(recorder.calls, 0)
    }

    // MARK: 令牌到手→落盘→上送

    func testTokenIntakePersistsAndUploads() async {
        let recorder = RegisterRecorder()
        let stub = UploadStub()
        let store = makeStore(recorder: recorder, stub: stub)
        adoptStubConnection(store)
        store.recordToken(Data([0xde, 0xad]))
        await awaitPhase(store, .registered)
        XCTAssertEqual(store.snapshot?.tokenHex, "dead")
        XCTAssertEqual(store.snapshot?.environment, .sandbox)
        XCTAssertEqual(stub.bodies.count, 1)
        XCTAssertEqual(stub.bodies.first?.deviceToken, "dead")
        XCTAssertEqual(
            stub.bodies.first?.environment, .sandbox
        )
        XCTAssertFalse(stub.bodies.first?.bundleID.isEmpty ?? true)
        // 落盘回读：新存储同 defaults 应见同一快照
        let reread = makeStore(recorder: recorder, stub: stub)
        XCTAssertEqual(reread.snapshot, store.snapshot)
    }

    func testTokenWithoutEnvironmentIsNotUploaded() async {
        let recorder = RegisterRecorder()
        let stub = UploadStub()
        let store = makeStore(
            recorder: recorder, stub: stub, environment: nil
        )
        adoptStubConnection(store)
        store.recordToken(Data([0x01]))
        XCTAssertEqual(
            store.phase, .failed(.environmentUnknown)
        )
        XCTAssertNil(store.snapshot)
        XCTAssertTrue(stub.bodies.isEmpty)
    }

    func testTokenRotationReuploads() async {
        let recorder = RegisterRecorder()
        let stub = UploadStub()
        let store = makeStore(recorder: recorder, stub: stub)
        adoptStubConnection(store)
        store.recordToken(Data([0xaa]))
        await awaitPhase(store, .registered)
        store.recordToken(Data([0xbb]))
        await awaitPhase(store, .registered)
        XCTAssertEqual(stub.bodies.count, 2)
        XCTAssertEqual(stub.bodies.last?.deviceToken, "bb")
        XCTAssertEqual(store.snapshot?.tokenHex, "bb")
    }

    // MARK: 上送分型

    func testUpload404BecomesServerNotReady() async {
        let recorder = RegisterRecorder()
        let stub = UploadStub()
        stub.error = HermesError.pushEndpointNotReady
        let store = makeStore(recorder: recorder, stub: stub)
        adoptStubConnection(store)
        store.recordToken(Data([0x01]))
        await awaitPhase(store, .failed(.serverNotReady))
        XCTAssertEqual(
            store.readinessReport.rows[2].tone, .blocked
        )
    }

    func testUpload401BecomesUnauthorized() async {
        let recorder = RegisterRecorder()
        let stub = UploadStub()
        stub.error = HermesError.apiKeyRejected
        let store = makeStore(recorder: recorder, stub: stub)
        adoptStubConnection(store)
        store.recordToken(Data([0x01]))
        await awaitPhase(store, .failed(.unauthorizedByServer))
    }

    func testUploadRegisteredFalseBecomesServerRejected()
        async {
        let recorder = RegisterRecorder()
        let stub = UploadStub()
        stub.response = PushTokenRegisteredResponse(
            registered: false
        )
        let store = makeStore(recorder: recorder, stub: stub)
        adoptStubConnection(store)
        store.recordToken(Data([0x01]))
        await awaitPhase(store, .failed(.serverRejected))
    }

    // MARK: 点按路由记账

    func testSessionRouteIsRecordedAsPending() {
        let store = makeStore(
            recorder: RegisterRecorder(), stub: UploadStub()
        )
        store.handleRoute(.session(sessionID: "s1"))
        XCTAssertEqual(
            store.pendingRoute, .session(sessionID: "s1")
        )
    }
}
