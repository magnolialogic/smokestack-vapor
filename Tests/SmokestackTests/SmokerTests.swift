/*
 *  SmokerTests.swift
 *  https://github.com/magnolialogic/smokestack-vapor
 *
 *  © 2021-Present @magnolialogic
*/

@testable import Smokestack
import XCTVapor
import Redis
import CoreSmokestack

final class SmokerTests: XCTestCase {
	let jsonEncoder = JSONEncoder()
	
	func test1_Init() throws {
		let app = Application(.testing)
		defer { app.shutdown() }
		try configure(app)
		
		let password = try app.redis.get(XCTVAPOR_KEY).wait()
		var headers = HTTPHeaders()
		headers.basicAuthorization = BasicAuthorization(username: XCTVAPOR_USERNAME, password: password.description)
		headers.contentType = .json
		headers.add(name: "Firmware-Version", value: SOFTWARE_VERSION)
		let postBody = ByteBuffer(data: try jsonEncoder.encode(SmokeState.shared))
		
		try app.test(.POST, "api/smoker/boot", headers: headers, body: postBody, beforeRequest: { _ in
			let msetKeys: [RedisKey: RESPValue] = [
				"online": 1.convertedToRESPValue(),
				"state": "state".convertedToRESPValue()
			]
			XCTAssertNoThrow(try app.redis.mset(msetKeys).wait())
		}, afterResponse: { response in
			XCTAssertEqual(response.status, .ok)
			XCTAssertEqual(try app.redis.exists(["online"]).wait(), 0)
			XCTAssertEqual(try app.redis.get("state", asJSON: SmokeState.self).wait(), SmokeState.shared)
			XCTAssertNoThrow(try app.redis.delete("state").wait())
			XCTAssertNoThrow(try app.redis.delete("version:firmware").wait())
		})
	}
	
	func test2_Heartbeat_201_Neither() throws {
		let app = Application(.testing)
		defer { app.shutdown() }
		try configure(app)
		
		let secretKey = try app.redis.get(XCTVAPOR_KEY).wait()
		var headers = HTTPHeaders()
		headers.contentType = .json
		headers.basicAuthorization = BasicAuthorization(username: XCTVAPOR_USERNAME, password: secretKey.description)
		headers.add(name: "Firmware-Version", value: SOFTWARE_VERSION)
		
		let dummyState = SmokeState.shared
		dummyState.temps[.grillCurrent] = Measurement(value: 225, unit: .fahrenheit)
		dummyState.temps[.probeCurrent] = Measurement(value: 105, unit: .fahrenheit)
		let postBodyData = try jsonEncoder.encode(dummyState)
		let postBody = ByteBuffer(data: postBodyData)
		
		// TODO: add test for version:firmware
		
		try app.test(.POST, "api/smoker/heartbeat", headers: headers, body: postBody, beforeRequest: { _ in
			XCTAssertNoThrow(try app.redis.delete("state:pending").wait())
			XCTAssertNoThrow(try app.redis.delete("program:pending").wait())
		}, afterResponse: { response in
			XCTAssertEqual(HTTPStatus.ok, response.status)
			let responseContent = try XCTUnwrap(try response.content.decode(SmokerAPICollection.HeartbeatResponseContent.self))
			XCTAssertNil(responseContent.state)
			XCTAssertNil(responseContent.program)
			XCTAssertNoThrow(try app.redis.delete("state").wait())
			XCTAssertNoThrow(try app.redis.delete("version:firmware").wait())
		})
	}
	
	func test3_Heartbeat_201_State() throws {
		let app = Application(.testing)
		defer { app.shutdown() }
		try configure(app)
		
		let secretKey = try app.redis.get(XCTVAPOR_KEY).wait()
		var headers = HTTPHeaders()
		headers.contentType = .json
		headers.basicAuthorization = BasicAuthorization(username: XCTVAPOR_USERNAME, password: secretKey.description)
		headers.add(name: "Firmware-Version", value: SOFTWARE_VERSION)
		
		let dummyState = SmokeState.shared
		dummyState.temps[.grillCurrent] = Measurement(value: 225, unit: .fahrenheit)
		dummyState.temps[.probeCurrent] = Measurement(value: 105, unit: .fahrenheit)
		let postBodyData = try jsonEncoder.encode(dummyState)
		let postBody = ByteBuffer(data: postBodyData)

		// Validate state:pending == 1 and program:pending == nil
		try app.test(.POST, "api/smoker/heartbeat", headers: headers, body: postBody, beforeRequest: { _ in
			XCTAssertNoThrow(try app.redis.set("state:pending", to: 1).wait())
			XCTAssertNoThrow(try app.redis.delete("program:pending").wait())
		}, afterResponse: { response in
			XCTAssertEqual(HTTPStatus.ok, response.status)
			let responseContent = try XCTUnwrap(try response.content.decode(SmokerAPICollection.HeartbeatResponseContent.self))
			XCTAssertNotNil(responseContent.state)
			XCTAssertNil(responseContent.program)
			XCTAssertEqual(try app.redis.exists("state:pending").wait(), 0)
			XCTAssertNoThrow(try app.redis.delete("state").wait())
			XCTAssertNoThrow(try app.redis.delete("version:firmware").wait())
		})
	}
	
	func test4_Heartbeat_201_Program() throws {
		let app = Application(.testing)
		defer { app.shutdown() }
		try configure(app)
		
		let secretKey = try app.redis.get(XCTVAPOR_KEY).wait()
		var headers = HTTPHeaders()
		headers.contentType = .json
		headers.basicAuthorization = BasicAuthorization(username: XCTVAPOR_USERNAME, password: secretKey.description)
		headers.add(name: "Firmware-Version", value: SOFTWARE_VERSION)
		
		let dummyState = SmokeState.shared
		dummyState.temps[.grillCurrent] = Measurement(value: 225, unit: .fahrenheit)
		dummyState.temps[.probeCurrent] = Measurement(value: 105, unit: .fahrenheit)
		let postBodyData = try jsonEncoder.encode(dummyState)
		let postBody = ByteBuffer(data: postBodyData)
		
		// Validate state:pending == nil and program:pending == 1
		try app.test(.POST, "api/smoker/heartbeat", headers: headers, body: postBody, beforeRequest: { _ in
			XCTAssertNoThrow(try app.redis.delete("state:pending").wait())
			let dummyProgram = SmokeProgram(steps: [
				SmokeStep(mode: .start, trigger: .time, limit: 600, targetGrill: 150),
				SmokeStep(mode: .hold, trigger: .time, limit: 7200, targetGrill: 225),
				SmokeStep(mode: .shutdown, trigger: .time, limit: 900, targetGrill: 0)
			])
			XCTAssertNoThrow(try app.redis.set("program", toJSON: dummyProgram).wait())
			XCTAssertNoThrow(try app.redis.set("program:pending", to: 1).wait())
		}, afterResponse: { response in
			XCTAssertEqual(HTTPStatus.ok, response.status)
			let responseContent = try XCTUnwrap(try response.content.decode(SmokerAPICollection.HeartbeatResponseContent.self))
			XCTAssertNil(responseContent.state)
			XCTAssertNotNil(responseContent.program?.steps)
			XCTAssertEqual(try app.redis.exists("program:pending").wait(), 0)
			XCTAssertNoThrow(try app.redis.delete("state").wait())
			XCTAssertNoThrow(try app.redis.delete("version:firmware").wait())
		})
	}
	
	func test5_Heartbeat_201_Both() throws {
		let app = Application(.testing)
		defer { app.shutdown() }
		try configure(app)
		
		let secretKey = try app.redis.get(XCTVAPOR_KEY).wait()
		var headers = HTTPHeaders()
		headers.contentType = .json
		headers.basicAuthorization = BasicAuthorization(username: XCTVAPOR_USERNAME, password: secretKey.description)
		headers.add(name: "Firmware-Version", value: SOFTWARE_VERSION)
		
		let dummyState = SmokeState.shared
		dummyState.temps[.grillCurrent] = Measurement(value: 225, unit: .fahrenheit)
		dummyState.temps[.probeCurrent] = Measurement(value: 105, unit: .fahrenheit)
		let postBodyData = try jsonEncoder.encode(dummyState)
		let postBody = ByteBuffer(data: postBodyData)
		
		try app.test(.POST, "api/smoker/heartbeat", headers: headers, body: postBody, beforeRequest: { _ in
			XCTAssertNoThrow(try app.redis.set("state:pending", to: 1).wait())
			let dummyProgram = SmokeProgram(steps: [
				SmokeStep(mode: .start, trigger: .time, limit: 600, targetGrill: 150),
				SmokeStep(mode: .hold, trigger: .time, limit: 7200, targetGrill: 225),
				SmokeStep(mode: .shutdown, trigger: .time, limit: 900, targetGrill: 0)
			])
			XCTAssertNoThrow(try app.redis.set("program", toJSON: dummyProgram).wait())
			XCTAssertNoThrow(try app.redis.set("program:pending", to: 1).wait())
		}, afterResponse: { response in
			XCTAssertEqual(HTTPStatus.ok, response.status)
			let responseContent = try XCTUnwrap(try response.content.decode(SmokerAPICollection.HeartbeatResponseContent.self))
			XCTAssertNotNil(responseContent.state)
			XCTAssertNotNil(responseContent.program?.steps)
			XCTAssertEqual(try app.redis.exists("program:pending").wait(), 0)
			XCTAssertEqual(try app.redis.exists("state:pending").wait(), 0)
			XCTAssertNoThrow(try app.redis.delete("program").wait())
			XCTAssertNoThrow(try app.redis.delete("state").wait())
			XCTAssertNoThrow(try app.redis.delete("version:firmware").wait())
		})
	}
	
	func test6_Heartbeat_Online() throws {
		let app = Application(.testing)
		defer { app.shutdown() }
		try configure(app)
		
		let secretKey = try app.redis.get(XCTVAPOR_KEY).wait()
		var headers = HTTPHeaders()
		headers.contentType = .json
		headers.basicAuthorization = BasicAuthorization(username: XCTVAPOR_USERNAME, password: secretKey.description)
		headers.add(name: "Firmware-Version", value: SOFTWARE_VERSION)
		
		let dummyState = SmokeState.shared
		dummyState.temps[.grillCurrent] = Measurement(value: 225, unit: .fahrenheit)
		let postBodyData = try jsonEncoder.encode(dummyState)
		let postBody = ByteBuffer(data: postBodyData)
		
		try app.test(.POST, "api/smoker/heartbeat", headers: headers, body: postBody, beforeRequest: { _ in
			XCTAssertNoThrow(try app.redis.delete("online").wait())
		}, afterResponse: { response in
			XCTAssert([HTTPStatus.ok, HTTPStatus.partialContent, HTTPStatus.multiStatus].contains(response.status))
			XCTAssertEqual(try app.redis.exists("online").wait(), 1)
			XCTAssertNotEqual(try app.redis.ttl("online").wait().timeAmount, nil)
			XCTAssertNoThrow(try app.redis.delete("state").wait())
			XCTAssertNoThrow(try app.redis.delete("version:firmware").wait())
		})
	}
	
	func test7_Heartbeat_Probe() throws {
		let app = Application(.testing)
		defer { app.shutdown() }
		try configure(app)
		
		let secretKey = try app.redis.get(XCTVAPOR_KEY).wait()
		var headers = HTTPHeaders()
		headers.contentType = .json
		headers.basicAuthorization = BasicAuthorization(username: XCTVAPOR_USERNAME, password: secretKey.description)
		headers.add(name: "Firmware-Version", value: SOFTWARE_VERSION)
		
		let dummyState = SmokeState.shared
		dummyState.temps[.grillCurrent] = Measurement(value: 225, unit: .fahrenheit)
		dummyState.temps[.probeCurrent] = Measurement(value: 105, unit: .fahrenheit)
		let postBodyData = try jsonEncoder.encode(dummyState)
		let postBody = ByteBuffer(data: postBodyData)
		
		try app.test(.POST, "api/smoker/heartbeat", headers: headers, body: postBody, afterResponse: { response in
			XCTAssertEqual(HTTPStatus.ok, response.status)
			let resultState = try app.redis.get("state", asJSON: SmokeState.self).wait()
			XCTAssertEqual(resultState!.temps[.grillCurrent]!.value, dummyState.temps[.grillCurrent]!.value)
			XCTAssertEqual(resultState!.temps[.probeCurrent]!.value, dummyState.temps[.probeCurrent]!.value)
			XCTAssertNoThrow(try app.redis.delete("state").wait())
			XCTAssertNoThrow(try app.redis.delete("version:firmware").wait())
		})
	}
	
	func test8_Heartbeat_NoProbe() throws {
		let app = Application(.testing)
		defer { app.shutdown() }
		try configure(app)
		
		let secretKey = try app.redis.get(XCTVAPOR_KEY).wait()
		var headers = HTTPHeaders()
		headers.contentType = .json
		headers.basicAuthorization = BasicAuthorization(username: XCTVAPOR_USERNAME, password: secretKey.description)
		headers.add(name: "Firmware-Version", value: SOFTWARE_VERSION)
		
		let dummyState = SmokeState.shared
		dummyState.temps[.grillCurrent] = Measurement(value: 225, unit: .fahrenheit)
		dummyState.temps.removeValue(forKey: .probeCurrent)
		let postBodyData = try jsonEncoder.encode(dummyState)
		let postBody = ByteBuffer(data: postBodyData)
		
		try app.test(.POST, "api/smoker/heartbeat", headers: headers, body: postBody, afterResponse: { response in
			XCTAssertEqual(HTTPStatus.ok, response.status)
			let resultState = try app.redis.get("state", asJSON: SmokeState.self).wait()
			XCTAssertEqual(resultState!.temps[.grillCurrent]!.value, dummyState.temps[.grillCurrent]!.value)
			XCTAssertNil(resultState?.temps[.probeCurrent]?.value)
			XCTAssertNoThrow(try app.redis.delete("state").wait())
			XCTAssertNoThrow(try app.redis.delete("version:firmware").wait())
		})
	}
}
