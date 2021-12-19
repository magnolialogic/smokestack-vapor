/*
 *  StateTests.swift
 *  https://github.com/magnolialogic/smokestack-vapor
 *
 *  © 2021-Present @magnolialogic
*/

@testable import Smokestack
import XCTVapor
import Redis
import CoreSmokestack

final class StateTests: XCTestCase {
	let route = "api/state"
	
	func test1_Get_404() throws {
		let app = Application(.testing)
		defer { app.shutdown() }
		try configure(app)
		
		let secretKey = try app.redis.get(XCTVAPOR_KEY).wait()
		var headers = HTTPHeaders()
		headers.basicAuthorization = BasicAuthorization(username: XCTVAPOR_USERNAME, password: secretKey.description)
		
		try app.test(.GET, route, headers: headers, afterResponse: { response in
			XCTAssertNil(try app.redis.get("state", asJSON: SmokeState.self).wait())
			XCTAssertEqual(response.status, .notFound)
		})
	}
	
	func test2_Put() throws {
		let app = Application(.testing)
		defer { app.shutdown() }
		try configure(app)
		
		let secretKey = try app.redis.get(XCTVAPOR_KEY).wait()
		var headers = HTTPHeaders()
		headers.basicAuthorization = BasicAuthorization(username: XCTVAPOR_USERNAME, password: secretKey.description)
		headers.contentType = .json
		let putBody = ByteBuffer(data: try JSONEncoder().encode(SmokeState.shared))
		try app.test(.PUT, route, headers: headers, body: putBody, afterResponse: { response in
			XCTAssertEqual(response.status, .accepted)
			XCTAssertNotNil(try app.redis.get("state", asJSON: SmokeState.self).wait())
			_ = try app.redis.delete("state:pending").wait()
		})
	}
	
	func test3_Patch() throws {
		let app = Application(.testing)
		defer { app.shutdown() }
		try configure(app)
		
		let secretKey = try app.redis.get(XCTVAPOR_KEY).wait()
		var headers = HTTPHeaders()
		headers.basicAuthorization = BasicAuthorization(username: XCTVAPOR_USERNAME, password: secretKey.description)
		headers.contentType = .json
		let patchBody = ByteBuffer(data: "{\"mode\":\"Start\"}".data(using: .utf8)!)
		
		try app.test(.PATCH, route, headers: headers, body: patchBody, beforeRequest: { _ in
			SmokeState.shared.mode = .idle
			XCTAssertNoThrow(try app.redis.set("state", toJSON: SmokeState.shared).wait())
		}, afterResponse: { response in
			XCTAssertEqual(response.status, .ok)
			let patchedState = try app.redis.get("state", asJSON: SmokeState.self).wait()
			XCTAssertEqual(patchedState!.mode, .start)
			_ = try app.redis.delete("state:pending").wait()
		})
	}
}
