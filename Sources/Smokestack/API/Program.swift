/*
 *  Program.swift
 *  https://github.com/magnolialogic/smokestack-vapor
 *
 *  © 2021-Present @magnolialogic
*/

import Vapor
import APNS
import CoreSmokestack

final class ProgramAPICollection {
	func getCurrentProgramID(request: Request) async throws -> ClientResponse {
		guard try await request.redis.exists("program").get() == 1 else {
			throw Abort(.notFound, reason: "No program exists")
		}
		guard let program = try await request.redis.get("program", asJSON: SmokeProgram.self).get() else {
			throw Abort(.notFound, reason: "Redis key 'program' does not conform to SmokeProgram.self")
		}
		
		return ClientResponse(
			status: HTTPStatus.created,
			headers: [:],
			body: ByteBuffer(data: program.id.data(using: .utf8)!)
		)
	}
	
	func postProgram(request: Request) throws -> HTTPStatus {
		try SmokeProgram.validate(content: request)
		let requestContent = try request.content.decode(SmokeProgram.self)
		
		try requestContent.steps.forEach { step in
			if step.trigger == .temp && step.limit >= Int(step.targetGrill.value) {
				throw Abort(.badRequest, reason: "Can't accept program with step.trigger == .temp && step.limit >= step.targetGrill")
			}
		}
		_ = request.redis.set("program", toJSON: requestContent)
		_ = request.redis.set("program:pending", to: 1)
		
		return .ok
	}
	
	func deleteProgram(request: Request) -> HTTPStatus {
		_ = request.redis.delete(["program", "program:pending"])
		
		return .ok
	}
	
	func getCurrentStepsForID(request: Request) async throws -> [SmokeStep] {
		guard let program = try await request.redis.get("program", asJSON: SmokeProgram.self).get() else {
			throw Abort(.notFound, reason: "Redis key 'program' does not exist or does not conform to SmokeProgram.self")
		}
		guard program.id == UUID(uuidString: request.url.path.pathComponents.last?.description ?? "nil")?.uuidString else {
			throw Abort(.badRequest, reason: "invalid ID")
		}
		_ = request.redis.delete("program:pending")
		
		return program.steps
	}
	
	func getCurrentProgramIndex(request: Request) async throws -> Int { // TODO: tests
		guard let program = try await request.redis.get("program", asJSON: SmokeProgram.self).get() else {
			throw Abort(.notFound, reason: "Redis key 'program' does not exist or does not conform to SmokeProgram.self")
		}
		
		return program.index
	}
	
	func postCurrentProgramIndex(request: Request) async throws -> HTTPStatus { // TODO: tests
		try ProgramChangedRequestContent.validate(content: request)
		let requestContent = try request.content.decode(ProgramChangedRequestContent.self)
		guard var program = try await request.redis.get("program", asJSON: SmokeProgram.self) else {
			throw Abort(.notFound, reason: "Redis key 'program' does not exist or does not conform to SmokeProgram.self")
		}
		program.index = requestContent.index
		_ = try await request.redis.set("program", toJSON: program)
		request.application.notificationManager.send(SmokeReport(programIndex: requestContent.index))
		
		return .ok
	}
}

extension ProgramAPICollection: RouteCollection {
	func boot(routes: RoutesBuilder) throws {
		routes.get(["api", "program"], use: getCurrentProgramID)
		routes.post(["api", "program"], use: postProgram)
		routes.delete(["api", "program"], use: deleteProgram)
		routes.get(["api", "program", ":id"], use: getCurrentStepsForID)
		routes.get(["api", "program", "index"], use: getCurrentProgramIndex)
		routes.post(["api", "program", "index"], use: postCurrentProgramIndex)
	}
}

extension ProgramAPICollection {
	struct ProgramChangedRequestContent: Content, Validatable {
		let index: Int
		
		static func validations(_ validations: inout Validations) {
			validations.add("index", as: Int.self, is: .valid)
		}
	}
}
