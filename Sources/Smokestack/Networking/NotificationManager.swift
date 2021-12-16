/*
 *  NotificationManager.swift
 *  https://github.com/magnolialogic/smokestack-vapor
 *
 *  © 2021-Present @magnolialogic
*/

import Foundation
import Vapor
import Redis
import APNS
import CoreSmokestack

final class NotificationManager {
	let apns = APNSController()
	let ws = WebSocketController()
	let jsonDecoder = JSONDecoder()
	let jsonEncoder = JSONEncoder()
	
	private init() {}
	
	static let shared = NotificationManager()
	
	func send(_ report: SmokeReport, for context: Application) {
		sendReport(environment: context.environment, apns: context.apns, redis: context.redis, logger: context.logger, report: report)
	}
	
	func send(_ report: SmokeReport, for context: Request) {
		sendReport(environment: context.application.environment, apns: context.apns, redis: context.redis, logger: context.logger, report: report)
	}
	
	fileprivate func sendReport(environment: Environment, apns: APNSwiftClient, redis: RedisClient, logger: Logger, report: SmokeReport) {
		if ws.clients.active.isEmpty {
			let notification = SmokestackAPNSNotification(aps: APNSwiftPayload(hasContentAvailable: true), data: report)
			self.apns.send(environment: environment, apns: apns, redis: redis, logger: logger, notification: notification)
		} else {
			ws.notifyClients(report)
		}
	}
}
