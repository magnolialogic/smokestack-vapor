/*
 *  ClientTests.swift
 *  https://github.com/magnolialogic/smokestack-vapor
 *
 *  © 2021-Present @magnolialogic
*/

@testable import Smokestack
import CryptoKit
import XCTVapor
import Redis
import CoreSmokestack

final class ClientTests: XCTestCase {
	func test1_Client() throws {
		let app = Application(.testing)
		defer { app.shutdown() }
		try configure(app)
		
		let route = "api/client"
		let password = try app.redis.get(XCTVAPOR_KEY).wait()
		var headers = HTTPHeaders()
		headers.basicAuthorization = BasicAuthorization(username: XCTVAPOR_USERNAME, password: password.description)
		headers.contentType = .json
		let deviceToken = SHA256.hash(data: Data("XCTVapor".utf8)).hex
		let body = ByteBuffer(string: "{\"deviceToken\":\"\(deviceToken)\"}")
		let tokenKey: RedisKey = "token-\(app.environment.name):\(deviceToken)"
		
		// GET without version:firwmare
		try app.test(.POST, route, headers: headers, body: body, beforeRequest: { _ in
			XCTAssertNoThrow(try app.redis.delete("version:firmware").wait())
		}, afterResponse: { response in
			XCTAssertEqual(response.status, .ok)
			XCTAssertNoThrow(try response.content.decode(ClientAPICollection.ClientResponseContent.self).softwareVersion == SOFTWARE_VERSION)
			XCTAssertNotEqual(try app.redis.ttl(tokenKey).wait().timeAmount, nil)
			XCTAssertNoThrow(try app.redis.delete(tokenKey).wait())
		})
		
		// GET with version:firwmare
		try app.test(.POST, route, headers: headers, body: body, beforeRequest: { _ in
			XCTAssertNoThrow(try app.redis.set("version:firmware", to: SOFTWARE_VERSION).wait())
		}, afterResponse: { response in
			XCTAssertEqual(response.status, .ok)
			XCTAssertNoThrow(try response.content.decode(ClientAPICollection.ClientResponseContent.self).softwareVersion == SOFTWARE_VERSION)
			XCTAssertNoThrow(try response.content.decode(ClientAPICollection.ClientResponseContent.self).firmwareVersion == SOFTWARE_VERSION)
			XCTAssertNotEqual(try app.redis.ttl(tokenKey).wait().timeAmount, nil)
			XCTAssertNoThrow(try app.redis.delete("version:firmware").wait())
			XCTAssertNoThrow(try app.redis.delete(tokenKey).wait())
		})
		
		// DELETE
		try app.test(.DELETE, route, headers: headers, body: body, beforeRequest: { _ in
			XCTAssertNoThrow(try app.redis.set(tokenKey, to: deviceToken).wait())
		}, afterResponse: { response in
			XCTAssertEqual(response.status, .accepted)
			XCTAssertEqual(try app.redis.exists(tokenKey).wait(), 0)
		})
	}
	
	func test2_Password() throws {
		let app = Application(.testing)
		defer { app.shutdown() }
		try configure(app)
		
		let route = "api/client/password"
		let password = try app.redis.get(XCTVAPOR_KEY).wait()
		var headers = HTTPHeaders()
		headers.basicAuthorization = BasicAuthorization(username: XCTVAPOR_USERNAME, password: password.description)
		headers.contentType = .json
		let body = ByteBuffer(string: "{\"newPassword\":\"\(password)\"}")
		
		try app.test(.POST, route, headers: headers, body: body, afterResponse: { response in
			XCTAssertEqual(response.status, .accepted)
			XCTAssertEqual(try app.redis.get(XCTVAPOR_KEY).wait(), password)
		})
	}
	
	func test3_Password_minCharacters() throws {
		let app = Application(.testing)
		defer { app.shutdown() }
		try configure(app)
		
		let route = "api/client/password"
		let password = try app.redis.get(XCTVAPOR_KEY).wait()
		var headers = HTTPHeaders()
		headers.basicAuthorization = BasicAuthorization(username: XCTVAPOR_USERNAME, password: password.description)
		headers.contentType = .json
		let newPassword = "1234567"
		let body = ByteBuffer(string: "{\"newPassword\":\"\(newPassword)\"}")
		
		try app.test(.POST, route, headers: headers, body: body, afterResponse: { response in
			XCTAssertEqual(response.status, .badRequest)
			XCTAssertNotEqual(try app.redis.get(XCTVAPOR_KEY).wait(), newPassword.convertedToRESPValue())
		})
	}
}
