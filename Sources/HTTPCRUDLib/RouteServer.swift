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
}

public protocol HTTPOutput {
	var status: HTTPResponseStatus? { get }
	var headers: HTTPHeaders? { get }
	var body: [UInt8]? { get }
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
	static let handlerQueue = DispatchQueue(label: "handlers", qos: DispatchQoS.userInitiated, attributes: DispatchQueue.Attributes.concurrent, autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency.inherit, target: nil)
	
	var method: HTTPMethod { return head?.method ?? .GET }
	var uri: String { return head?.uri ?? "" }
	var headers: HTTPHeaders { return head?.headers ?? .init() }
	
	public typealias InboundIn = HTTPServerRequestPart
	public typealias OutboundOut = HTTPServerResponsePart
	let finder: RouteFinder
	var head: HTTPRequestHead?
	var channel: Channel?
	var pendingBytes: [ByteBuffer] = []
	enum State {
		case none, head, body, end
	}
	var readState = State.none
	var writeState = State.none
	
	init(finder: RouteFinder) {
		self.finder = finder
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
		let uri = head.uri
//		NIOHTTPHandler.handlerQueue.async {
			if let fnc = self.finder[uri] {
				let state = HandlerState(request: self, uri: uri)
				do {
					self.flush(output: try fnc(state, self))
				} catch {
					let out = DefaultHTTPOutput()
					out.status = .internalServerError
					out.body = Array("Error caught: \(error)".utf8)
					self.flush(output: out)
				}
			} else {
				let out = DefaultHTTPOutput()
				out.status = .notFound
				out.body = Array("No route for URI.".utf8)
				self.flush(output: out)
			}
//		}
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
			writeState = .none
			readState = .none
			head = nil
			channel.writeAndFlush(wrapOutboundOut(.end(nil)), promise: p)
		}
	}
	
//	func userInboundEventTriggered(ctx: ChannelHandlerContext, event: Any) {
//		if event is IdleStateHandler.IdleStateEvent {
//			_ = ctx.close()
//		} else {
//			ctx.fireUserInboundEventTriggered(event)
//		}
//	}
}

class NIOBoundRoutes: BoundRoutes {
	typealias RegistryType = RouteRegistry<HTTPRequest, HTTPOutput>
	private let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount * 2)
	private let channel: Channel
	
	public let port: Int
	public let address: String
	init(registry: RegistryType, port: Int, address: String) throws {
		let finder = try RouteFinderDual(registry)
		self.port = port
		self.address = address
		let bootstrap = ServerBootstrap(group: group)
			.serverChannelOption(ChannelOptions.backlog, value: 256)
			.serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
			.childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
			.childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
			.childChannelOption(ChannelOptions.maxMessagesPerRead, value: 10)
			.childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: true)
			.childChannelInitializer {
				channel in
				channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true)
				.then {
					channel.pipeline.add(handler: NIOHTTPHandler(finder: finder))
				}
		}
		channel = try bootstrap.bind(host: address, port: port).wait()
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

