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
	func testMap1() {
		do {
			let route = try root().dir {[
				$0.a { 1 }.map { "\($0)" }.text(),
				$0.b { [1,2,3] }.map { (i: Int) -> String in "\(i)" }.json()
			]}
			let server = try route.bind(port: 42000).listen()
			let req1 = try CURLRequest("http://localhost:42000/a").perform()
			XCTAssertEqual(req1.bodyString, "1")
			let req2 = try CURLRequest("http://localhost:42000/b").perform().bodyJSON(Array<String>.self)
			XCTAssertEqual(req2, ["1","2","3"])
			try server.stop().wait()
		} catch {
			XCTFail("\(error)")
		}
	}
	func testStatusCheck1() {
		do {
			let route = try root().dir {[
				$0.a.statusCheck { .internalServerError }.map { "BAD" }.text(),
				$0.b.statusCheck { _ in .internalServerError }.map { "BAD" }.text(),
				$0.c.statusCheck { _ in .ok }.map { "OK" }.text()
				]}
			let server = try route.bind(port: 42000).listen()
			let req1 = try CURLRequest("http://localhost:42000/a").perform()
			XCTAssertEqual(req1.responseCode, 500)
			let req2 = try CURLRequest("http://localhost:42000/b").perform()
			XCTAssertEqual(req2.responseCode, 500)
			let req3 = try CURLRequest("http://localhost:42000/c").perform().bodyString
			XCTAssertEqual(req3, "OK")
			try server.stop().wait()
		} catch {
			XCTFail("\(error)")
		}
	}
	func testMethods1() {
		do {
			let route = try root().dir {[
				$0.GET.foo1 { "GET OK" },
				$0.POST.foo2 { "POST OK" },
				]}.text()
			let server = try route.bind(port: 42000).listen()
			let req1 = try CURLRequest("http://localhost:42000/foo1").perform().bodyString
			XCTAssertEqual(req1, "GET OK")
			let req2 = try CURLRequest("http://localhost:42000/foo2", .postString("")).perform().bodyString
			XCTAssertEqual(req2, "POST OK")
			let req3 = try CURLRequest("http://localhost:42000/foo1", .postString("")).perform().responseCode
			XCTAssertEqual(req3, 404)
			try server.stop().wait()
		} catch {
			XCTFail("\(error)")
		}
	}
	func testReadBody1() {
		do {
			let route = try root().dir(type: String.self) {[
				$0.multi.readBody {
					req, cont in
					switch cont {
					case .multiPartForm(_):
						return "OK"
					case .none, .urlForm, .other:
						throw HTTPOutputError(status: .badRequest)
					}
				},
				$0.url.readBody {
					req, cont in
					switch cont {
					case .urlForm(_):
						return "OK"
					case .none, .multiPartForm, .other:
						throw HTTPOutputError(status: .badRequest)
					}
				},
				$0.other.readBody {
					req, cont in
					switch cont {
					case .other(_):
						return "OK"
					case .none, .multiPartForm, .urlForm:
						throw HTTPOutputError(status: .badRequest)
					}
				},
			]}.POST.text()
			let server = try route.bind(port: 42000).listen()
			let req1 = try CURLRequest("http://localhost:42000/multi", .postField(.init(name: "foo", value: "bar"))).perform().bodyString
			XCTAssertEqual(req1, "OK")
			let req2 = try CURLRequest("http://localhost:42000/url", .postString("foo=bar")).perform().bodyString
			XCTAssertEqual(req2, "OK")
			let req3 = try CURLRequest("http://localhost:42000/other", .addHeader(.contentType, "application/octet-stream"), .postData([1,2,3,4,5])).perform().bodyString
			XCTAssertEqual(req3, "OK")
			try server.stop().wait()
		} catch {
			XCTFail("\(error)")
		}
	}
	func testDecodeBody1() {
		struct Foo: Codable {
			let id: UUID
			let date: Date
		}
		do {
			let route = try root().POST.dir{[
				$0.1.decode(Foo.self).json(),
				$0.2.decode(Foo.self) { $1 }.json(),
				$0.3.decode(Foo.self) { $0 }.json(),
				]}
			let server = try route.bind(port: 42000).listen()
			let foo = Foo(id: UUID(), date: Date())
			let fooData = Array(try JSONEncoder().encode(foo))
			for i in 1...3 {
				let req = try CURLRequest("http://localhost:42000/\(i)", .addHeader(.contentType, "application/json"), .postData(fooData)).perform().bodyJSON(Foo.self)
				XCTAssertEqual(req.id, foo.id)
				XCTAssertEqual(req.date, foo.date)
			}
			try server.stop().wait()
		} catch {
			XCTFail("\(error)")
		}
	}
	func testPathExt1() {
		struct Foo: Codable, CustomStringConvertible {
			var description: String {
				return "foo-data \(id)/\(date)"
			}
			let id: UUID
			let date: Date
		}
		do {
			let fooRoute = root().foo { Foo(id: UUID(), date: Date()) }
			let route = try root().dir(
				fooRoute.ext("json").json(),
				fooRoute.ext("txt").text())
			let server = try route.bind(port: 42000).listen()
			let req1 = try? CURLRequest("http://localhost:42000/foo.json").perform().bodyJSON(Foo.self)
			XCTAssertNotNil(req1)
			let req2 = try CURLRequest("http://localhost:42000/foo.txt").perform().bodyString
			XCTAssert(req2.hasPrefix("foo-data "))
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
//		print("\(q.lookup)")
//		print("\(q.ranges)")
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
//	func testStringDecodeSpeed() {
//		func printTupes(_ t: [(String,String)]) {
//			for c in "abcdefghijklmnopqrstuvwxyz" {
//				let key = "abc" + String(c)
//				let _ = t.first { $0.0 == key }
//				//				print(fnd)
//			}
//		}
//		let body = "abca=abcdefghijklmnopqrstuvwxyz&abcb=abcdefghijklmnopqrstuvwxyz&abcc=abcdefghijklmnopqrstuvwxyz&abcd=abcdefghijklmnopqrstuvwxyz&abce=abcdefghijklmnopqrstuvwxyz&abcf=abcdefghijklmnopqrstuvwxyz&abcg=abcdefghijklmnopqrstuvwxyz&abch=abcdefghijklmnopqrstuvwxyz&abci=abcdefghijklmnopqrstuvwxyz&abcj=abcdefghijklmnopqrstuvwxyz&abck=abcdefghijklmnopqrstuvwxyz&abcl=abcdefghijklmnopqrstuvwxyz&abcm=abcdefghijklmnopqrstuvwxyz&abcn=abcdefghijklmnopqrstuvwxyz&abco=abcdefghijklmnopqrstuvwxyz&abcp=abcdefghijklmnopqrstuvwxyz&abcq=abcdefghijklmnopqrstuvwxyz&abca=abcdefghijklmnopqrstuvwxyz&abcs=abcdefghijklmnopqrstuvwxyz&abct=abcdefghijklmnopqrstuvwxyz&abcu=abcdefghijklmnopqrstuvwxyz&abcv=abcdefghijklmnopqrstuvwxyz&abcw=abcdefghijklmnopqrstuvwxyz&abcx=abcdefghijklmnopqrstuvwxyz&abcy=abcdefghijklmnopqrstuvwxyz&abcz=abcdefghijklmnopqrstuvwxyz"
//		self.measure {
//			for _ in 0..<20000 {
//				let q = body.decodedQuery
//				printTupes(q)
//			}
//		}
//	}
	
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
