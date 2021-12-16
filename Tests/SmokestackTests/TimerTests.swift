/*
 *  TimerTests.swift
 *  https://github.com/magnolialogic/smokestack-vapor
 *
 *  © 2021-Present @magnolialogic
*/

@testable import Smokestack
import XCTVapor
import Redis
import CoreSmokestack

final class TimerTests: XCTestCase {
	var ROUTE = "api/timer/program/started"
	var REDIS_KEY: RedisKey = "timer:program:started"
	
	func test0_Get() throws {
		let app = Application(.testing)
		defer { app.shutdown() }
		try configure(app)
		
		let secretKey = try app.redis.get(XCTVAPOR_KEY).wait()
		var headers = HTTPHeaders()
		headers.basicAuthorization = BasicAuthorization(username: XCTVAPOR_USERNAME, password: secretKey.description)
		
		try app.test(.GET, ROUTE, headers: headers, afterResponse: { response in
			XCTAssert([HTTPStatus.ok, HTTPStatus.notFound].contains(response.status))
			if response.status == .ok {
				XCTAssertEqual(try app.redis.exists(REDIS_KEY).wait(), 1)
				XCTAssertNotNil(try app.redis.get(REDIS_KEY, as: Double.self).wait())
			} else if response.status == .notFound {
				XCTAssertEqual(try app.redis.exists(REDIS_KEY).wait(), 0)
			}
		})
	}
	
	func test1_Get_404() throws {
		let app = Application(.testing)
		defer { app.shutdown() }
		try configure(app)
		
		let secretKey = try app.redis.get(XCTVAPOR_KEY).wait()
		var headers = HTTPHeaders()
		headers.basicAuthorization = BasicAuthorization(username: XCTVAPOR_USERNAME, password: secretKey.description)
		
		try app.test(.GET, ROUTE, headers: headers, beforeRequest: { _ in
			XCTAssertNoThrow(try app.redis.delete(REDIS_KEY).wait())
		}, afterResponse: { response in
			XCTAssertEqual(try app.redis.exists(REDIS_KEY).wait(), 0)
			XCTAssertEqual(response.status, .notFound)
		})
	}
	
	func test2_Post() throws {
		let app = Application(.testing)
		defer { app.shutdown() }
		try configure(app)
		
		let secretKey = try app.redis.get(XCTVAPOR_KEY).wait()
		var headers = HTTPHeaders()
		headers.basicAuthorization = BasicAuthorization(username: XCTVAPOR_USERNAME, password: secretKey.description)
		
		let dummyData = [
			"lastProgramStarted": Date().timeIntervalSince1970
		]
		headers.contentType = .json
		
		let postBody = ByteBuffer(data: try! dummyData.jsonData())
		try app.test(.POST, ROUTE, headers: headers, body: postBody, afterResponse: { response in
			XCTAssertEqual(response.status, .accepted)
		})
	}
	
	func test3_Get_200() throws {
		let app = Application(.testing)
		defer { app.shutdown() }
		try configure(app)
		
		let secretKey = try app.redis.get(XCTVAPOR_KEY).wait()
		var headers = HTTPHeaders()
		headers.basicAuthorization = BasicAuthorization(username: XCTVAPOR_USERNAME, password: secretKey.description)
		
		try app.test(.GET, ROUTE, headers: headers, afterResponse: { response in
			XCTAssertEqual(try app.redis.exists(REDIS_KEY).wait(), 1)
			XCTAssertEqual(response.status, .ok)
			XCTAssertNotEqual(app.redis.get(REDIS_KEY, as: Double.self), nil)
		})
	}
	
	func test4_Delete() throws {
		let app = Application(.testing)
		defer { app.shutdown() }
		try configure(app)
		
		let secretKey = try app.redis.get(XCTVAPOR_KEY).wait()
		var headers = HTTPHeaders()
		headers.basicAuthorization = BasicAuthorization(username: XCTVAPOR_USERNAME, password: secretKey.description)
		
		try app.test(.DELETE, ROUTE, headers: headers, beforeRequest: { _ in
			XCTAssertEqual(try app.redis.exists(REDIS_KEY).wait(), 1)
		}, afterResponse: { response in
			XCTAssertEqual(response.status, .ok)
			XCTAssertEqual(try app.redis.exists(REDIS_KEY).wait(), 0)
		})
	}
	
	func test5_Get_404() throws {
		let app = Application(.testing)
		defer { app.shutdown() }
		try configure(app)
		
		let secretKey = try app.redis.get(XCTVAPOR_KEY).wait()
		var headers = HTTPHeaders()
		headers.basicAuthorization = BasicAuthorization(username: XCTVAPOR_USERNAME, password: secretKey.description)
		
		try app.test(.GET, ROUTE, headers: headers, afterResponse: { response in
			XCTAssertEqual(response.status, .notFound)
			XCTAssertEqual(try app.redis.exists(REDIS_KEY).wait(), 0)
		})
	}
	
	func test6_Post_Future() throws {
		let app = Application(.testing)
		defer { app.shutdown() }
		try configure(app)
		
		let secretKey = try app.redis.get(XCTVAPOR_KEY).wait()
		var headers = HTTPHeaders()
		headers.basicAuthorization = BasicAuthorization(username: XCTVAPOR_USERNAME, password: secretKey.description)
		
		let futureDate: Double = Calendar.current.date(byAdding: .minute, value: 1, to: Date())!.timeIntervalSince1970
		
		let dummyData = [
			"lastProgramStarted": futureDate
		]
		headers.contentType = .json
		
		let postBody = ByteBuffer(data: try! dummyData.jsonData())
		try app.test(.POST, ROUTE, headers: headers, body: postBody, afterResponse: { response in
			XCTAssertEqual(response.status, .badRequest)
		})
	}
}
