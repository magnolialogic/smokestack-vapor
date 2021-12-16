/*
 *  ProgramTests.swift
 *  https://github.com/magnolialogic/smokestack-vapor
 *
 *  © 2021-Present @magnolialogic
*/

@testable import Smokestack
import XCTVapor
import Redis
import CoreSmokestack

final class ProgramTests: XCTestCase {
	let ROUTE = "api/program"
	
	let dummyProgram = SmokeProgram(steps: [ // TODO: add validations for Program.steps: count > 2, count[0] == .start, count[-1] == .keepWarm
		SmokeStep(mode: .start, trigger: .time, limit: 600, targetGrill: 150),
		SmokeStep(mode: .hold, trigger: .time, limit: 3600, targetGrill: 225),
		SmokeStep(mode: .smoke, trigger: .time, limit: 43200, targetGrill: 150),
		SmokeStep(mode: .shutdown, trigger: .time, limit: 600, targetGrill: 0) // TODO: need to remove all shutdown steps
	])
	
	func test0_Get_404() throws {
		let app = Application(.testing)
		defer { app.shutdown() }
		try configure(app)
		
		let secretKey = try app.redis.get(XCTVAPOR_KEY).wait()
		var headers = HTTPHeaders()
		headers.basicAuthorization = BasicAuthorization(username: XCTVAPOR_USERNAME, password: secretKey.description)
		
		try app.test(.GET, ROUTE, headers: headers, beforeRequest: { _ in
			XCTAssertNoThrow(try app.redis.delete("program", "program:pending").wait())
		}, afterResponse: { response in
			XCTAssertEqual(response.status, .notFound)
		})
	}
	
	func test1_Post() throws {
		let app = Application(.testing)
		defer { app.shutdown() }
		try configure(app)
		
		let secretKey = try app.redis.get(XCTVAPOR_KEY).wait()
		var headers = HTTPHeaders()
		headers.basicAuthorization = BasicAuthorization(username: XCTVAPOR_USERNAME, password: secretKey.description)
		headers.contentType = .json
		let postBody = ByteBuffer(data: dummyProgram.jsonData())
		
		// Post dummyProgram, verify response == .ok
		try app.test(.POST, ROUTE, headers: headers, body: postBody, beforeRequest: { _ in
			XCTAssertNoThrow(try app.redis.delete("program").wait())
			XCTAssertEqual(try app.redis.exists("program").wait(), 0)
		}, afterResponse: { response in
			XCTAssertEqual(response.status, .ok)
			XCTAssertEqual(try app.redis.exists("program").wait(), 1)
		})
		
		// Validate GET program while "program" + "program:pending" exist
		try app.test(.GET, ROUTE, headers: headers, beforeRequest: { _ in
			XCTAssertEqual(try app.redis.exists("program").wait(), 1)
			XCTAssertEqual(try app.redis.exists("program:pending").wait(), 1)
		}, afterResponse: { response in
			XCTAssertEqual(response.status, .created)
			XCTAssertNoThrow(try app.redis.get("program", asJSON: SmokeProgram.self).wait())
		})
		
		// Validate GET currentStepsForID while "program" exists
		let program = try XCTUnwrap(try app.redis.get("program", asJSON: SmokeProgram.self).wait())
		let id = program.id
		try app.test(.GET, ROUTE.appending("/\(id)"), headers: headers, beforeRequest: { _ in
			XCTAssertNoThrow(try app.redis.set("program:pending", to: 1).wait())
		}, afterResponse: { response in
			XCTAssertEqual(response.status, .ok)
			XCTAssertEqual(try response.content.decode([SmokeStep].self), try app.redis.get("program", asJSON: SmokeProgram.self).wait()?.steps)
			XCTAssertEqual(try app.redis.exists("program:pending").wait(), 0)
		})
		
		_ = app.redis.delete(["program", "program:pending"])
	}
	
	func test2_Delete() throws {
		let app = Application(.testing)
		defer { app.shutdown() }
		try configure(app)
		
		let secretKey = try app.redis.get(XCTVAPOR_KEY).wait()
		var headers = HTTPHeaders()
		headers.basicAuthorization = BasicAuthorization(username: XCTVAPOR_USERNAME, password: secretKey.description)
		
		// Validate DELETE does the thing
		try app.test(.DELETE, ROUTE, headers: headers, beforeRequest: { _ in
			XCTAssertNoThrow(try app.redis.set("program", toJSON: dummyProgram).wait())
			XCTAssertNoThrow(try app.redis.set("program:pending", to: 1).wait())
		}, afterResponse: { response in
			XCTAssertEqual(response.status, .ok)
			XCTAssertEqual(try app.redis.exists("program").wait(), 0)
			XCTAssertEqual(try app.redis.exists("program:pending").wait(), 0)
		})
		
		// Validate GET program returns 404 when "program" does not exist
		try app.test(.GET, ROUTE, headers: headers, beforeRequest: { _ in
			XCTAssertEqual(try app.redis.exists("program").wait(), 0)
			XCTAssertEqual(try app.redis.exists("program:pending").wait(), 0)
		}, afterResponse: { response in
			XCTAssertEqual(response.status, .notFound)
		})
		
		// Validate GET currentStepsForID returns 404 when "program" does not exist
		try app.test(.GET, ROUTE, headers: headers, beforeRequest: { _ in
			XCTAssertEqual(try app.redis.exists("program").wait(), 0)
		}, afterResponse: { response in
			XCTAssertEqual(response.status, .notFound)
		})
	}
}
