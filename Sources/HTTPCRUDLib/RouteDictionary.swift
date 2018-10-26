//
//  RouteDictionary.swift
//  HTTPCRUDLib
//
//  Created by Kyle Jessup on 2018-10-23.
//

import PerfectHTTP
import Foundation

protocol RouteFinder {
	typealias ResolveFunc = (HandlerState, HTTPRequest) throws -> HTTPOutput
	init(_ registry: RouteRegistry<HTTPRequest, HTTPOutput>) throws
	subscript(uri: String) -> ResolveFunc? { get }
}

class RouteFinderRegExp: RouteFinder {
	typealias Matcher = (NSRegularExpression, ResolveFunc)
	let matchers: [Matcher]
	required init(_ registry: RouteRegistry<HTTPRequest, HTTPOutput>) throws {
		matchers = try registry.routes.map { (try RouteFinderRegExp.regExp(for: $0.path), $0.resolve) }
	}
	subscript(uri: String) -> ResolveFunc? {
		let uriRange = NSRange(location: 0, length: uri.count)
		for matcher in matchers {
			guard let match = matcher.0.firstMatch(in: uri, range: uriRange) else {
				continue
			}
			// ranges/wildcards
			return matcher.1
		}
		return nil
	}
	static func regExp(for path: String) throws -> NSRegularExpression {
		let c = path.components
		let strs = c.map {
			comp -> String in
			switch comp {
			case "*":
				return "/([^/]*)"
			case "**":
				return "/(.*)"
			default:
				return "/\(comp)"
			}
		}
		return try NSRegularExpression(pattern: "^" + strs.joined(separator: "") + "$", options: NSRegularExpression.Options.caseInsensitive)
	}
}
