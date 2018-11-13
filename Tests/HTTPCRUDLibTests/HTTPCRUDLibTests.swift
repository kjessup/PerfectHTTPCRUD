import XCTest
import NIOHTTP1
import NIO
import PerfectCRUD
@testable import HTTPCRUDLib

//class ShimHTTPRequest: HTTPRequest {
//	var contentType: String?
//	
//	var contentConsumed: Int
//	
//	func readSomeContent() -> EventLoopFuture<[ByteBuffer]> {
//		
//	}
//	
//	func readContent() -> EventLoopFuture<HTTPRequestContentType> {
//		
//	}
//	
//	var path = ""
//	var searchArgs: [(String, String)] = []
//	var contentLength: Int = 0
//	var contentRead: Int = 0
//	var uriVariables: [String : String] = [:]
//	var method = HTTPMethod.GET
//	var uri = "" {
//		didSet {
//			let (p, a) = uri.splitUri
//			path = p
//			searchArgs = a
//		}
//	}
//	var headers = HTTPHeaders()
//	func readBody(_ call: @escaping (ByteBuffer?) -> ()) {
//		call(nil)
//	}
//	
//}

final class HTTPCRUDLibTests: XCTestCase {
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
	
    func testScratch() {
		let uris = ["/v1/device/register",
					"/v1/device/unregister",
					"/v1/device/limits",
					"/v1/device/update",
					"/v1/device/share",
					"/v1/device/share/token",
					"/v1/device/unshare",
					"/v1/device/obs/delete",
					"/v1/device/limits",
					"/v1/device/list",
					"/v1/device/info",
					"/v1/device/obs",
					"/v1/group/create",
					"/v1/group/device/add",
					"/v1/group/device/remove",
					"/v1/group/delete",
					"/v1/group/update",
					"/v1/group/device/list",
					"/v1/group/list"]
		struct DeviceRequest: Codable {
			let id: UUID
		}
		struct GroupRequest: Codable {
			let id: UUID?
			let name: String?
		}
		typealias DeviceResponse = DeviceRequest
		typealias GroupResponse = GroupRequest
		
		struct AuthorizedRequest {
			let token: String
			init?(_ request: HTTPRequest) {
				token = "abc"
			}
		}
		
		let authorizedRoute = root(AuthorizedRequest.init)
			.statusCheck { nil == $0 ? .unauthorized : .ok }
			.then { $0! }
		
		let deviceRoutes = authorizedRoute
			.device
				.decode(DeviceRequest.self)
				.dir {[
					$0.register { DeviceResponse(id: $0.id) },
					$0.share.token { DeviceResponse(id: $0.id) }
				]}
		
		let groupRoutes = authorizedRoute
			.group
				.decode(GroupRequest.self)
				.dir {[
					$0.create { GroupResponse(id: $0.id, name: $0.name) }
				]}
		
		let v1 = root()
			.v1.dir(deviceRoutes.json(),
					groupRoutes.json())
		
//		let request = ShimHTTPRequest()
//		request.uri = "/v1/device/share/token?id=\(UUID().uuidString)"
		let uri = "/v1/device/share/token"//request.path
		let finder = try! RouteFinderDual(v1)
		if let fnd = finder[.GET, uri] {
//			let state = HandlerState(request: request, uri: uri)
//			let output = try! fnd(state, request)
//			print(String(validatingUTF8: output.body ?? [])!)
		}
	}
	
	func testExample() {
		func p<O>(_ o: O, _ msg: String) -> O {
			print(msg)
			return o
		}
		struct Authenticator {
			init?(_ request: HTTPRequest) {}
		}
		struct UserRequest: Codable {
			let id: UUID
		}
		struct UserResponse: Codable {
			let id: UUID
			let msg: String
		}
		typealias DeviceRequest = UserRequest
		typealias DeviceResponse = UserResponse
		
		let authenticatedRoute = root(Authenticator.init)
			.statusCheck { nil == $0 ? .unauthorized : .ok }
			.then { $0! }
		
		let user = authenticatedRoute
			.user
			.decode(UserRequest.self) { (auth: $0, user: $1) }
		let device = authenticatedRoute
			.device
			.decode(DeviceRequest.self) { (auth: $0, user: $1) }

		let fullRoutes = root()
			.v1
			.dir(
				user.info { UserResponse(id: $0.1.id, msg: "i") },
				user.wild { p($0, "wild: \($1)") }.info { UserResponse(id: $0.1.id, msg: "i") },
				user.info.d { UserResponse(id: $0.1.id, msg: "id") },
				user.share { UserResponse(id: $0.1.id, msg: "s") },
				device.foo { DeviceResponse(id: $0.1.id, msg: "d") }
			)
		let fullJson = fullRoutes.path("json").json()
		let fullText = fullRoutes.path("text").then { "\($0)" }.text()
		let end = root().dir(fullText, fullJson)

//		let request = ShimHTTPRequest()
//		request.uriVariables = ["id":UUID().uuidString]

		let uri1 = "/v1/user/share/json"
		let uri2 = "/v1/user/FOOBAR/info/json"
		let uri3 = "/v1/user/info/d/json"

		let finder = try! RouteFinderRegExp(end)

		if let fnd = finder[.GET, uri2] {
//			let state = HandlerState(request: request, uri: uri2)
//			let output = try! fnd(state, request)
//			print(String(validatingUTF8: output.body ?? [])!)
		}
	}
	
	func testUriVars() {
		struct Req: Codable {
			let id: UUID
			let action: String
		}
		let uri = root().v1
			.wild(name: "id")
			.wild(name: "action")
			.decode(Req.self) { return "\($1.id) - \($1.action)" }
			.text()
		let finder = try! RouteFinderDual(uri)
		let uu = UUID().uuidString
		let uri1 = "/v1/\(uu)/share"
//		let request = ShimHTTPRequest()
//		request.uri = uri1
//		let output = try! request.run(finder: finder)!
//		XCTAssertEqual("\(uu) - share", String(validatingUTF8: output.body ?? [])!)
	}
	
	func testToDo() {
		struct Item: Codable {
			let text: String
		}
		struct List: Codable {
			let name: String
			let items: [Item]
		}
		struct ListRequest: Codable {
			
		}
		
		
		
	}
	
    static var allTests = [
        ("testExample", testExample),
    ]
}
