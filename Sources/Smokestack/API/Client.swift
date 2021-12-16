/*
 *  Client.swift
 *  https://github.com/magnolialogic/smokestack-vapor
 *
 *  © 2021-Present @magnolialogic
*/

import Vapor
import CoreSmokestack

final class ClientAPICollection {
	/* /client
	 * POST
	 *
	 * @BODY JSON{"deviceToken": String.quoted()}
	 *
	 * Basic Auth endpoint, used to register + store device token (7 day TTL) for APNS
	 * Returns server software version and (optionally) firmware version
	 */
	func postClient(request: Request) async throws -> ClientResponseContent {
		struct TokenData: Content, Validatable {
			let deviceToken: String
			
			static func validations(_ validations: inout Validations) {
				validations.add("deviceToken", as: String.self, is: .alphanumeric && .count(64...64), required: true)
			}
		}
		try TokenData.validate(content: request)
		let requestContent = try request.content.decode(TokenData.self)
		_ = request.redis.setex("token-\(request.application.environment.name):\(requestContent.deviceToken)", to: requestContent.deviceToken, expirationInSeconds: 604800)
		let responseContent = ClientResponseContent(softwareVersion: SOFTWARE_VERSION, firmwareVersion: try await request.redis.get("version:firmware").get().string)
		
		return responseContent
	}
	
	/* /client/password
	 * POST
	 *
	 * @BODY: JSON{"newPassword": String.quoted()}
	 *
	 * Resets basic authentication password
	 */
	func postPassword(request: Request) throws -> HTTPStatus {
		struct PasswordData: Content, Validatable {
			let newPassword: String
			
			static func validations(_ validations: inout Validations) {
				validations.add("newPassword", as: String.self, is: .count(8...), required: true)
			}
		}
		try PasswordData.validate(content: request)
		let requestContent = try request.content.decode(PasswordData.self)
		guard let username = request.headers.basicAuthorization?.username else {
			throw Abort(.unauthorized)
		}
		_ = request.redis.set("key:\(username)", to: requestContent.newPassword.saltedMD5Digest(prefix: "smoke", suffix: "stack"))
		
		return .accepted
	}
	
	/* /client
	 * DELETE
	 *
	 * @BODY JSON{"deviceToken": String.quoted()}
	 *
	 * Removes deviceToken from APNS pool
	 */
	func deleteClient(request: Request) throws -> HTTPStatus {
		struct TokenData: Content, Validatable {
			let deviceToken: String
			
			static func validations(_ validations: inout Validations) {
				validations.add("deviceToken", as: String.self, is: .alphanumeric && .count(64...64), required: true)
			}
		}
		try TokenData.validate(content: request)
		let requestContent = try request.content.decode(TokenData.self)
		_ = request.redis.delete("token-\(request.application.environment.name):\(requestContent.deviceToken)")
		
		return .accepted
	}
}

extension ClientAPICollection: RouteCollection {
	func boot(routes: RoutesBuilder) throws {
		routes.post(["api", "client"], use: postClient)
		routes.delete(["api", "client"], use: deleteClient)
		routes.post(["api", "client", "password"], use: postPassword)
	}
}

extension ClientAPICollection {
	struct ClientResponseContent: Content {
		var softwareVersion = SOFTWARE_VERSION
		var firmwareVersion: String?
	}
}
