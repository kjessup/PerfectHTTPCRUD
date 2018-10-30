//
//  NIOHTTPHandler.swift
//  HTTPCRUDLib
//
//  Created by Kyle Jessup on 2018-10-30.
//

import NIO
import NIOHTTP1

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
	var contentType: String? = nil
	var contentLength = 0
	var contentRead = 0
	var contentConsumed = 0
	
	let finder: RouteFinder
	var head: HTTPRequestHead?
	var channel: Channel?
	var pendingBytes: [ByteBuffer] = []
	var pendingPromise: EventLoopPromise<[ByteBuffer]>?
	var readState = State.none
	var writeState = State.none
	
	init(finder: RouteFinder) {
		self.finder = finder
	}
	func readSomeContent() -> EventLoopFuture<[ByteBuffer]> {
		assert(nil != self.channel)
		let channel = self.channel!
		let promise: EventLoopPromise<[ByteBuffer]> = channel.eventLoop.newPromise()
		readSomeContent(promise)
		return promise.futureResult
	}
	func readSomeContent(_ promise: EventLoopPromise<[ByteBuffer]>) {
		guard contentConsumed < contentLength else {
			return promise.succeed(result: [])
		}
		if !pendingBytes.isEmpty {
			let cpy = pendingBytes
			pendingBytes = []
			let sum = cpy.reduce(0) { $0 + $1.readableBytes }
			contentConsumed += sum
			return promise.succeed(result: cpy)
		}
		pendingPromise = promise
		channel?.read()
	}
	
	func readContent() -> EventLoopFuture<HTTPRequestContentType> {
		if contentLength == 0 || contentConsumed == contentLength {
			return channel!.eventLoop.newSucceededFuture(result: .none)
		}
		let ret: EventLoopFuture<HTTPRequestContentType>
		let ct = contentType ?? "application/octet-stream"
		if ct.hasPrefix("multipart/form-data") {
			//application/x-www-form-urlencoded or multipart/form-data
			let p: EventLoopPromise<HTTPRequestContentType> = channel!.eventLoop.newPromise()
			readContent(multi: MimeReader(ct), p)
			ret = p.futureResult
		} else {
			let p: EventLoopPromise<[UInt8]> = channel!.eventLoop.newPromise()
			readContent(p)
			if ct.hasPrefix("application/x-www-form-urlencoded") {
				ret = p.futureResult.map {
					.urlForm((String(validatingUTF8: $0) ?? "").decodedQuery)
				}
			} else {
				ret = p.futureResult.map { .other($0) }
			}
		}
		return ret
	}
	
	func readContent(multi: MimeReader, _ promise: EventLoopPromise<HTTPRequestContentType>) {
		if contentConsumed == contentLength {
			return promise.succeed(result: .multiPartForm(multi))
		}
		readSomeContent().whenSuccess {
			buffers in
			buffers.forEach {
				multi.addToBuffer(bytes: $0.getBytes(at: 0, length: $0.readableBytes) ?? [])
			}
			self.readContent(multi: multi, promise)
		}
	}
	
	func readContent(_ promise: EventLoopPromise<[UInt8]>) {
		readContent(accum: [], promise)
	}
	
	func readContent(accum: [UInt8], _ promise: EventLoopPromise<[UInt8]>) {
		readSomeContent().whenSuccess {
			buffers in
			var a = accum
			buffers.forEach {
				a.append(contentsOf: $0.getBytes(at: 0, length: $0.readableBytes) ?? [])
			}
			if self.contentConsumed == self.contentLength {
				promise.succeed(result: a)
			} else {
				self.readContent(accum: a, promise)
			}
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
		contentType = head.headers["content-type"].first
		contentLength = Int(head.headers["content-length"].first ?? "0") ?? 0
		contentRead = 0
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
		let readable = body.readableBytes
		if contentRead + readable > contentLength {
			let diff = contentLength - contentRead
			if diff > 0, let s = body.getSlice(at: 0, length: diff) {
				pendingBytes.append(s)
			}
			contentRead = contentLength
		} else {
			contentRead += readable
			pendingBytes.append(body)
		}
		if let p = pendingPromise {
			pendingPromise = nil
			readSomeContent(p)
		}
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