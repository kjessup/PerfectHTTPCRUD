//
//  RouteServer.swift
//  HTTPCRUDLib
//
//  Created by Kyle Jessup on 2018-10-24.
//

import NIO
import NIOHTTP1
import Dispatch
import Foundation

public protocol HTTPRequest {
	var method: HTTPMethod { get }
	var uri: String { get }
	var headers: HTTPHeaders { get }
	var uriVariables: [String:String] { get set }
	var path: String { get }
	var searchArgs: [(String, String)] { get }
	var contentLength: Int { get }
	var contentRead: Int { get }
	func readBody(_ call: @escaping (ByteBuffer?) -> ())
}

public protocol HTTPOutput {
	var status: HTTPResponseStatus? { get }
	var headers: HTTPHeaders? { get }
	var body: [UInt8]? { get }
}

public struct HTTPOutputError: HTTPOutput, Error {
	public let status: HTTPResponseStatus?
	public let headers: HTTPHeaders?
	public let body: [UInt8]?
	public init(status: HTTPResponseStatus,
		headers: HTTPHeaders? = nil,
		body: [UInt8]? = nil) {
		self.status = status
		self.headers = headers
		self.body = body
	}
	public init(status: HTTPResponseStatus, description: String) {
		let chars = Array(description.utf8)
		self.status = status
		headers = HTTPHeaders([("content-type", "text/plain"), ("content-length", "\(chars.count)")])
		body = chars
	}
}

public protocol ListeningRoutes {
	func stop()
	func wait() throws
}

public protocol BoundRoutes {
	var port: Int { get }
	var address: String { get }
	func listen() throws -> ListeningRoutes
}

struct JSONOutput<E: Encodable>: HTTPOutput {
	var status: HTTPResponseStatus? { return nil }
	var headers: HTTPHeaders? = HTTPHeaders([("content-type", "application/json")])
	let body: [UInt8]?
	init(_ encodable: E) throws {
		body = Array(try JSONEncoder().encode(encodable))
	}
}

struct TextOutput<C: CustomStringConvertible>: HTTPOutput {
	var status: HTTPResponseStatus? { return nil }
	var headers: HTTPHeaders? = HTTPHeaders([("content-type", "text/plain")])
	let body: [UInt8]?
	init(_ c: C) {
		body = Array("\(c)".utf8)
	}
}

final class NIOHTTPHandler: ChannelInboundHandler, HTTPRequest {
	public typealias InboundIn = HTTPServerRequestPart
	public typealias OutboundOut = HTTPServerResponsePart
	enum State {
		case none, head, body, end
	}
	
	var method: HTTPMethod { return head?.method ?? .GET }
	var uri: String { return head?.uri ?? "" }
	var headers: HTTPHeaders { return head?.headers ?? .init() }
	var uriVariables: [String:String] = [:]
	var path: String = ""
	var searchArgs: [(String, String)] = []
	var contentLength = 0
	var contentRead = 0
	
	let finder: RouteFinder
	var head: HTTPRequestHead?
	var channel: Channel?
	var pendingBytes = CircularBuffer<ByteBuffer>()
	var readState = State.none
	var writeState = State.none
	
	init(finder: RouteFinder) {
		self.finder = finder
	}
	func readBody(_ call: @escaping (ByteBuffer?) -> ()) {
		if pendingBytes.count > 0 {
			call(pendingBytes.remove(at: 0))
		} else {
			// fix
			call(nil)
		}
	}
	func channelActive(ctx: ChannelHandlerContext) {
		channel = ctx.channel
	}
	func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
		let reqPart = self.unwrapInboundIn(data)
		switch reqPart {
		case .head(let head):
			http(head: head, ctx: ctx)
		case .body(let body):
			http(body: body, ctx: ctx)
		case .end(let headers):
			http(end: headers, ctx: ctx)
		}
	}
	func http(head: HTTPRequestHead, ctx: ChannelHandlerContext) {
		readState = .head
		self.head = head
		let (path, args) = head.uri.splitUri
		self.path = path
		searchArgs = args
		let output: HTTPOutput
		if let fnc = finder[head.method, path] {
			let state = HandlerState(request: self, uri: path)
			output = runHandler(state: state, fnc)
		} else {
			output = HTTPOutputError(status: .notFound, description: "No route for URI.")
		}
		flush(output: output)
	}
	func runHandler(state: HandlerState, _ fnc: (HandlerState, HTTPRequest) throws -> HTTPOutput) -> HTTPOutput {
		do {
			return try fnc(state, self)
		} catch let error as TerminationType {
			switch error {
			case .error(let e):
				return e
			case .criteriaFailed:
				return state.response
			case .internalError:
				return HTTPOutputError(status: .internalServerError)
			}
		} catch {
			return HTTPOutputError(status: .internalServerError, description: "Error caught: \(error)")
		}
	}
	func http(body: ByteBuffer, ctx: ChannelHandlerContext) {
		readState = .body
		pendingBytes.append(body)
	}
	func http(end: HTTPHeaders?, ctx: ChannelHandlerContext) {
		readState = .end
		
	}
	
	func writeHead(output: HTTPOutput) {
		let headers = output.headers ?? HTTPHeaders()
		let h = HTTPResponseHead(version: head?.version ?? .init(major: 1, minor: 1),
								 status: output.status ?? .ok,
								 headers: headers)
		channel?.write(wrapOutboundOut(.head(h)), promise: nil)
	}
	func write(output: HTTPOutput) {
		switch writeState {
		case .none:
			writeState = .head
			writeHead(output: output)
			fallthrough
		case .head, .body:
			if let b = output.body, let channel = self.channel {
				writeState = .body
				var buffer = channel.allocator.buffer(capacity: b.count)
				buffer.write(bytes: b)
				channel.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
			}
		case .end:
			()
		}
	}
	func flush(output: HTTPOutput? = nil) {
		if let o = output {
			if case .none = writeState {
				var headers = o.headers ?? HTTPHeaders()
				headers.replaceOrAdd(name: "content-length", value: "\(o.body?.count ?? 0)")
				let newO = DefaultHTTPOutput(status: o.status, headers: headers, body: o.body)
				write(output: newO)
			} else {
				write(output: o)
			}
		}
		if let channel = self.channel {
			let p: EventLoopPromise<Void> = channel.eventLoop.newPromise()
			let keepAlive = head?.isKeepAlive ?? false
			p.futureResult.whenComplete {
				if !keepAlive {
					channel.close(promise: nil)
				}
			}
			reset()
			channel.writeAndFlush(wrapOutboundOut(.end(nil)), promise: p)
		}
	}
	
	func reset() {
		writeState = .none
		readState = .none
		head = nil
	}
	
//	func userInboundEventTriggered(ctx: ChannelHandlerContext, event: Any) {
//		if event is IdleStateHandler.IdleStateEvent {
//			_ = ctx.close()
//		} else {
//			ctx.fireUserInboundEventTriggered(event)
//		}
//	}
}

func configureHTTPServerPipeline(pipeline: ChannelPipeline,
								 first: Bool = false,
								 withPipeliningAssistance pipelining: Bool = true,
								 withServerUpgrade upgrade: HTTPUpgradeConfiguration? = nil,
								 withErrorHandling errorHandling: Bool = false) -> EventLoopFuture<Void> {
	let responseEncoder = HTTPResponseEncoder()
	let requestDecoder = HTTPRequestDecoder(leftOverBytesStrategy: upgrade == nil ? .dropBytes : .forwardBytes)
	
	var handlers: [ChannelHandler] = [responseEncoder, requestDecoder]
	
	if pipelining {
		handlers.append(HTTPServerPipelineHandler())
	}
	
//	if errorHandling {
//		handlers.append(HTTPServerProtocolErrorHandler())
//	}
	
//	if let (upgraders, completionHandler) = upgrade {
//		let upgrader = HTTPServerUpgradeHandler(upgraders: upgraders,
//												httpEncoder: responseEncoder,
//												extraHTTPHandlers: Array(handlers.dropFirst()),
//												upgradeCompletionHandler: completionHandler)
//		handlers.append(upgrader)
//	}
	
	return pipeline.addHandlers(handlers, first: first)
}

class NIOBoundRoutes: BoundRoutes {
	typealias RegistryType = RouteRegistry<HTTPRequest, HTTPOutput>
	private let childGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
	private let channel: Channel
	
	public let port: Int
	public let address: String
	init(registry: RegistryType, port: Int, address: String) throws {
		let finder = try RouteFinderDual(registry)
		self.port = port
		self.address = address
		channel = try ServerBootstrap(group: childGroup)
			.serverChannelOption(ChannelOptions.backlog, value: 256)
			.serverChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
			.serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEPORT), value: 1)
			.serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
			.childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
			.childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
			.childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
			.childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: true)
			.childChannelInitializer {
				channel in
				configureHTTPServerPipeline(pipeline: channel.pipeline)
				.then {
					channel.pipeline.add(handler: NIOHTTPHandler(finder: finder))
				}
			}.bind(host: address, port: port).wait()
	}
	public func listen() throws -> ListeningRoutes {
		return NIOListeningRoutes(channel: channel)
	}
}

class NIOListeningRoutes: ListeningRoutes {
	private let channel: Channel
	private let f: EventLoopFuture<Void>
	init(channel: Channel) {
		self.channel = channel
		f = channel.closeFuture
	}
	public func stop() {
		channel.close(promise: nil)
	}
	public func wait() throws {
		try f.wait()
	}
}

public extension RouteRegistry where InType == HTTPRequest, OutType == HTTPOutput {
	func bind(port: Int, address: String = "0.0.0.0") throws -> BoundRoutes {
		return try NIOBoundRoutes(registry: self, port: port, address: address)
	}
}

extension HTTPMethod {
	static var allCases: [HTTPMethod] {
		return [
		.GET,.PUT,.ACL,.HEAD,.POST,.COPY,.LOCK,.MOVE,.BIND,.LINK,.PATCH,
		.TRACE,.MKCOL,.MERGE,.PURGE,.NOTIFY,.SEARCH,.UNLOCK,.REBIND,.UNBIND,
		.REPORT,.DELETE,.UNLINK,.CONNECT,.MSEARCH,.OPTIONS,.PROPFIND,.CHECKOUT,
		.PROPPATCH,.SUBSCRIBE,.MKCALENDAR,.MKACTIVITY,.UNSUBSCRIBE
		]
	}
	var name: String {
		switch self {
		case .GET:
			return "GET"
		case .PUT:
			return "PUT"
		case .ACL:
			return "ACL"
		case .HEAD:
			return "HEAD"
		case .POST:
			return "POST"
		case .COPY:
			return "COPY"
		case .LOCK:
			return "LOCK"
		case .MOVE:
			return "MOVE"
		case .BIND:
			return "BIND"
		case .LINK:
			return "LINK"
		case .PATCH:
			return "PATCH"
		case .TRACE:
			return "TRACE"
		case .MKCOL:
			return "MKCOL"
		case .MERGE:
			return "MERGE"
		case .PURGE:
			return "PURGE"
		case .NOTIFY:
			return "NOTIFY"
		case .SEARCH:
			return "SEARCH"
		case .UNLOCK:
			return "UNLOCK"
		case .REBIND:
			return "REBIND"
		case .UNBIND:
			return "UNBIND"
		case .REPORT:
			return "REPORT"
		case .DELETE:
			return "DELETE"
		case .UNLINK:
			return "UNLINK"
		case .CONNECT:
			return "CONNECT"
		case .MSEARCH:
			return "MSEARCH"
		case .OPTIONS:
			return "OPTIONS"
		case .PROPFIND:
			return "PROPFIND"
		case .CHECKOUT:
			return "CHECKOUT"
		case .PROPPATCH:
			return "PROPPATCH"
		case .SUBSCRIBE:
			return "SUBSCRIBE"
		case .MKCALENDAR:
			return "MKCALENDAR"
		case .MKACTIVITY:
			return "MKACTIVITY"
		case .UNSUBSCRIBE:
			return "UNSUBSCRIBE"
		case .RAW(let value):
			return value
		}
	}
}

extension HTTPMethod: Hashable {
	public var hashValue: Int { return name.hashValue }
}

extension String {
	var method: HTTPMethod {
		switch self {
		case "GET":
			return .GET
		case "PUT":
			return .PUT
		case "ACL":
			return .ACL
		case "HEAD":
			return .HEAD
		case "POST":
			return .POST
		case "COPY":
			return .COPY
		case "LOCK":
			return .LOCK
		case "MOVE":
			return .MOVE
		case "BIND":
			return .BIND
		case "LINK":
			return .LINK
		case "PATCH":
			return .PATCH
		case "TRACE":
			return .TRACE
		case "MKCOL":
			return .MKCOL
		case "MERGE":
			return .MERGE
		case "PURGE":
			return .PURGE
		case "NOTIFY":
			return .NOTIFY
		case "SEARCH":
			return .SEARCH
		case "UNLOCK":
			return .UNLOCK
		case "REBIND":
			return .REBIND
		case "UNBIND":
			return .UNBIND
		case "REPORT":
			return .REPORT
		case "DELETE":
			return .DELETE
		case "UNLINK":
			return .UNLINK
		case "CONNECT":
			return .CONNECT
		case "MSEARCH":
			return .MSEARCH
		case "OPTIONS":
			return .OPTIONS
		case "PROPFIND":
			return .PROPFIND
		case "CHECKOUT":
			return .CHECKOUT
		case "PROPPATCH":
			return .PROPPATCH
		case "SUBSCRIBE":
			return .SUBSCRIBE
		case "MKCALENDAR":
			return .MKCALENDAR
		case "MKACTIVITY":
			return .MKACTIVITY
		case "UNSUBSCRIBE":
			return .UNSUBSCRIBE
		default:
			return .RAW(value: self)
		}
	}
	var splitMethod: (HTTPMethod?, String) {
		if let i = range(of: "://") {
			return (String(self[i]).method, String(self[i.upperBound...]))
		}
		return (nil, self)
	}
}

public extension RouteRegistry {
	func method(_ method: HTTPMethod, _ methods: HTTPMethod...) -> RouteRegistry {
		let methods = [method] + methods
		return .init(
			routes.flatMap {
				route in
				methods.map {
					.init(path: $0.name + "://" + route.path.splitMethod.1,
						  resolve: route.resolve) } }
		)
	}
}
