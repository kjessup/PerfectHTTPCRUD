import PerfectHTTP
import Foundation

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
		if hasSuffix("/") {
			return self + name
		}
		return self + "/" + name.split(separator: "/").joined(separator: "/")
	}
	var cleanedPath: String {
		return "/" + components.joined(separator: "/")
	}
	var componentBase: String? {
		return self.components.first
	}
	var componentName: String? {
		return self.components.last
	}
	var ext: String {
		if self.first != "." {
			return "." + self
		}
		return self
	}
	var splitQuery: (String, String?) {
		let splt = split(separator: "?").map(String.init)
		return (splt.first ?? "/", splt.count > 1 ? splt[1] : nil)
	}
	var decodedQuery: [(String, String)] {
		return split(separator: "&").map {
			let s = $0.split(separator: "=").map(String.init)
			return ((s.first ?? "").stringByDecodingURL ?? "",  (s.count > 1 ? s[1] : "").stringByDecodingURL ?? "")
		}
	}
	var splitUri: (String, [(String, String)]) {
		let s1 = splitQuery
		return (s1.0, s1.1?.decodedQuery ?? [])
	}
}

public enum TerminationType: Error {
	case error(HTTPOutputError)
	case criteriaFailed
	case internalError
}
