/*
 *  Extensions.swift
 *  https://github.com/magnolialogic/smokestack-vapor
 *
 *  © 2021-Present @magnolialogic
*/

import Vapor
import CoreSmokestack
import MLCommon

extension SmokeState: Content, Validatable {
	public static func validations(_ validations: inout Validations) {
		validations.add("mode", as: String.self, is: .in(SmokeMode.allCases.map({ $0.rawValue })), required: true)
		validations.add("probeConnected", as: Bool.self, is: .valid, required: true)
		validations.add("online", as: Bool.self, is: .valid, required: true)
		validations.add("power", as: Bool.self, is: .valid, required: true)
		validations.add("temps", as: [String: Int].self, required: false)
	}
}

extension SmokeState.PatchContent: Content, Validatable {
	public static func validations(_ validations: inout Validations) {
		validations.add("mode", as: String.self, is: .in(SmokeMode.allCases.map({ $0.rawValue })), required: false)
		validations.add("probeConnected", as: Bool.self, is: .valid, required: false)
		validations.add("online", as: Bool.self, is: .valid, required: false)
		validations.add("power", as: Bool.self, is: .valid, required: false)
		validations.add("temps", as: [String: Int?].self, required: false)
	}
}

extension SmokeProgram: Content, Validatable {
	public static func validations(_ validations: inout Validations) {
		validations.add("id", as: String.self, required: true)
		validations.add("index", as: Int.self, required: true)
		validations.add("steps", as: [SmokeStep].self, is: !.empty, required: true)
	}
}

extension SmokeMode: Content {}
extension SmokeStep: Content {}
