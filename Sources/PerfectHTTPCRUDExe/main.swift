import HTTPCRUDLib
import PerfectCRUD

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

let server = try routes.bind(port: 9000).listen()
print("Server listening on port 9000")
try server.wait()