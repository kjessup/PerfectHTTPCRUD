//
//  RouteServer.swift
//  HTTPCRUDLib
//
//  Created by Kyle Jessup on 2018-10-24.
//

import NIO
import NIOHTTP1
import Foundation
import PerfectNet

/* TODO
struct requestinfoforlogging {
}
*/
public enum HTTPRequestContentType {
	case none,
		multiPartForm(MimeReader),
		urlForm([(String, String)]),
		other([UInt8])
}

public protocol HTTPRequest {
	var method: HTTPMethod { get }
	var uri: String { get }
	var headers: HTTPHeaders { get }
	var uriVariables: [String:String] { get set }
	var path: String { get }
	var searchArgs: [(String, String)] { get }
	var contentType: String? { get }
	var contentLength: Int { get }
	var contentRead: Int { get }
	var contentConsumed: Int { get }
	func readSomeContent() -> EventLoopFuture<[ByteBuffer]>
	func readContent() -> EventLoopFuture<HTTPRequestContentType>
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
	typealias RegistryType = Routes<HTTPRequest, HTTPOutput>
	private let childGroup: EventLoopGroup
	let acceptGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
	private let channel: Channel
	public let port: Int
	public let address: String
	init(registry: RegistryType,
		 port: Int,
		 address: String,
		 threadGroup: EventLoopGroup) throws {
		childGroup = threadGroup
		let finder = try RouteFinderDual(registry)
		self.port = port
		self.address = address
		
//		let acceptor = NetTCP()
//		acceptor.initSocket(family: AF_INET)
//		acceptor.fd.switchToBlocking()
//		let fd = acceptor.fd.fd
//		
//		var one = Int32(1)
//		setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &one, UInt32(MemoryLayout<Int32>.size))
//		setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, UInt32(MemoryLayout<Int32>.size))
//		try acceptor.bind(port: UInt16(port), address: address)
//		acceptor.fd.fd = -1
		
		channel = try ServerBootstrap(group: acceptGroup, childGroup: childGroup)
			.serverChannelOption(ChannelOptions.backlog, value: 256)
			.serverChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
			.serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEPORT), value: 1)
			.serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
			.childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
			.childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
			.childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
			.childChannelOption(ChannelOptions.autoRead, value: false)
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
	private static var globalInitialized: Bool = {
		var sa = sigaction()
	#if os(Linux)
		sa.__sigaction_handler.sa_handler = SIG_IGN
	#else
		sa.__sigaction_u.__sa_handler = SIG_IGN
	#endif
		sa.sa_flags = 0
		sigaction(SIGPIPE, &sa, nil)
		var rlmt = rlimit()
	#if os(Linux)
		getrlimit(Int32(RLIMIT_NOFILE.rawValue), &rlmt)
		rlmt.rlim_cur = rlmt.rlim_max
		setrlimit(Int32(RLIMIT_NOFILE.rawValue), &rlmt)
	#else
		getrlimit(RLIMIT_NOFILE, &rlmt)
		rlmt.rlim_cur = rlim_t(OPEN_MAX)
		setrlimit(RLIMIT_NOFILE, &rlmt)
	#endif
		return true
	}()
	init(channel: Channel) {
		_ = NIOListeningRoutes.globalInitialized
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

//let serverThreadGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

public extension Routes where InType == HTTPRequest, OutType == HTTPOutput {
	func bind(port: Int, address: String = "0.0.0.0") throws -> BoundRoutes {
		return try NIOBoundRoutes(registry: self, port: port, address: address, threadGroup: MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount))
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
			return (String(self[self.startIndex..<i.lowerBound]).method, String(self[i.upperBound...]))
		}
		return (nil, self)
	}
}

public extension Routes {
	var GET: Routes<InType, OutType> { return method(.GET) }
	var POST: Routes { return method(.POST) }
	var PUT: Routes { return method(.PUT) }
	var DELETE: Routes { return method(.DELETE) }
	var OPTIONS: Routes { return method(.OPTIONS) }
	func method(_ method: HTTPMethod, _ methods: HTTPMethod...) -> Routes {
		let methods = [method] + methods
		return .init(.init(routes:
			registry.routes.flatMap {
				route in
				return methods.map {
					($0.name + "://" + route.0.splitMethod.1, route.1)
				}
			}
		))
	}
}
