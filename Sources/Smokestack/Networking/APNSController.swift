/*
 *  APNSController.swift
 *  https://github.com/magnolialogic/smokestack-vapor
 *
 *  © 2021-Present @magnolialogic
*/

import Vapor
import Redis
import APNS
import CoreSmokestack

struct SmokestackAPNSNotification: APNSwiftNotification {
	let aps: APNSwiftPayload
	let data: SmokeReport
	
	init(aps: APNSwiftPayload, data: SmokeReport) {
		self.aps = aps
		self.data = data
	}
}

class APNSController {
	private func getByteBuffer(for notification: SmokestackAPNSNotification) throws -> ByteBuffer {
		return ByteBuffer(data: try NotificationManager.shared.jsonEncoder.encode(notification))
	}
	
	// MARK: - Overload all the things
	
	func send(environment: Environment, apns: APNSwiftClient, redis: RedisClient, logger: Logger, notification: SmokestackAPNSNotification) {
		Task {
			try await sendAPNSRawBytes(environment: environment, apns: apns, redis: redis, logger: logger, notification: notification)
		}
	}
	
	func send(_ notification: SmokestackAPNSNotification, for context: Application) {
		Task {
			try await sendAPNSRawBytes(environment: context.environment, apns: context.apns, redis: context.redis, logger: context.logger, notification: notification)
		}
	}
	
	func send(_ notification: SmokestackAPNSNotification, for context: Request) {
		Task {
			try await sendAPNSRawBytes(environment: context.application.environment, apns: context.apns, redis: context.redis, logger: context.logger, notification: notification)
		}
	}
	
	// MARK: - Dirty work
	
	fileprivate func sendAPNSRawBytes(environment: Environment, apns: APNSwiftClient, redis: RedisClient, logger: Logger, notification: SmokestackAPNSNotification) async throws {
		let deviceTokens = try await redisGetAllDeviceTokens(environment: environment, redis: redis)
		guard !deviceTokens.isEmpty else {
			logger.error("APNSController.send(): no tokens registered!")
			return
		}
		var background = false
		if notification.aps.alert == nil {
			background = true
		}
		let apnsBytes = try getByteBuffer(for: notification)
		deviceTokens.forEach { deviceToken in
			apns.send(rawBytes: apnsBytes, pushType: background ? .background : .alert, to: deviceToken).whenFailure { error in
				self.handleAPNSError(environment: environment, redis: redis, logger: logger, error: error, deviceToken: deviceToken)
			}
		}
	}
	
	// MARK: - Convenience methods
	
	fileprivate func handleAPNSError(environment: Environment, redis: RedisClient, logger: Logger, error: Error, deviceToken: String) {
		guard let error = error as? APNSwiftError.ResponseError else {
			logger.report(error: error)
			return
		}
		switch error {
		case .badRequest(let apnsResponseError):
			if apnsResponseError == .unregistered {
				logger.error("APNSController.handleAPNSError(): deleting expired token \(deviceToken)")
				_ = redis.delete("token-\(environment.name):\(deviceToken)")
			} else {
				logger.error("APNSController.handleAPNSError(): error \(apnsResponseError) for \(deviceToken)")
			}
		}
	}

	fileprivate func redisGetAllDeviceTokens(environment: Environment, redis: RedisClient) async throws -> [String] {
		var (cursor, tokenKeys) = try await redis.scan(startingFrom: 0, matching: "token-\(environment.name):*").get()
		while cursor != 0 {
			let (newCursor, moreTokenKeys) = try await redis.scan(startingFrom: cursor, matching: "token-\(environment.name):*").get()
			tokenKeys.append(contentsOf: moreTokenKeys)
			cursor = newCursor
		}
		return tokenKeys.map { $0.components(separatedBy: ":")[1] }
	}
}
