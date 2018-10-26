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

let uri1 = "/v1/user/share/json"
let uri2 = "/v1/user/*/json"
let uri3 = "/v1/user/info/d/json"

let regexp = try regExp(for: uri2)

if let match = regexp.firstMatch(in: uri1, range: NSRange(location: 0, length: uri1.count)) {
	if match.numberOfRanges == 2 {
		let components = match.range(at: 1)
		print(components)
	}
}


