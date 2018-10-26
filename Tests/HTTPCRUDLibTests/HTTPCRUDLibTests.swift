import XCTest
import PerfectHTTP
import PerfectNet
@testable import HTTPCRUDLib

class ShimHTTPRequest: HTTPRequest {
	var method = HTTPMethod.get
	var path = "/"
	var pathComponents: [String] { return [""] }
	var queryParams = [(String, String)]()
	var protocolVersion = (1, 1)
	var remoteAddress = (host: "127.0.0.1", port: 8000 as UInt16)
	var serverAddress = (host: "127.0.0.1", port: 8282 as UInt16)
	var serverName = "my_server"
	var documentRoot = "./webroot"
	var connection = NetTCP()
	var urlVariables = [String:String]()
	var scratchPad = [String:Any]()
	func header(_ named: HTTPRequestHeader.Name) -> String? { return nil }
	func addHeader(_ named: HTTPRequestHeader.Name, value: String) {}
	func setHeader(_ named: HTTPRequestHeader.Name, value: String) {}
	var headers = AnyIterator<(HTTPRequestHeader.Name, String)> { return nil }
	var postParams = [(String, String)]()
	var postBodyBytes: [UInt8]? = nil
	var postBodyString: String? = nil
	var postFileUploads: [MimeReader.BodySpec]? = nil
}

class ShimHTTPResponse: HTTPResponse {
	var request: HTTPRequest = ShimHTTPRequest()
	var status: HTTPResponseStatus = .ok
	var isStreaming = false
	var bodyBytes = [UInt8]()
	var bodyString: String {
		return String(data: Data(bytes: bodyBytes), encoding: .utf8)!
	}
	var headerStore = Array<(HTTPResponseHeader.Name, String)>()
	func header(_ named: HTTPResponseHeader.Name) -> String? {
		for (n, v) in headerStore where n == named {
			return v
		}
		return nil
	}
	@discardableResult
	func addHeader(_ name: HTTPResponseHeader.Name, value: String) -> Self {
		headerStore.append((name, value))
		return self
	}
	@discardableResult
	func setHeader(_ name: HTTPResponseHeader.Name, value: String) -> Self {
		var fi = [Int]()
		for i in 0..<headerStore.count {
			let (n, _) = headerStore[i]
			if n == name {
				fi.append(i)
			}
		}
		fi = fi.reversed()
		for i in fi {
			headerStore.remove(at: i)
		}
		return addHeader(name, value: value)
	}
	var headers: AnyIterator<(HTTPResponseHeader.Name, String)> {
		var g = self.headerStore.makeIterator()
		return AnyIterator<(HTTPResponseHeader.Name, String)> {
			g.next()
		}
	}
	func addCookie(_: PerfectHTTP.HTTPCookie) -> Self { return self }
	func appendBody(bytes: [UInt8]) {}
	func appendBody(string: String) {}
	func setBody(json: [String:Any]) throws {}
	func push(callback: @escaping (Bool) -> ()) {}
	func completed() {}
	func next() {
		if let f = handlers?.removeFirst() {
			f(request, self)
		}
	}
	
	// shim shim
	var handlers: [RequestHandler]?
}

final class HTTPCRUDLibTests: XCTestCase {
    func testScratch() {
		
		func p<O>(_ msg: String, _ o: O) -> O {
			print(msg)
			return o
		}
		
		let rt = root().foo { p("foo/", $0) }
		let rt2 = root {p("root/", $0)}.foo.bar { p("bar", $0) }.baz { p("baz", $0) }
		let rt3 = rt.combine(rt2)
		
		print(rt3)
		print(rt3.routes)
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
			.append([
				user.info { UserResponse(id: $0.1.id, msg: "i") },
				user.wild { p($0, "wild: \($1)") }.info { UserResponse(id: $0.1.id, msg: "i") },
				user.info.d { UserResponse(id: $0.1.id, msg: "id") },
				user.share { UserResponse(id: $0.1.id, msg: "s") },
				device.foo { DeviceResponse(id: $0.1.id, msg: "d") }
			])
		let fullJson = fullRoutes.path("json").json()
		let fullText = fullRoutes.path("text").then { "\($0)" }.text()
		let end = fullText.combine(fullJson)
		
		let response = ShimHTTPResponse()
		let request = response.request as! ShimHTTPRequest
		request.queryParams = [("id", UUID().uuidString)]
		
		let uri1 = "/v1/user/share/json"
		let uri2 = "/v1/user/FOOBAR/info/json"
		let uri3 = "/v1/user/info/d/json"
		
		let finder = try! RouteFinderRegExp(end)
		
		if let fnd = finder[uri2] {
			let state = HandlerState(request: request, response: response, uri: uri2)
			let output = try! fnd(state, request)
			try! output.apply(response: response)
			print(response.bodyString)
		}
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
