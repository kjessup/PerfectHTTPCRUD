import Foundation

extension String {
	var components: [String] {
		return self.split(separator: "/").map(String.init)
	}
}

func regExp(for path: String) throws -> NSRegularExpression {
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

class ReverseLookup<Payload> {
	class Entry {
		var children: [Entry?]? = nil
		var payload: Payload? = nil
		var rest: [UInt8]? = nil
		func child(_ at: Int) -> Entry? {
			guard let c = children else {
				return nil
			}
			return c[at]
		}
		func add(_ chars: [UInt8], _ index: Array<UInt8>.Index, _ payload: Payload ) {
			if let r = rest, let p = self.payload {
				rest = nil
				self.payload = nil
				children = [Entry?](repeating: nil, count: Int(UInt8.max))
				add(r, r.startIndex, p)
			}
			if index < chars.endIndex {
				if let c = children {
					let e = c[index] ?? Entry()
					e.add(chars, chars.index(after: index), payload)
					children?[index] = e
				} else {
					self.payload = payload
					self.rest = Array(chars[index...])
				}
			} else {
				self.payload = payload
			}
		}
		func find(_ chars: [UInt8], _ index: Array<UInt8>.Index) -> Payload? {
			if index == chars.endIndex {
				return payload
			}
			return children?[index]?.find(chars, chars.index(after: index))
		}
	}
	var root = Entry()
	func add(_ uri: String, _ payload: Payload) {
		add(Array(uri.utf8), payload)
	}
	func add(_ uri: [UInt8], _ payload: Payload) {
		root.add(uri.reversed(), uri.startIndex, payload)
	}
	func find(_ uri: String) -> Payload? {
		return find(Array(uri.utf8))
	}
	func find(_ uri: [UInt8]) -> Payload? {
		return root.find(uri.reversed(), uri.startIndex)
	}
}

let uri1 = "/v1/user/share/json"
let uri2 = "/v1/user/*/json"
let uri3 = "/v1/user/info/d/json"

struct Foo: CustomStringConvertible {
	let description: String
	init(_ d: String) {
		description = d
	}
}
var lookup = ReverseLookup<Foo>()

lookup.add(uri1, Foo("1"))
lookup.add(uri2, Foo("2"))
lookup.add(uri3, Foo("3"))

lookup.find(uri2)

//let regexp = try regExp(for: uri2)
//
//if let match = regexp.firstMatch(in: uri1, range: NSRange(location: 0, length: uri1.count)) {
//	if match.numberOfRanges == 2 {
//		let components = match.range(at: 1)
//		print(components)
//	}
//}


