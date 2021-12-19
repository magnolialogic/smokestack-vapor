/*
 *  Smoker.swift
 *  https://github.com/magnolialogic/smokestack-vapor
 *
 *  © 2021-Present @magnolialogic
*/

import Vapor
import Redis
import APNS
import CoreSmokestack

// MARK: - Core

final class SmokerAPICollection {
	
	/* /smoker/boot
	 * POST
	 *
	 * @HEADER Firmware-Version: String
	 *
	 * @BODY State.json()
	 *
	 * Called on boot by firmware, nukes any stale keys, initializes state, and stores firmware version
	 */
	func boot(request: Request) async throws -> HTTPStatus {
		try SmokeState.validate(content: request)
		guard let firmwareVersion: String = request.headers.first(name: "Firmware-Version") else {
			throw Abort(.badRequest, reason: "Missing Firmware-Version header")
		}
		guard let requestContent: SmokeState = try? request.content.decode(SmokeState.self) else {
			throw Abort(.badRequest, reason: "JSON does not conform to SmokeState.self")
		}
		_ = request.redis.delete(["online", "state"])
		try await request.redis.set("state", toJSON: requestContent)
		_ = request.redis.set("version:firmware", to: firmwareVersion)
		
		return .ok
	}

	/*
	 * /smoker/heartbeat
	 * POST
	 *
	 * @BODY: SmokeState.json()
	 *
	 * 1. Get/set initial Redis keys
	 * 2. Reconcile smoker state
	 * 3. Construct SmokeReport
	 * 4. Notify any active WebSocket clients
	 * 5. Construct and return ClientResponse
	 *    HEADER Content-Type: application/json
	 *    BODY {
	 *        state: SmokeState.json()?,		nil if Redis key state:pending does not exist
	 *        program: SmokeProgram.json()?		nil if Redis key program:pending does not exist
	 *    }
	 */
	func heartbeat(request: Request) async throws -> ClientResponse {
		try SmokeState.validate(content: request)
		guard let firmwareVersion: String = request.headers.first(name: "Firmware-Version") else {
			throw Abort(.badRequest, reason: "Missing Firmware-Version header")
		}
		guard let requestContent: SmokeState = try? request.content.decode(SmokeState.self) else {
			throw Abort(.badRequest, reason: "JSON does not conform to SmokeState.self")
		}
		
		var smokeReport = SmokeReport()
		var reconciledState = requestContent
		
		let statePending = try await request.redis.send(command: "GETDEL", with: ["state:pending".convertedToRESPValue()]) // 1
		let existingState = try await request.redis.get("state", asJSON: SmokeState.self).get()
		let programPending = try await request.redis.send(command: "GETDEL", with: ["program:pending".convertedToRESPValue()])
		let existingProgram = try await request.redis.get("program", asJSON: SmokeProgram.self).get()
		let online = try await request.redis.send(command: "GETSET", with: ["online".convertedToRESPValue(), 1.convertedToRESPValue()])
		_ = try request.redis.set("version:firmware", to: firmwareVersion).wait()
		switch true { // 2
		case !statePending.isNull && existingState == nil: // Error case (delete interrupt, complete replacement)
			_ = request.redis.delete("state:pending")
			_ = try await request.redis.set("state", toJSON: reconciledState)
		case !statePending.isNull && existingState != nil: // Interrupts pending, state exists (prioritize interrupt settables)
			if let power = existingState?.power, power != reconciledState.power {
				reconciledState.power = power
			}
			if let targetGrill = existingState?.temps[.grillTarget], targetGrill != reconciledState.temps[.grillTarget] {
				reconciledState.temps[.grillTarget] = targetGrill
			}
			if let targetProbe = reconciledState.temps[.probeTarget], targetProbe != reconciledState.temps[.probeTarget] {
				reconciledState.temps[.probeTarget] = targetProbe
			}
			try await request.redis.set("state", toJSON: reconciledState)
		case statePending.isNull && existingState != nil: // No pending interrupts + state exists (apply all heartbeat settables)
			reconciledState = SmokeState.shared.apply(update: reconciledState, to: existingState!)
		case statePending.isNull && (existingState == nil || online.isNull): // No pending interrupts + either no existing state or coming online (complete replacement)
			try await request.redis.set("state", toJSON: reconciledState)
		default:
			break
		}
		
		if online.isNull { // 3
			request.logger.info("Smoker.heartbeat(): Online")
			let firmwareVersion = try await request.redis.get("version:firmware", as: String.self).get()
			smokeReport.state = reconciledState
			smokeReport.firmwareVersion = firmwareVersion
		}
		_ = request.redis.expire("online", after: TimeAmount.seconds(Int64(HEARTBEAT_TTL)))
		
		var probeLatest: Int?
		if requestContent.temps[.probeCurrent] != nil {
			probeLatest = Int(requestContent.temps[.probeCurrent]!.value)
		} else {
			probeLatest = nil
			reconciledState.temps.removeValue(forKey: .probeCurrent)
		}
		
		let reportTemperatureUpdate = SmokeTemperatureUpdate(
			grill: Int(requestContent.temps[.grillCurrent]!.value),
			probe: requestContent.temps[.probeCurrent] != nil ? Int(requestContent.temps[.probeCurrent]!.value) : nil)
		
		smokeReport.temps = reportTemperatureUpdate
		smokeReport.programIndex = existingProgram?.index
		
		if !request.application.notificationManager.ws.clients.active.isEmpty { // 4
			request.application.notificationManager.ws.notifyClients(smokeReport)
		}

		var responseHeaders = HTTPHeaders() // 5
		responseHeaders.contentType = .json
		let responseBody = HeartbeatResponseContent(
			state: statePending.isNull ? nil : reconciledState,
			program: programPending.isNull ? nil : existingProgram
		)
		
		return ClientResponse(
			status: HTTPStatus.ok,
			headers: responseHeaders,
			body: ByteBuffer(data: responseBody.data())
		)
	}
}

// MARK: - Power

extension SmokerAPICollection {
	
	/*
	 * /api/smoker/power
	 * POST
	 *
	 * Only called by iOS app, and only after program has been set
	 */
	func postPower(request: Request) async throws -> HTTPStatus { // TODO: test
		guard try await request.redis.exists("program").get().bool() else {
			throw Abort(.conflict, reason: "Redis key 'program' does not exist, rejecting power request")
		}
		guard let state = try await request.redis.get("state", asJSON: SmokeState.self).get() else {
			throw Abort(.internalServerError, reason: "Redis key 'state' does not exist or does not conform to SmokeState.self")
		}
		
		guard !state.power else {
			throw Abort(.conflict, reason: "always has been")
		}
		
		state.power = true
		_ = try await request.redis.set("state", toJSON: state)
		_ = request.redis.set("state:pending", to: 1)
		
		return .ok
	}
	
	/*
	 * /api/smoker/power
	 * DELETE
	 *
	 * Only called by app (command shutdown)
	 * TODO: Add firmware support
	 */
	func deletePower(request: Request) async throws -> HTTPStatus { // TODO: test
		guard let state = try await request.redis.get("state", asJSON: SmokeState.self).get() else {
			throw Abort(.internalServerError, reason: "Redis key 'state' does not exist or does not conform to SmokeState.self")
		}
		
		guard state.power else {
			throw Abort(.conflict, reason: "never was")
		}
		
		state.power = false
		
		_ = try await request.redis.set("state", toJSON: state)
		_ = request.redis.set("state:pending", to: 1)
		
		return .ok
	}
	
	func target(request: Request) async throws -> HTTPStatus { // TODO: test
		try TargetRequestContent.validate(content: request)
		guard let requestContent = try? request.content.decode(TargetRequestContent.self) else {
			throw Abort(.internalServerError, reason: "Failed to decode request content")
		}
		guard let state = try await request.redis.get("state", asJSON: SmokeState.self).get() else {
			throw Abort(.internalServerError, reason: "Redis key 'state' does not exist or does not conform to SmokeState.self")
		}
		if requestContent.probe != nil && !state.probeConnected {
			throw Abort(.conflict, reason: "Failed to set probe target: not connecteed")
		}
		
		if let grillTarget = requestContent.grill {
			state.temps[.grillTarget] = Measurement(value: Double(grillTarget), unit: .fahrenheit)
		}
		if let probeTarget = requestContent.probe {
			state.temps[.probeTarget] = Measurement(value: Double(probeTarget), unit: .fahrenheit)
		}
		
		_ = try await request.redis.set("state", toJSON: state)
		_ = request.redis.set("state:pending", to: 1)
		
		return .accepted
	}
}

// MARK: - Routes

extension SmokerAPICollection: RouteCollection {
	func boot(routes: RoutesBuilder) throws {
		routes.post(["api", "smoker", "boot"], use: boot)
		routes.post(["api", "smoker", "heartbeat"], use: heartbeat)
		routes.patch(["api", "smoker", "target"], use: target)
		routes.post(["api", "smoker", "power"], use: postPower)
		routes.delete(["api", "smoker", "power"], use: deletePower)
		// TODO: routes.post["api", "smoker", "problem"], use postProblem) // Endpoint for firmware to post errors that need to be delivered to app
	}
}

// MARK: - Structures

extension SmokerAPICollection {
	struct HeartbeatResponseContent: Content, Codable {
		var state: SmokeState?
		var program: SmokeProgram?
		
		func json() -> String {
			var stateDescription = "null"
			do {
				let stateData = try JSONEncoder().encode(state)
				stateDescription = String(data: stateData, encoding: .utf8) ?? "null"
			} catch {
				stateDescription = "null"
			}
			return "{\"state\":\(stateDescription),\"program\":\(program?.json() ?? "null")}"
		}

		func data() -> Data {
			return json().data(using: .utf8)!
		}
	}
	
	struct TargetRequestContent: Content, Validatable {
		let grill: Int?
		let probe: Int?
		
		static func validations(_ validations: inout Validations) {
			validations.add("grill", as: Int.self, is: .in([0, 150, 180, 225, 250, 275, 300, 350, 400]), required: false)
			validations.add("probe", as: Int.self, is: .in([135, 145, 160, 165, 200, 205]), required: false) // Medium-rare beef, beef/pork/ham/fish, ground meat, poultry, ribs, brisket
		}
	}
}
