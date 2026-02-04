import XCTest
@testable import MoshTerminal

final class PredictionNetworkSnapshotStoreTests: XCTestCase {
    func testInitialState() {
        let store = PredictionNetworkSnapshotStore()
        let snapshot = store.snapshot()
        
        XCTAssertEqual(snapshot.lastSentStateNum, 0)
        XCTAssertEqual(snapshot.lastAckedStateNum, 0)
        XCTAssertEqual(snapshot.echoAck, 0)
        XCTAssertNil(snapshot.srttMillis)
    }
    
    func testSetLastSent() {
        let store = PredictionNetworkSnapshotStore()
        store.setLastSent(42)
        
        let snapshot = store.snapshot()
        XCTAssertEqual(snapshot.lastSentStateNum, 42)
        XCTAssertEqual(snapshot.lastAckedStateNum, 0)
        XCTAssertEqual(snapshot.echoAck, 0)
    }
    
    func testSetLastAcked() {
        let store = PredictionNetworkSnapshotStore()
        store.setLastAcked(100)
        
        let snapshot = store.snapshot()
        XCTAssertEqual(snapshot.lastSentStateNum, 0)
        XCTAssertEqual(snapshot.lastAckedStateNum, 100)
        XCTAssertEqual(snapshot.echoAck, 0)
    }
    
    func testSetEchoAck() {
        let store = PredictionNetworkSnapshotStore()
        store.setEchoAck(200)
        
        let snapshot = store.snapshot()
        XCTAssertEqual(snapshot.lastSentStateNum, 0)
        XCTAssertEqual(snapshot.lastAckedStateNum, 0)
        XCTAssertEqual(snapshot.echoAck, 200)
    }
    
    func testSetSrtt() {
        let store = PredictionNetworkSnapshotStore()
        store.setSrtt(150)
        
        let snapshot = store.snapshot()
        XCTAssertEqual(snapshot.lastSentStateNum, 0)
        XCTAssertEqual(snapshot.lastAckedStateNum, 0)
        XCTAssertEqual(snapshot.echoAck, 0)
        XCTAssertEqual(snapshot.srttMillis, 150)
    }
    
    func testSetSrttNil() {
        let store = PredictionNetworkSnapshotStore()
        store.setSrtt(150)
        store.setSrtt(nil)
        
        let snapshot = store.snapshot()
        XCTAssertNil(snapshot.srttMillis)
    }
    
    func testMultipleUpdatesPreserveOtherFields() {
        let store = PredictionNetworkSnapshotStore()
        
        store.setLastSent(1)
        store.setLastAcked(2)
        store.setEchoAck(3)
        store.setSrtt(100)
        
        store.setLastSent(10)
        let snapshot1 = store.snapshot()
        XCTAssertEqual(snapshot1.lastSentStateNum, 10)
        XCTAssertEqual(snapshot1.lastAckedStateNum, 2)
        XCTAssertEqual(snapshot1.echoAck, 3)
        XCTAssertEqual(snapshot1.srttMillis, 100)
        
        store.setLastAcked(20)
        let snapshot2 = store.snapshot()
        XCTAssertEqual(snapshot2.lastSentStateNum, 10)
        XCTAssertEqual(snapshot2.lastAckedStateNum, 20)
        XCTAssertEqual(snapshot2.echoAck, 3)
        XCTAssertEqual(snapshot2.srttMillis, 100)
        
        store.setEchoAck(30)
        let snapshot3 = store.snapshot()
        XCTAssertEqual(snapshot3.lastSentStateNum, 10)
        XCTAssertEqual(snapshot3.lastAckedStateNum, 20)
        XCTAssertEqual(snapshot3.echoAck, 30)
        XCTAssertEqual(snapshot3.srttMillis, 100)
        
        store.setSrtt(200)
        let snapshot4 = store.snapshot()
        XCTAssertEqual(snapshot4.lastSentStateNum, 10)
        XCTAssertEqual(snapshot4.lastAckedStateNum, 20)
        XCTAssertEqual(snapshot4.echoAck, 30)
        XCTAssertEqual(snapshot4.srttMillis, 200)
    }
    
    func testConcurrentReadsDoNotCrash() {
        let store = PredictionNetworkSnapshotStore()
        let expectation = XCTestExpectation(description: "Concurrent operations complete")
        
        let iterations = 1000
        expectation.expectedFulfillmentCount = iterations
        
        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            let snapshot = store.snapshot()
            XCTAssertNotNil(snapshot)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testConcurrentWritesDoNotCrash() {
        let store = PredictionNetworkSnapshotStore()
        let expectation = XCTestExpectation(description: "Concurrent operations complete")
        
        let iterations = 1000
        expectation.expectedFulfillmentCount = iterations
        
        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            switch i % 4 {
            case 0:
                store.setLastSent(UInt64(i))
            case 1:
                store.setLastAcked(UInt64(i))
            case 2:
                store.setEchoAck(UInt64(i))
            case 3:
                store.setSrtt(i % 2 == 0 ? UInt64(i) : nil)
            default:
                break
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testConcurrentReadsAndWritesDoNotCrash() {
        let store = PredictionNetworkSnapshotStore()
        let expectation = XCTestExpectation(description: "Concurrent operations complete")
        
        let iterations = 2000
        expectation.expectedFulfillmentCount = iterations
        
        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            if i % 2 == 0 {
                let snapshot = store.snapshot()
                XCTAssertNotNil(snapshot)
            } else {
                store.setLastSent(UInt64(i))
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testInvariantLastAckedNeverExceedsLastSent() {
        let store = PredictionNetworkSnapshotStore()
        
        for i in 0..<100 {
            store.setLastSent(UInt64(i * 10))
            store.setLastAcked(UInt64(i * 5))
            
            let snapshot = store.snapshot()
            XCTAssertLessThanOrEqual(snapshot.lastAckedStateNum, snapshot.lastSentStateNum,
                                     "Invariant violated: lastAcked (\(snapshot.lastAckedStateNum)) > lastSent (\(snapshot.lastSentStateNum))")
        }
    }
    
    func testSnapshotReflectsLastWrittenValues() {
        let store = PredictionNetworkSnapshotStore()
        
        let expectedSent: UInt64 = 12345
        let expectedAcked: UInt64 = 12340
        let expectedEchoAck: UInt64 = 12338
        let expectedSrtt: UInt64 = 87
        
        store.setLastSent(expectedSent)
        store.setLastAcked(expectedAcked)
        store.setEchoAck(expectedEchoAck)
        store.setSrtt(expectedSrtt)
        
        let snapshot = store.snapshot()
        XCTAssertEqual(snapshot.lastSentStateNum, expectedSent)
        XCTAssertEqual(snapshot.lastAckedStateNum, expectedAcked)
        XCTAssertEqual(snapshot.echoAck, expectedEchoAck)
        XCTAssertEqual(snapshot.srttMillis, expectedSrtt)
    }
}
