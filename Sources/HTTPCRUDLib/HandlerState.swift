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
		 headers h: HTTPHeaders = HTTPHeaders(),
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
	let uri: [Character]
	var genRange: Array<Character>.Index
	init(request: HTTPRequest, uri: String) {
		self.request = request
		self.uri = Array(uri)
		genRange = self.uri.startIndex
		advanceComponent()
	}
	func advanceComponent() {
		while genRange < uri.endIndex && uri[genRange] == "/" {
			genRange = uri.index(after: genRange)
		}
		guard genRange < uri.endIndex else {
			currentComponent = nil
			return
		}
		let sRange = genRange
		while genRange < uri.endIndex && uri[genRange] != "/" {
			genRange = uri.index(after: genRange)
		}
		currentComponent = String(uri[sRange..<genRange])
	}
}
