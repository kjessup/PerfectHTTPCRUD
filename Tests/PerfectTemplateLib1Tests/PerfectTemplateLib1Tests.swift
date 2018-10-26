import XCTest
import PerfectHTTP
import PerfectNet
@testable import PerfectTemplateLib1

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

struct AuthenticatedRequest {}
struct AResponse: NodeHTTPOutput {
	let string: String
	func apply(response: HTTPResponse) throws {
		response.setBody(string: "Msg from AResponse \(string)")
	}
}
struct BResponse: Codable {
	let string: String
}
struct CResponse: Codable {
	let string: String
}
struct ARequest: Codable {
	let id: String
}

final class PerfectHTTPCRUDTests: XCTestCase {
    func testExample() {
		func p<A>(_ a: A, _ msg: String) -> A {
			print(msg)
			return a
		}
		let s: IndexingIterator<[String]> = "/a/b/c".split(separator: "/").map(String.init).makeIterator()
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
		
		let authenticatedRoute = Root(Authenticator.init)
			.statusCheck { nil == $0 ? .unauthorized : .ok }
			.then { $0! }
		
		let user = authenticatedRoute
			.user
			.decode(UserRequest.self) { (auth: $0, user: $1) }
		let device = authenticatedRoute
			.device
			.decode(DeviceRequest.self) { (auth: $0, user: $1) }
		
		let full = Root{p($0, "Root/")}
			.v1{p($0, "v1/")}
			.dir {
				_ in
				[
					user.dir {
						[
						$0.info { UserResponse(id: $0.1.id, msg: "info") },
						$0.info.d { UserResponse(id: $0.1.id, msg: "info d") },
						$0.share { UserResponse(id: $0.1.id, msg: "share") }
					]},
					device.foo { DeviceResponse(id: $0.1.id, msg: "device foo") }
				]
			}.json()
		print(full.registry.terminals)
		
		let response = ShimHTTPResponse()
		let request = response.request as! ShimHTTPRequest
		request.queryParams = [("id", UUID().uuidString)]
		
		let uri1 = "/v1/user/share"
		let uri2 = "/v1/user/info"
		let uri3 = "/v1/user/info/d"
		if let fnd = full.registry.terminals.first(where: {$0.0 == uri1})?.1 {
			fnd.pureHandler(request: request, response: response)
			print(response.bodyString)
		}
		if let fnd = full.registry.terminals.first(where: {$0.0 == uri2})?.1 {
			fnd.pureHandler(request: request, response: response)
			print(response.bodyString)
		}
		if let fnd = full.registry.terminals.first(where: {$0.0 == uri3})?.1 {
			fnd.pureHandler(request: request, response: response)
			print(response.bodyString)
		}
		
		print(response.status)
	}

    static var allTests = [
        ("testExample", testExample),
    ]
}
