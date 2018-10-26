//
//  HandlerState.swift
//  HTTPCRUDLib
//
//  Created by Kyle Jessup on 2018-10-12.
//

import NIOHTTP1

class DefaultHTTPOutput: HTTPOutput {
	var status: HTTPResponseStatus? = .ok
	var headers: HTTPHeaders? = nil
	var body: [UInt8]? = nil
	init(status s: HTTPResponseStatus? = .ok,
		 headers h: HTTPHeaders? = nil,
		 body b: [UInt8]? = nil) {
		status = s
		headers = h
		body = b
	}
}

class HandlerState {
	let request: HTTPRequest
	var response = DefaultHTTPOutput()
	var currentComponent: String?
	var gen: IndexingIterator<[String]>
	init(request: HTTPRequest, uri: String) {
		self.request = request
		gen = uri.split(separator: "/").map(String.init).makeIterator()
		currentComponent = gen.next()
	}
	func advanceComponent() {
		currentComponent = gen.next()
	}
}
