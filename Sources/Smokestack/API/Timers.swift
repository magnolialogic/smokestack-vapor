/*
 *  Timers.swift
 *  https://github.com/magnolialogic/smokestack-vapor
 *
 *  © 2021-Present @magnolialogic
*/

import Vapor
import CoreSmokestack

final class TimerAPICollection {
	/* /timer/program/started
	 * GET
	 *
	 * Returns 200 + lastProgramStarted as Double if key exists, 404 otherwise
	 */
	func getProgramStarted(request: Request) async throws -> Double {
		guard let lastProgramStarted = try await request.redis.get("timer:program:started", as: Double.self).get() else {
			throw Abort(.notFound, reason: "key 'timer:program:started' does not exist")
		}
		
		return lastProgramStarted
	}
	
	/* /timer/program/started
	 * POST
	 *
	 * @BODY JSON{"lastProgramStarted": Date().timeIntervalSince1970}
	 *
	 * Called by firmware when program is started with Unix timestamp for lastProgramStarted
	 */
	func postProgramStarted(request: Request) throws -> HTTPStatus {
		struct ProgramTimerData: Content, Validatable {
			let lastProgramStarted: Double
			
			static func validations(_ validations: inout Validations) {
				validations.add("lastProgramStarted", as: Double.self, is: .range(...Date().timeIntervalSince1970), required: true)
			}
		}
		try ProgramTimerData.validate(content: request)
		let requestContent = try request.content.decode(ProgramTimerData.self)
		
		_ = request.redis.set("timer:program:started", to: requestContent.lastProgramStarted)
		
		return .accepted
	}
	
	/* /timer/program/started
	 * DELETE
	 *
	 * Deletes Redis key "timer:program:started"
	 */
	func deleteProgramStarted(request: Request) throws -> HTTPStatus {
		_ = request.redis.delete("timer:program:started")
		
		return .ok
	}
}

extension TimerAPICollection: RouteCollection {
	func boot(routes: RoutesBuilder) throws {
		routes.get(["api", "timer", "program", "started"], use: getProgramStarted)
		routes.post(["api", "timer", "program", "started"], use: postProgramStarted)
		routes.delete(["api", "timer", "program", "started"], use: deleteProgramStarted)
	}
}
