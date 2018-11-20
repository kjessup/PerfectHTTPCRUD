import XCTest
import NIOHTTP1
import NIO
import PerfectCRUD
import PerfectSQLite
import PerfectCURL
@testable import HTTPCRUDLib

final class HTTPCRUDLibTests: XCTestCase {
	
	func testRoot1() {
		do {
			let route = root { "OK" }.text()
			let server = try route.bind(port: 42000).listen()
			let req = try CURLRequest("http://localhost:42000/").perform()
			XCTAssertEqual(req.bodyString, "OK")
			try server.stop().wait()
		} catch {
			XCTFail("\(error)")
		}
	}
	func testRoot2() {
		do {
			let route1 = root { "OK2" }.text()
			let route2 = root { "OK1" }.foo { $0 }.text()
			let server = try root().dir(route1, route2).bind(port: 42000).listen()
			let resp1 = try CURLRequest("http://localhost:42000/foo").perform().bodyString
			XCTAssertEqual(resp1, "OK1")
			let resp2 = try CURLRequest("http://localhost:42000/").perform().bodyString
			XCTAssertEqual(resp2, "OK2")
			try server.stop().wait()
		} catch {
			XCTFail("\(error)")
		}
	}
	func testDir1() {
		do {
			let route = try root().dir{[
				$0.foo1 { "OK1" },
				$0.foo2 { "OK2" },
				$0.foo3 { "OK3" },
				]}.text()
			let server = try route.bind(port: 42000).listen()
			let resp1 = try CURLRequest("http://localhost:42000/foo1").perform().bodyString
			XCTAssertEqual(resp1, "OK1")
			let resp2 = try CURLRequest("http://localhost:42000/foo2").perform().bodyString
			XCTAssertEqual(resp2, "OK2")
			let resp3 = try CURLRequest("http://localhost:42000/foo3").perform().bodyString
			XCTAssertEqual(resp3, "OK3")
			try server.stop().wait()
		} catch {
			XCTFail("\(error)")
		}
	}
	func testDuplicates() {
		do {
			let route = try root().dir{[
				$0.foo1 { "OK1" },
				$0.foo1 { "OK2" },
				$0.foo3 { "OK3" },
				]}.text()
			let server = try route.bind(port: 42000).listen()
			try server.stop().wait()
			XCTAssert(false)
		} catch {
			XCTAssert(true)
		}
	}
	func testUriVars() {
		struct Req: Codable {
			let id: UUID
			let action: String
		}
		do {
			let route = root().v1
				.wild(name: "id")
				.wild(name: "action")
				.decode(Req.self) { return "\($1.id) - \($1.action)" }
				.text()
			let id = UUID().uuidString
			let action = "share"
			let uri1 = "/v1/\(id)/\(action)"
			let server = try route.bind(port: 42000).listen()
			let resp1 = try CURLRequest("http://localhost:42000\(uri1)").perform().bodyString
			XCTAssertEqual(resp1, "\(id) - \(action)")
			try server.stop().wait()
		} catch {
			XCTAssert(true)
		}
	}
	func testWildCard() {
		do {
			let route = root().wild { $1 }.foo.text()
			let server = try route.bind(port: 42000).listen()
			let req = try CURLRequest("http://localhost:42000/OK/foo").perform()
			XCTAssertEqual(req.bodyString, "OK")
			try server.stop().wait()
		} catch {
			XCTFail("\(error)")
		}
	}
	func testTrailingWildCard() {
		do {
			let route = root().foo.trailing { $1 }.text()
			let server = try route.bind(port: 42000).listen()
			let req = try CURLRequest("http://localhost:42000/foo/OK/OK").perform()
			XCTAssertEqual(req.bodyString, "OK/OK")
			try server.stop().wait()
		} catch {
			XCTFail("\(error)")
		}
	}
	
	func testByteBufferCollection() {
		let alloc = ByteBufferAllocator()
		func b(_ s: String) -> ByteBuffer {
			var b = alloc.buffer(capacity: s.count)
			b.write(string: s)
			return b
		}
		do {
			let buffers = [b("012"), b("34"), b("5678"), b("9")]
			let collection = ByteBufferCollection(buffers: buffers)
			XCTAssertEqual(10, collection.count)
			for i in 0...9 {
				let c = Character(Unicode.Scalar(collection[i]))
				XCTAssertEqual("\(i)", "\(c)")
			}
		}
		do {
			let buffers = [b("0000"), b("012"), b("34"), b("5678"), b("9")]
			let collection = ByteBufferCollection(buffers: buffers, offset: 4)
			XCTAssertEqual(10, collection.count)
			for i in 0...9 {
				let c = Character(Unicode.Scalar(collection[i]))
				XCTAssertEqual("\(i)", "\(c)")
			}
		}
		do {
			let buffers = [b("0123456789")]
			let collection = ByteBufferCollection(buffers: buffers)
			XCTAssertEqual(10, collection.count)
			for i in 0...9 {
				let c = Character(Unicode.Scalar(collection[i]))
				XCTAssertEqual("\(i)", "\(c)")
			}
		}
	}
	func testQueryDecoder() {
		let q = QueryDecoder(Array("a=1&b=2&c=3&d=4&b=5&e&f=&g=1234567890&h".utf8))
		XCTAssertEqual(q["not"], [])
		XCTAssertEqual(q["a"], ["1"])
		XCTAssertEqual(q["b"], ["2", "5"])
		XCTAssertEqual(q["c"], ["3"])
		XCTAssertEqual(q["d"], ["4"])
		XCTAssertEqual(q["e"], [""])
		XCTAssertEqual(q["f"], [""])
		XCTAssertEqual(q["g"], ["1234567890"])
		XCTAssertEqual(q["h"], [""])
		print("\(q.lookup)")
		print("\(q.ranges)")
	}
	func testQueryDecoderSpeed() {
		func printTupes(_ t: QueryDecoder) {
			for c in "abcdefghijklmnopqrstuvwxyz" {
				let key = "abc" + String(c)
				let _ = t.get(key)
				//				print(fnd)
			}
		}
		let body = Array("abca=abcdefghijklmnopqrstuvwxyz&abcb=abcdefghijklmnopqrstuvwxyz&abcc=abcdefghijklmnopqrstuvwxyz&abcd=abcdefghijklmnopqrstuvwxyz&abce=abcdefghijklmnopqrstuvwxyz&abcf=abcdefghijklmnopqrstuvwxyz&abcg=abcdefghijklmnopqrstuvwxyz&abch=abcdefghijklmnopqrstuvwxyz&abci=abcdefghijklmnopqrstuvwxyz&abcj=abcdefghijklmnopqrstuvwxyz&abck=abcdefghijklmnopqrstuvwxyz&abcl=abcdefghijklmnopqrstuvwxyz&abcm=abcdefghijklmnopqrstuvwxyz&abcn=abcdefghijklmnopqrstuvwxyz&abco=abcdefghijklmnopqrstuvwxyz&abcp=abcdefghijklmnopqrstuvwxyz&abcq=abcdefghijklmnopqrstuvwxyz&abca=abcdefghijklmnopqrstuvwxyz&abcs=abcdefghijklmnopqrstuvwxyz&abct=abcdefghijklmnopqrstuvwxyz&abcu=abcdefghijklmnopqrstuvwxyz&abcv=abcdefghijklmnopqrstuvwxyz&abcw=abcdefghijklmnopqrstuvwxyz&abcx=abcdefghijklmnopqrstuvwxyz&abcy=abcdefghijklmnopqrstuvwxyz&abcz=abcdefghijklmnopqrstuvwxyz".utf8)
		self.measure {
			for _ in 0..<20000 {
				let q = QueryDecoder(body)
				printTupes(q)
			}
		}
	}
	func testStringDecodeSpeed() {
		func printTupes(_ t: [(String,String)]) {
			for c in "abcdefghijklmnopqrstuvwxyz" {
				let key = "abc" + String(c)
				let _ = t.first { $0.0 == key }
				//				print(fnd)
			}
		}
		let body = "abca=abcdefghijklmnopqrstuvwxyz&abcb=abcdefghijklmnopqrstuvwxyz&abcc=abcdefghijklmnopqrstuvwxyz&abcd=abcdefghijklmnopqrstuvwxyz&abce=abcdefghijklmnopqrstuvwxyz&abcf=abcdefghijklmnopqrstuvwxyz&abcg=abcdefghijklmnopqrstuvwxyz&abch=abcdefghijklmnopqrstuvwxyz&abci=abcdefghijklmnopqrstuvwxyz&abcj=abcdefghijklmnopqrstuvwxyz&abck=abcdefghijklmnopqrstuvwxyz&abcl=abcdefghijklmnopqrstuvwxyz&abcm=abcdefghijklmnopqrstuvwxyz&abcn=abcdefghijklmnopqrstuvwxyz&abco=abcdefghijklmnopqrstuvwxyz&abcp=abcdefghijklmnopqrstuvwxyz&abcq=abcdefghijklmnopqrstuvwxyz&abca=abcdefghijklmnopqrstuvwxyz&abcs=abcdefghijklmnopqrstuvwxyz&abct=abcdefghijklmnopqrstuvwxyz&abcu=abcdefghijklmnopqrstuvwxyz&abcv=abcdefghijklmnopqrstuvwxyz&abcw=abcdefghijklmnopqrstuvwxyz&abcx=abcdefghijklmnopqrstuvwxyz&abcy=abcdefghijklmnopqrstuvwxyz&abcz=abcdefghijklmnopqrstuvwxyz"
		self.measure {
			for _ in 0..<20000 {
				let q = body.decodedQuery
				printTupes(q)
			}
		}
	}
	
    static var allTests = [
		("testRoot1", testRoot1),
		("testRoot2", testRoot2),
		("testDir1", testDir1),
		("testDuplicates", testDuplicates),
		("testUriVars", testUriVars),
		("testWildCard", testWildCard),
		("testTrailingWildCard", testTrailingWildCard),
		
		("testQueryDecoder", testQueryDecoder),
    ]
}
