/*
 *  WebSocketController.swift
 *  https://github.com/magnolialogic/smokestack-vapor
 *
 *  © 2021-Present @magnolialogic
*/

import Vapor
import APNS
import CoreSmokestack

final class WebSocketClient {
	var id: UUID
	var socket: WebSocket
	
	init(for socket: WebSocket) {
		self.id = UUID()
		self.socket = socket
	}
}

final class WebSocketClients {
	var clients: [UUID: WebSocketClient]
	
	var active: [WebSocketClient] {
		self.clients.values.filter { !$0.socket.isClosed }
	}
	
	init(clients: [UUID: WebSocketClient] = [:]) {
		self.clients = clients
	}
	
	func add(_ client: WebSocketClient) {
		self.clients[client.id] = client
	}
	
	func remove(_ client: WebSocketClient) {
		self.clients[client.id] = nil
	}
	
	func find(_ uuid: UUID) -> WebSocketClient? {
		return self.clients[uuid]
	}
}

final class WebSocketController {
	let app: Application
	var clients = WebSocketClients()
	private let jsonEncoder = JSONEncoder()
	
	init(app: Application) {
		self.app = app
	}
	
	func greetClient(request: Request, webSocket: WebSocket) {
		Task {
			do {
				let online = try await request.redis.exists("online").get().bool()
				var temperatureUpdate: SmokeTemperatureUpdate?
				if online {
					guard let state = try await request.redis.get("state", asJSON: SmokeState.self).get() else {
						throw Abort(.internalServerError, reason: "Redis key 'state' does not exist or does not conform to SmokeState.self")
					}
					temperatureUpdate = SmokeTemperatureUpdate(grill: Int(state.temps[.grillCurrent]!.value))
					if let probeCurrent = state.temps[.probeCurrent]?.value {
						temperatureUpdate?.probe = Int(probeCurrent)
					}
				}
				let state = try await request.redis.get("state", asJSON: SmokeState.self).get()
				let program = try await request.redis.get("program", asJSON: SmokeProgram.self).get()
				let webSocketReport = SmokeReport(temps: temperatureUpdate ?? nil, state: state ?? nil, program: program ?? nil, softwareVersion: SOFTWARE_VERSION, firmwareVersion: online ? try request.redis.get("version:firmware", as: String.self).wait() : nil)
				let webSocketData = try jsonEncoder.encode(webSocketReport)
				request.logger.info("WS GREET \(webSocketReport)")
				webSocket.send(webSocketData.bytes)
			} catch {
				request.logger.error("WS ERROR!! Failed to greet new client")
			}
		}
	}
	
	func notifyClients(_ report: SmokeReport) {
		do {
			let webSocketData = try jsonEncoder.encode(report)
			clients.active.forEach { client in
				client.socket.send(webSocketData.bytes)
			}
		} catch {
			app.logger.error("\(error.localizedDescription)")
		}
	}
}
