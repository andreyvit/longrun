import Foundation
import Testing
@testable import LongrunCore

@Suite struct ConfigurationTests {

    @Test func newConfigurationHasSpecDefaults() {
        let c = Configuration()
        #expect(c.name == "New Configuration")
        #expect(c.command == "")
        #expect(c.launchMode == .exec)
        #expect(c.workingDirectory == "")
        #expect(c.environment.isEmpty)
        #expect(c.autostart == false)
        #expect(c.restartPolicy == .always)
        #expect(c.notificationRules.isEmpty)
        #expect(c.notifyOnUnexpectedExit == true)
        #expect(!c.id.isEmpty)
    }

    @Test func dataRoundTripsThroughJSON() throws {
        var c = Configuration(name: "lifebase", command: "go run ./cmd/lifebase")
        c.launchMode = .loginShell
        c.workingDirectory = "~/dev/lifebase"
        c.environment = [EnvEntry(key: "PORT", value: "8080"), EnvEntry(key: "DEBUG", value: "1")]
        c.autostart = true
        c.restartPolicy = .never
        c.notificationRules = [NotificationRule(pattern: "panic:", enabled: true)]
        c.notifyOnUnexpectedExit = false

        let data = try JSONEncoder().encode(c)
        let decoded = try JSONDecoder().decode(Configuration.self, from: data)

        // id is filename-driven, not part of the JSON — compare everything else.
        #expect(decoded.name == c.name)
        #expect(decoded.command == c.command)
        #expect(decoded.launchMode == c.launchMode)
        #expect(decoded.workingDirectory == c.workingDirectory)
        #expect(decoded.environment == c.environment)
        #expect(decoded.autostart == c.autostart)
        #expect(decoded.restartPolicy == c.restartPolicy)
        #expect(decoded.notificationRules == c.notificationRules)
        #expect(decoded.notifyOnUnexpectedExit == c.notifyOnUnexpectedExit)
    }

    @Test func idIsNotWrittenToJSON() throws {
        let c = Configuration(id: "fixed-id", name: "x")
        let data = try JSONEncoder().encode(c)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("fixed-id"))
        #expect(!json.contains("\"id\""))
    }

    @Test func tolerantDecodeFillsMissingFieldsWithDefaults() throws {
        let json = Data(#"{ "command": "ssh -MN host" }"#.utf8)
        let c = try JSONDecoder().decode(Configuration.self, from: json)
        #expect(c.command == "ssh -MN host")
        // Everything else defaulted.
        #expect(c.name == "New Configuration")
        #expect(c.launchMode == .exec)
        #expect(c.restartPolicy == .always)
        #expect(c.notifyOnUnexpectedExit == true)
        #expect(c.autostart == false)
    }

    @Test func tolerantDecodeIgnoresUnknownKeys() throws {
        let json = Data(#"{ "name": "n", "futureField": 42, "nested": {"x": 1} }"#.utf8)
        let c = try JSONDecoder().decode(Configuration.self, from: json)
        #expect(c.name == "n")
    }

    @Test func tolerantDecodeFallsBackOnBadEnumValues() throws {
        let json = Data(#"{ "launchMode": "exce", "restartPolicy": "sometimes" }"#.utf8)
        let c = try JSONDecoder().decode(Configuration.self, from: json)
        #expect(c.launchMode == .exec)
        #expect(c.restartPolicy == .always)
    }

    @Test func tolerantDecodeFallsBackOnWrongTypes() throws {
        // The natural hand-edit mistakes: 1/0 for a bool, a number for a string.
        let json = Data(#"{ "name": 123, "command": true, "autostart": 1, "notifyOnUnexpectedExit": 0 }"#.utf8)
        let c = try JSONDecoder().decode(Configuration.self, from: json)
        #expect(c.name == "New Configuration")
        #expect(c.command == "")
        #expect(c.autostart == false)
        #expect(c.notifyOnUnexpectedExit == true)
    }

    @Test func tolerantDecodeDegradesMalformedEnvEntry() throws {
        // First entry is missing its value — it degrades to a blank, the array survives.
        let json = Data(#"{ "environment": [ {"key": "PORT"}, {"key": "DEBUG", "value": "1"} ] }"#.utf8)
        let c = try JSONDecoder().decode(Configuration.self, from: json)
        #expect(c.environment == [EnvEntry(key: "PORT", value: ""), EnvEntry(key: "DEBUG", value: "1")])
    }

    @Test func tolerantDecodeDropsWrongTypedEnvironmentField() throws {
        let json = Data(#"{ "environment": "PATH=/x" }"#.utf8)  // a string, not an array
        let c = try JSONDecoder().decode(Configuration.self, from: json)
        #expect(c.environment.isEmpty)
    }

    @Test func validEnumValuesDecode() throws {
        let json = Data(#"{ "launchMode": "bash", "restartPolicy": "never" }"#.utf8)
        let c = try JSONDecoder().decode(Configuration.self, from: json)
        #expect(c.launchMode == .bash)
        #expect(c.restartPolicy == .never)
    }

    @Test func emptyEnvironmentObjectDecodes() throws {
        let c = try JSONDecoder().decode(Configuration.self, from: Data("{}".utf8))
        #expect(c.environment.isEmpty)
        #expect(c.name == "New Configuration")
    }
}
