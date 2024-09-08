@testable import AppsEngine
import XCTVapor

final class PathComponentsTests: XCTestCase {
	struct Case {
		let path: String
		let separator: String
		let expect: String

		init(_ path: String, _ separator: String, expect: String? = nil) {
			self.path = path
			self.separator = separator
			self.expect = expect ?? path
		}
	}

	func testRoot() {
		let cases: [Case] = [
			.init("/foo/bar", "/"),
			.init("/foo/bar/", "/", expect: "/foo/bar"),
			.init("C:\\foo", "\\"),
		]
		for it in cases {
			let path = PathComponents(separator: it.separator, it.path)
			XCTAssertEqual(it.expect, path.joined())
		}
	}

	func testRelative() {
		let paths = PathComponents.url()
		XCTAssertEqual("foo/bar", paths.appending("foo", "bar").joined())
		XCTAssertEqual("foo.bar", paths.appending("foo", "bar").joined(withOtherSeparator: "."))
		XCTAssertEqual("foo", paths.appending("foo", nil).joined())
		XCTAssertEqual("bar", paths.appending(nil, "bar").joined())
		XCTAssertEqual("", paths.appending(nil, nil).joined())
		XCTAssertEqual("foo/bar", paths.appending("foo", nil, "bar").joined())
		XCTAssertEqual("foo/bar", paths.appending("foo", "", "bar").joined())
		let foo_bar = ["foo", "bar"]
		var pathFooBar = paths
		pathFooBar += foo_bar
		XCTAssertEqual("foo/bar", pathFooBar.joined())
		XCTAssertEqual("foo/bar", (paths + foo_bar).joined())
		XCTAssertTrue(pathFooBar == foo_bar)
		var pathAppending = PathComponents.url("foo")
		pathAppending[0] = "f"
		pathAppending[2] = "o"
		XCTAssertEqual("f/o", pathAppending.joined())
		pathAppending += "o"
		XCTAssertEqual("f/o/o", pathAppending.joined())
		do {
			var path = PathComponents.url("f")
			path.insert("d", at: -1)
			XCTAssertEqual("d/f", path.joined())
			path.insert("d", at: 10)
			XCTAssertEqual("d/f/d", path.joined())
			path.insert("o", at: 0)
			XCTAssertEqual("o/d/f/d", path.joined())
			path.insert("d", at: 1)
			XCTAssertEqual("o/d/d/f/d", path.joined())
		}
		XCTAssertEqual("foo", paths.appending("foo/bar").components[0])
		XCTAssertEqual("\\foo\\bar", PathComponents(separator: "/", "/foo/bar").joined(withOtherSeparator: "\\"))
	}
	
	func testLastComponent() {
		let path = "z/f/b/a.txt"
		let sep = "/"
		// not found
		XCTAssertEqual(path[...], PathComponents.lastComponent(path: path, separator: "?"))
		// last one
		XCTAssertEqual("txt", PathComponents.lastComponent(path: path, separator: "."))
		XCTAssertEqual("a.txt", PathComponents.lastComponent(path: path, separator: sep))
		// last 2 comps
		XCTAssertEqual("b/a.txt", PathComponents.lastComponent(path: path, separator: sep, step: 2))
		XCTAssertEqual("z/f/b/a.txt", PathComponents.lastComponent(path: path, separator: sep, step: 4))
		XCTAssertEqual("z/f/b/a.txt", PathComponents.lastComponent(path: path, separator: sep, step: 6))
	}

	func testSubrange() {
		let path = PathComponents(separator: "/", "a/b/c/d")
		XCTAssertEqual("b/c/d", path[1...5].joined())
		XCTAssertEqual("b/c", path[1...2].joined())
		XCTAssertEqual("a/b/c", path[...2].joined())
		XCTAssertEqual("c/d", path[2...].joined())
		XCTAssertEqual("a/b/c/d", path[(-1)...].joined())
		XCTAssertEqual("a/b/c/d", path[...(-1)].joined())
		XCTAssertEqual("a/b/c/d", path[...].joined())
		XCTAssertEqual("a", path[0..<0].joined())
		XCTAssertEqual("", path[10...].joined())
		XCTAssertEqual("d", path[3...].joined())
	}
}
