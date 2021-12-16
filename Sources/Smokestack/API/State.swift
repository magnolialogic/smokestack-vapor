/*
 *  State.swift
 *  https://github.com/magnolialogic/smokestack-vapor
 *
 *  © 2021-Present @magnolialogic
*/

import Vapor
import CoreSmokestack

/* /state
 * GET
 *
 * PUT
 * @HEADER: ContentType
 *
 * @BODY: JSON
 *  Provide State in JSON format
 *
 * Getter/setter for smoker state
 */
final class StateAPICollection {
	func getState(request: Request) async throws -> SmokeState {
		guard try request.redis.exists("state").wait().bool() else {
			throw Abort(.notFound, reason: "Redis key 'state' does not exist")
		}
		guard let state = try await request.redis.get("state", asJSON: SmokeState.self).get() else {
			throw Abort(.internalServerError, reason: "Redis key 'state' does not conform to SmokeState.self")
		}
		
		return state
	}
	
	func putState(request: Request) throws -> HTTPStatus {
		try SmokeState.PatchContent.validate(content: request)
		let putContent = try request.content.decode(SmokeState.self)
		_ = request.redis.set("state", toJSON: putContent)
		if request.headers.basicAuthorization?.username != "firmware" {
			_ = request.redis.set("state:pending", to: 1)
		}
		
		return .accepted
	}
	
	func patchState(request: Request) async throws -> HTTPStatus {
		try SmokeState.PatchContent.validate(content: request)
		guard let patchContent = try? request.content.decode(SmokeState.PatchContent.self) else {
			throw Abort(.badRequest, reason: "JSON does not conform to State.self")
		}
		guard let state = try await request.redis.get("state", asJSON: SmokeState.self).get() else {
			throw Abort(.internalServerError, reason: "Redis key 'state' does not exist or does not conform to SmokeState.self")
		}
		
		SmokeState.shared.apply(update: patchContent, to: state)
		_ = try await request.redis.set("state", toJSON: state)
		
		if request.headers.basicAuthorization?.username != "firmware" {
			_ = request.redis.set("state:pending", to: 1)
		}
		
		return .ok
	}
}

extension StateAPICollection: RouteCollection {
	func boot(routes: RoutesBuilder) throws {
		routes.get(["api", "state"], use: getState)
		routes.put(["api", "state"], use: putState)
		routes.patch(["api", "state"], use: patchState)
	}
}
