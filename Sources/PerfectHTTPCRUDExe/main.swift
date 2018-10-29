import HTTPCRUDLib
import PerfectCRUD
import NIO

CRUDLogging.queryLogDestinations = []

let big1024 = String(repeating: "A", count: 1024)
let big2048 = String(repeating: "A", count: 2048)
let big4096 = String(repeating: "A", count: 4096)
let big8192 = String(repeating: "A", count: 8192)

let routes = root().dir{[
	$0.empty { "" },
	$0.path("1024") { big1024 },
	$0.path("2048") { big2048 },
	$0.path("4096") { big4096 },
	$0.path("8192") { big8192 },
//	$0.foo.wild {$1}.bar1 { $0 },
//	$0.foo.wild {$1}.bar2 { $0 },
//	$0.foo.wild {$1}.bar3 { $0 },
//	$0.foo.wild {$1}.bar4 { $0 },
//	$0.foo.wild {$1}.bar5 { $0 },
//	$0.foo.wild {$1}.bar6 { $0 },
]}.text()

let servers = try (0...System.coreCount).map { _ in return try routes.bind(port: 9000).listen() }
print("Server listening on port 9000 with \(System.coreCount) cores")
try servers.map { try $0.wait() }
