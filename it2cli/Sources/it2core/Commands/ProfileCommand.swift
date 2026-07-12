import ArgumentParser
import Foundation
import ProtobufRuntime

struct Profile: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "profile",
        abstract: "Manage iTerm2 profiles.",
        subcommands: [
            List.self,
            Show.self,
            Apply.self,
            Set.self,
        ]
    )
}

// Property name mapping: friendly name -> (API key, type)
private let propertyMap: [String: (key: String, type: PropertyType)] = [
    "font-size": ("Normal Font", .fontSize),
    "font-family": ("Normal Font", .fontFamily),
    "bg-color": ("Background Color", .color),
    "fg-color": ("Foreground Color", .color),
    "transparency": ("Transparency", .float),
    "blur": ("Blur", .bool),
    "cursor-color": ("Cursor Color", .color),
    "selection-color": ("Selection Color", .color),
    "badge-text": ("Badge Text", .string),
]

private enum PropertyType {
    case string, float, bool, color, fontSize, fontFamily
}

// MARK: - profile list

extension Profile {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List all profiles."
        )

        @Flag(name: .long, help: "Output as JSON.")
        var json = false

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let listReq = ITMListProfilesRequest()
            listReq.propertiesArray.add("Name")
            listReq.propertiesArray.add("Guid")

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.listProfilesRequest = listReq

            let response = try client.send(request)
            guard response.submessageOneOfCase == .listProfilesResponse,
                  let listResp = response.listProfilesResponse else {
                throw IT2Error.apiError("No list profiles response")
            }

            guard let profiles = listResp.profilesArray as? [ITMListProfilesResponse_Profile] else { return }
            var profilesData: [[String: String]] = []
            for profile in profiles {
                guard let props = profile.propertiesArray as? [ITMProfileProperty] else { continue }
                var guid = ""
                var name = ""
                for prop in props {
                    if prop.key == "Guid" { guid = prop.jsonValue?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? "" }
                    if prop.key == "Name" { name = prop.jsonValue?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? "" }
                }
                profilesData.append(["guid": guid, "name": name])
            }

            if json {
                if let data = try? JSONSerialization.data(withJSONObject: profilesData, options: .prettyPrinted),
                   let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
            } else {
                for p in profilesData {
                    print("\(p["guid"] ?? "")\t\(p["name"] ?? "")")
                }
            }
        }
    }
}

// MARK: - profile show

extension Profile {
    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "show",
            abstract: "Show profile details."
        )

        @Argument(help: "Profile name.")
        var name: String

        @Flag(name: .long, help: "Output as JSON.")
        var json = false

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let guid = try findProfileGuid(client: client, name: name)

            // Request specific properties for curated display.
            let listReq = ITMListProfilesRequest()
            listReq.guidsArray.add(guid)

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.listProfilesRequest = listReq

            let response = try client.send(request)
            guard response.submessageOneOfCase == .listProfilesResponse,
                  let listResp = response.listProfilesResponse,
                  let profiles = listResp.profilesArray as? [ITMListProfilesResponse_Profile],
                  let profile = profiles.first,
                  let props = profile.propertiesArray as? [ITMProfileProperty] else {
                throw IT2Error.apiError("Could not load profile")
            }

            // Build a dictionary for easy access.
            var propDict: [String: String] = [:]
            for prop in props {
                if let key = prop.key {
                    propDict[key] = prop.jsonValue
                }
            }

            if json {
                // Output curated schema matching the Python tool.
                let font = trimJSONQuotes(propDict["Normal Font"])
                let fontParts = font.split(separator: " ")
                let fontSize = fontParts.last.flatMap { Double($0) } ?? 0.0
                var curatedData: [String: Any] = [
                    "guid": guid,
                    "name": trimJSONQuotes(propDict["Name"]),
                    "font": font,
                    "font_size": fontSize,
                    "background_color": propDict["Background Color"] ?? "null",
                    "foreground_color": propDict["Foreground Color"] ?? "null",
                    "transparency": Double(propDict["Transparency"] ?? "0") ?? 0.0,
                    "blur": propDict["Blur"] ?? "false",
                    "cursor_color": propDict["Cursor Color"] ?? "null",
                    "selection_color": propDict["Selection Color"] ?? "null",
                ]
                let badgeText = trimJSONQuotes(propDict["Badge Text"])
                if !badgeText.isEmpty {
                    curatedData["badge_text"] = badgeText
                }
                printJSON(curatedData)
            } else {
                let profileName = trimJSONQuotes(propDict["Name"]).isEmpty ? name : trimJSONQuotes(propDict["Name"])
                print("Profile: \(profileName)")
                print("GUID: \(guid)")
                let font = trimJSONQuotes(propDict["Normal Font"])
                let fontParts = font.split(separator: " ")
                if fontParts.count >= 2, let size = Double(fontParts.last!) {
                    let family = fontParts.dropLast().joined(separator: " ")
                    print("Font: \(family) \(size)pt")
                } else {
                    print("Font: \(font)")
                }
                print("Background: \(formatColor(propDict["Background Color"]))")
                print("Foreground: \(formatColor(propDict["Foreground Color"]))")
                print("Transparency: \(propDict["Transparency"] ?? "0")")
                print("Blur: \(propDict["Blur"] ?? "false")")
                print("Cursor Color: \(formatColor(propDict["Cursor Color"]))")
                print("Selection Color: \(formatColor(propDict["Selection Color"]))")
                let badge = trimJSONQuotes(propDict["Badge Text"])
                if !badge.isEmpty {
                    print("Badge Text: \(badge)")
                }
            }
        }
    }
}

// MARK: - profile apply

extension Profile {
    struct Apply: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "apply",
            abstract: "Apply profile to session."
        )

        @Argument(help: "Profile name.")
        var name: String

        @Option(name: .shortAndLong, help: "Target session ID (default: active).")
        var session: String?

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let guid = try findProfileGuid(client: client, name: name)

            let listReq = ITMListProfilesRequest()
            listReq.guidsArray.add(guid)

            let listMsg = ITMClientOriginatedMessage()
            listMsg.id_p = client.nextId()
            listMsg.listProfilesRequest = listReq

            let listResp = try client.send(listMsg)
            guard listResp.submessageOneOfCase == .listProfilesResponse,
                  let profilesResp = listResp.listProfilesResponse,
                  let profiles = profilesResp.profilesArray as? [ITMListProfilesResponse_Profile],
                  let profile = profiles.first,
                  let props = profile.propertiesArray as? [ITMProfileProperty] else {
                throw IT2Error.apiError("Could not load profile properties")
            }

            let setProp = ITMSetProfilePropertyRequest()
            setProp.session = session ?? "active"
            for prop in props {
                guard let key = prop.key, let value = prop.jsonValue else { continue }
                let assignment = ITMSetProfilePropertyRequest_Assignment()
                assignment.key = key
                assignment.jsonValue = value
                setProp.assignmentsArray.add(assignment)
            }

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.setProfilePropertyRequest = setProp

            let response = try client.send(request)
            guard response.submessageOneOfCase == .setProfilePropertyResponse,
                  let propResp = response.setProfilePropertyResponse else {
                throw IT2Error.apiError("No set profile property response")
            }
            guard propResp.status == ITMSetProfilePropertyResponse_Status.ok else {
                throw IT2Error.apiError("Apply profile failed with status \(propResp.status.rawValue)")
            }
            print("Applied profile '\(name)' to session")
        }
    }
}

// MARK: - profile set

extension Profile {
    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set",
            abstract: "Set profile property.",
            discussion: """
                Supported friendly property names:
                  font-size         Font size (e.g. "13.5")
                  font-family       Font family name (e.g. "Monaco")
                  bg-color          Background color as hex (e.g. "#1a1a1a")
                  fg-color          Foreground color as hex (e.g. "#c7c8c9")
                  transparency      Window transparency, 0.0-1.0
                  blur              Enable blur, "true" or "false"
                  cursor-color      Cursor color as hex (e.g. "#bbbbbb")
                  selection-color   Selection color as hex (e.g. "#1a0133")
                  badge-text        Badge text
                """
        )

        @Argument(help: "Profile name.")
        var name: String

        @Argument(help: "Property name (see supported names in help).")
        var propertyName: String

        @Argument(help: "Property value.")
        var value: String

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let guid = try findProfileGuid(client: client, name: name)

            let setProp = ITMSetProfilePropertyRequest()
            let guidList = ITMSetProfilePropertyRequest_GuidList()
            guidList.guidsArray.add(guid)
            setProp.guidList = guidList

            let assignment = ITMSetProfilePropertyRequest_Assignment()

            if let mapping = propertyMap[propertyName] {
                assignment.key = mapping.key
                switch mapping.type {
                case .string:
                    assignment.jsonValue = jsonString(value)
                case .float:
                    guard let _ = Double(value) else {
                        throw IT2Error.invalidArgument("Invalid numeric value: \(value)")
                    }
                    assignment.jsonValue = value
                case .bool:
                    assignment.jsonValue = value.lowercased() == "true" ? "true" : "false"
                case .color:
                    assignment.jsonValue = try colorToJSON(value)
                case .fontSize:
                    let currentFont = try getCurrentFont(client: client, guid: guid)
                    let fontParts = currentFont.split(separator: " ")
                    guard fontParts.count >= 2 else {
                        throw IT2Error.apiError("Cannot parse font string: \(currentFont)")
                    }
                    let family = fontParts.dropLast().joined(separator: " ")
                    assignment.jsonValue = jsonString("\(family) \(value)")
                case .fontFamily:
                    let currentFont = try getCurrentFont(client: client, guid: guid)
                    let fontParts = currentFont.split(separator: " ")
                    guard fontParts.count >= 2, let _ = Double(fontParts.last!) else {
                        throw IT2Error.apiError("Cannot parse font string: \(currentFont)")
                    }
                    let size = fontParts.last!
                    assignment.jsonValue = jsonString("\(value) \(size)")
                }
            } else {
                throw IT2Error.invalidArgument("Unknown property: \(propertyName)")
            }

            setProp.assignmentsArray.add(assignment)

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.setProfilePropertyRequest = setProp

            let response = try client.send(request)
            guard response.submessageOneOfCase == .setProfilePropertyResponse,
                  let propResp = response.setProfilePropertyResponse else {
                throw IT2Error.apiError("No set profile property response")
            }
            guard propResp.status == ITMSetProfilePropertyResponse_Status.ok else {
                throw IT2Error.apiError("Set property failed with status \(propResp.status.rawValue)")
            }
            print("Set \(propertyName) = \(value) for profile '\(name)'")
        }

        private func getCurrentFont(client: APIClient, guid: String) throws -> String {
            let listReq = ITMListProfilesRequest()
            listReq.guidsArray.add(guid)
            listReq.propertiesArray.add("Normal Font")

            let msg = ITMClientOriginatedMessage()
            msg.id_p = client.nextId()
            msg.listProfilesRequest = listReq

            let resp = try client.send(msg)
            guard resp.submessageOneOfCase == .listProfilesResponse,
                  let lr = resp.listProfilesResponse,
                  let profiles = lr.profilesArray as? [ITMListProfilesResponse_Profile],
                  let profile = profiles.first,
                  let props = profile.propertiesArray as? [ITMProfileProperty] else {
                throw IT2Error.apiError("Could not get current font")
            }
            for prop in props {
                if prop.key == "Normal Font" {
                    guard let fontStr = prop.jsonValue?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) else {
                        throw IT2Error.apiError("Font value is missing")
                    }
                    return fontStr
                }
            }
            throw IT2Error.apiError("Could not determine current font for profile")
        }

    }
}

// MARK: - Helpers

func findProfileGuid(client: APIClient, name: String) throws -> String {
    let listReq = ITMListProfilesRequest()
    listReq.propertiesArray.add("Name")
    listReq.propertiesArray.add("Guid")

    let request = ITMClientOriginatedMessage()
    request.id_p = client.nextId()
    request.listProfilesRequest = listReq

    let response = try client.send(request)
    guard response.submessageOneOfCase == .listProfilesResponse,
          let listResp = response.listProfilesResponse,
          let profiles = listResp.profilesArray as? [ITMListProfilesResponse_Profile] else {
        throw IT2Error.apiError("Could not list profiles")
    }

    for profile in profiles {
        guard let props = profile.propertiesArray as? [ITMProfileProperty] else { continue }
        var guid: String?
        var profileName: String?
        for prop in props {
            if prop.key == "Guid" { guid = prop.jsonValue?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            if prop.key == "Name" { profileName = prop.jsonValue?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        }
        if profileName == name, let guid = guid {
            return guid
        }
    }
    throw IT2Error.targetNotFound("Profile '\(name)' not found")
}

/// Format a JSON color dict as a human-readable string.
private func formatColor(_ jsonValue: String?) -> String {
    guard let jsonValue = jsonValue,
          let data = jsonValue.data(using: .utf8),
          let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return jsonValue ?? "unknown"
    }
    let r = Int((dict["Red Component"] as? Double ?? 0) * 255)
    let g = Int((dict["Green Component"] as? Double ?? 0) * 255)
    let b = Int((dict["Blue Component"] as? Double ?? 0) * 255)
    return String(format: "#%02x%02x%02x", r, g, b)
}
