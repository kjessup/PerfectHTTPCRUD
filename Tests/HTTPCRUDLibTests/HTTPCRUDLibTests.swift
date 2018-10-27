import XCTest
import NIOHTTP1
@testable import HTTPCRUDLib

class ShimHTTPRequest: HTTPRequest {
	var method = HTTPMethod.GET
	var uri = ""
	var headers = HTTPHeaders()
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
