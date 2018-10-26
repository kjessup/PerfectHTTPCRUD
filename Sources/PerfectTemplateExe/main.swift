import HTTPCRUDLib

let big1024 = String(repeating: "A", count: 1024)
let big2048 = String(repeating: "A", count: 2048)
let big4096 = String(repeating: "A", count: 4096)
let big8192 = String(repeating: "A", count: 8192)

let routes = root().append([
	root().empty { "" }.text(),
	root().path("1024") { big1024 }.text(),
	root().path("2048") { big2048 }.text(),
	root().path("4096") { big4096 }.text(),
	root().path("8192") { big8192 }.text(),
])

let server = try routes.bind(port: 9000).listen()
try server.wait()
