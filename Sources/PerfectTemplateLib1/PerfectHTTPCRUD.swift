
import Foundation
import PerfectHTTP

/*

	Request handling is expressed as a function taking an HTTPRequest and returning a NodeHTTPOutput.
	This function is created by chaining other functions together, each taking and returning other value types.
	These are referred to as Nodes.
	Each intermediate node between HTTPRequest -> NodeHTTPOutput is given a path component.
	Trailing slash components (of which there may be many) are considered extensions of the preceeding component. *(explain this)
	When the output of a node is NodeHTTPOutput it is considered "terminal".
	Terminal nodes can be directly referenced by a request.

	As a series of nodes are strung together to build a full path, they build an index.
	This index tracks terminal nodes and is used to perform the actual lookups to locate
	the intended path -> HTTPRequest -> NodeHTTPOutput function which will execute the request.
	The index is transformed and optimized before the server starts.
	At request-handling time, all shared structures are immutable and thread-safe.

	Multiple sibling nodes may be composed together and given to a parent node.
	These child nodes must accept whatever the parent returns and they all must return the same type.
	The result of this composition is a node which accepts what the parent returns and returns what all of the nodes return.
	These composition nodes are responsible for selecting which child that will be executed based on the currently executing path component.

	For example you could have paths:
		/<root>
			|___/foo<terminal>|___/json<terminal>
			|___/bar<terminal>|

	/foo and /bar can be accessed and will return some default content.
	/foo/json and /bar/json can be accessed and will return that content, but JSONized.

	Each node contains a name, and set of paths which led to it. Thus, nodes do not (nessesarily) have a single path "address".
	Nodes must take this into account when recording terminals and when merging child node arrays.

	explain Wildcards, Trailing wildcards, variables (wildcards and variablbes become the same thing? - must account for HTTPRequest.decode utilizing vars for decoding).
*/

public typealias ComponentGenerator = IndexingIterator<[String]>

extension String {
	var components: [String] {
		return self.split(separator: "/").map(String.init)
	}
	var componentGenerator: ComponentGenerator {
		 return self.split(separator: "/").map(String.init).makeIterator()
	}
	// need url decoding component generator
	func appending(component name: String) -> String {
		if self == "/" {
			return "/" + name
		}
		return self + "/" + name
	}
	var cleanedComponents: String {
		return components.joined(separator: "/")
	}
	var componentBase: String? {
		return self.components.first
	}
	var componentName: String? {
		return self.components.last
	}
}

public enum TerminationType: Error {
	case error(Error)
	case criteriaFailed
	case internalError
}

public protocol NodeHTTPOutput {
	func apply(response: HTTPResponse) throws
}

public class HandlerState {
	let request: HTTPRequest
	let response: HTTPResponse
	var gen: ComponentGenerator
	var currentComponent: String?
	init(request: HTTPRequest, response: HTTPResponse, gen: ComponentGenerator) {
		self.request = request
		self.response = response
		self.gen = gen
		self.currentComponent = self.gen.next()
	}
	func advanceComponent() {
		currentComponent = gen.next()
	}
}

struct NodeJSONOutput<E: Encodable>: NodeHTTPOutput {
	let encodable: E
	func apply(response: HTTPResponse) throws {
		response.setHeader(.contentType, value: "application/json")
		response.setBody(string:
			String(data: try JSONEncoder().encode(encodable),
				   encoding: .utf8)!)
	}
}

public protocol NodeItem {
	associatedtype InType
	associatedtype OutType
	var paths: [String] { get }
	var handler: (HandlerState, InType) throws -> OutType { get }
}

class TerminalRegistry<InType>: CustomStringConvertible {
	var terminals: [(String, Node<InType, NodeHTTPOutput>)] = []
	var description: String {
		return terminals.map { $0.0 }.joined(separator: "\n")
	}
	init() {}
	func add(node: Node<InType, NodeHTTPOutput>) {
		if node.paths.isEmpty {
			terminals.append(("", node))
		} else {
			terminals.append(contentsOf: node.paths.map { ($0, node) })
		}
	}
}

@dynamicMemberLookup
public struct Node<InType, OutType>: NodeItem {
	public let paths: [String]
	public let handler: (HandlerState, InType) throws -> OutType
	typealias RegistryType = TerminalRegistry<InType>
	let registry: RegistryType
	
	init<SomeOut>(parent: Node<InType, SomeOut>, name: String, pairHandler: @escaping (HandlerState, InType) throws -> OutType) {
		self.init(paths: parent.paths.map { $0.appending(component: name) }, registry: parent.registry, name: name, pairHandler: pairHandler)
	}
	init(paths: [String], registry: RegistryType, name: String, pairHandler: @escaping (HandlerState, InType) throws -> OutType) {
		self.handler = pairHandler
		self.registry = registry
		self.paths = paths.map { $0.appending(component: name) }
	}
	init(name: String, pairHandler: @escaping (HandlerState, InType) throws -> OutType) {
		self.paths = [name]
		self.handler = pairHandler
		self.registry = RegistryType()
	}
}

extension Node where InType == HTTPRequest, OutType == NodeHTTPOutput {
	init<SomeOut>(parent: Node<InType, SomeOut>, name: String, pairHandler: @escaping (HandlerState, InType) throws -> OutType) {
		self.handler = pairHandler
		self.registry = parent.registry
		self.paths = parent.paths.map { $0.appending(component: name) }
		registry.add(node: self)
	}
}

public extension Node {
	subscript(dynamicMember name: String) -> Node<InType, OutType> {
		return path(name)
	}
	subscript<NewOut>(dynamicMember name: String) -> (@escaping (OutType) throws -> NewOut) -> Node<InType, NewOut> {
		return {
			return self.path(name, $0)
		}
	}
}

public func Path<InType, OutType>(_ path: String, _ handler: @escaping (InType) throws -> OutType) -> Node<InType, OutType> {
	return .init(name: path) { try handler($1) }
}

public func Path<InType>(_ path: String) -> Node<InType, InType> {
	return Path(path, identity: InType.self)
}

func Path<InType>(_ path: String, identity: InType.Type) -> Node<InType, InType> {
	return .init(name: path) { $1 }
}

public func Root<OutType>(_ handler: @escaping (HTTPRequest) throws -> OutType) -> Node<HTTPRequest, OutType> {
	return Path("/", handler)
}

public func Root() -> Node<HTTPRequest, HTTPRequest> {
	return Path("/")
}

public extension Node {
	func then<NewOut>(_ handler: @escaping (OutType) throws -> NewOut) -> Node<InType, NewOut> {
		return .init(parent: self, name: "/") {
			reqResp, intype in
			return try handler(self.handler(reqResp, intype))
		}
	}
	func then<NewOut>(_ node: Node<OutType, NewOut>) -> Node<InType, NewOut> {
		return dir(nodes: [node])
	}
	func path<NewOut>(_ name: String, _ handler: @escaping (OutType) throws -> NewOut) -> Node<InType, NewOut> {
		return .init(parent: self, name: name) {
			reqResp, intype in
			return try handler(self.handler(reqResp, intype))
		}
	}
	func path(_ name: String) -> Node<InType, OutType> {
		return path(name) {$0}
	}
	func decode<Type: Decodable, NewOut>(_ type: Type.Type, _ handler: @escaping (OutType, Type) throws -> NewOut) -> Node<InType, NewOut> {
		return .init(parent: self, name: name) {
			reqResp, intype in
			return try handler(try self.handler(reqResp, intype), try reqResp.request.decode(Type.self))
		}
	}
	func statusCheck(_ handler: @escaping (OutType) throws -> HTTPResponseStatus) -> Node<InType, OutType> {
		return .init(parent: self, name: name) {
			reqResp, intype in
			let o = try self.handler(reqResp, intype)
			let status = try handler(o)
			reqResp.response.status = status
			guard status.code >= 200 && status.code < 300 else {
				throw TerminationType.criteriaFailed
			}
			return o
		}
	}
	func dir<NewOut>(_ handler: (Node<OutType, OutType>) -> [Node<OutType, NewOut>]) -> Node<InType, NewOut> {
		return dir(nodes: handler(Path("/")))
	}
	func dir<NewOut>(nodes: [Node<OutType, NewOut>]) -> Node<InType, NewOut> {
		
		typealias Term = (String, Node<InType, NodeHTTPOutput>)
		typealias Child = Node<OutType, NewOut>
		
		let terminals = nodes
			.map { $0.registry.terminals }
		
		print(terminals)
		
		let newTerminals: [Term] = nodes
			.flatMap { $0.registry.terminals }
			.map { ($0.0, self.then($0.1)) }
			.flatMap {
				(tup: Term) -> [Term] in
				let (path, node) = tup
				return self.paths.map {
					($0.appending(component: path), node)
				}
			}
		
		print(nodes)
		
		registry.terminals.append(contentsOf: newTerminals)
		
		// index the path choices
		let prs = nodes.flatMap {
			node in
			return node.pathsForChildren
				.compactMap { $0.componentBase }
				.map {
				($0, node)
			}
		}
		
		var nodeMap = Dictionary(prs, uniquingKeysWith: {$1})
		return .init(paths: prs.map { $0.0 }, registry: registry, name: "/") {
			reqResp, intype in
			let value = try self.handler(reqResp, intype)
			guard let this = reqResp.currentComponent else {
				throw TerminationType.internalError
			}
			guard let node = nodeMap[this] ?? nodeMap["*"] else {
				throw TerminationType.internalError
			}
			reqResp.advanceComponent()
			return try node.handler(reqResp, value)
		}
	}
}

public extension Node where OutType: Encodable {
	func json() -> Node<InType, NodeHTTPOutput> {
		return .init(parent: self, name: "/") {
			reqResp, intype in
			return NodeJSONOutput(encodable: try self.handler(reqResp, intype))
		}
	}
}

extension NodeItem {
	func handle(error: Error, response: HTTPResponse) {
		print("Err \(error)")
		response.completed()
	}
	func handle(error: TerminationType, response: HTTPResponse) {
		print("Term \(error)")
		response.completed()
	}
}

extension NodeItem where InType == HTTPRequest, OutType == NodeHTTPOutput {
	func pureHandler(request: HTTPRequest, response: HTTPResponse) {
		do {
			let state = HandlerState(request: request, response: response, gen: request.path.componentGenerator)
			try self.handler(state, request).apply(response: response)
		} catch let term as TerminationType {
			self.handle(error: term, response: response)
		} catch {
			self.handle(error: error, response: response)
		}
	}
}
