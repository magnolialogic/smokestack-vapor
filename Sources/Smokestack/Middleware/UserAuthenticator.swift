/*
 *  UserAuthenticator.swift
 *  https://github.com/magnolialogic/smokestack-vapor
 *
 *  © 2021-Present @magnolialogic
*/

import Vapor
import Redis
import CoreSmokestack

struct UserAuthenticator: BasicAuthenticator {
	struct User: Authenticatable {
		enum ClientType: String, CaseIterable, Content {
			case app = "app"
			case firmware = "firmware"
			case insomnia = "Insomnia"
			case xctest = "XCTVapor"
		}
		
		let id: UUID
		let clientType: ClientType
	}
	
	// TODO: Adopt async/await (not working implemented yet in 4.53.0)
	func authenticate(basic: BasicAuthorization, for request: Request) -> EventLoopFuture<Void> {
		return request.redis.get("key:\(basic.username)", as: String.self).flatMap { secretKey in
			guard let secretKey = secretKey else {
				return request.eventLoop.makeFailedFuture(Abort(.internalServerError))
			}
			if User.ClientType.allCases.contains(where: { $0.rawValue == basic.username }),
			   basic.password.saltedMD5Digest(prefix: "smoke", suffix: "stack") == secretKey { // TODO: move these into .env
				let user = User(id: UUID(), clientType: User.ClientType(rawValue: basic.username)!)
				request.auth.login(user)
			}
			return request.eventLoop.makeSucceededFuture(())
		}
	}
}
