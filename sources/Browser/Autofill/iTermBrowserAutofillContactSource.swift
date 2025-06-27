import Foundation
import Contacts

@available(macOS 11.0, *)
@MainActor
class iTermBrowserAutofillContactSource {
    
    enum ContactError: Error {
        case accessDenied
        case noContactFound
        case contactsUnavailable
    }
    
    private let store = CNContactStore()
    
    // Request contacts access if needed
    func requestContactsAccess() async -> Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        
        switch status {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            do {
                return try await store.requestAccess(for: .contacts)
            } catch {
                DLog("Failed to request contacts access: \(error)")
                return false
            }
        @unknown default:
            return false
        }
    }
    
    // Get the user's contact info (typically the "me" card)
    func getUserContact() async throws -> [String: String] {
        guard await requestContactsAccess() else {
            throw ContactError.accessDenied
        }
        
        // Try to get the "me" card first
        if let meContact = try? store.unifiedMeContactWithKeys(toFetch: getUserContactKeys()) {
            return extractContactData(from: meContact)
        }
        
        // Fallback: get the first contact with the most complete information
        let request = CNContactFetchRequest(keysToFetch: getUserContactKeys())
        var bestContact: CNContact?
        var bestScore = 0

        do {
            try store.enumerateContacts(with: request) { contact, stop in
                let score = scoreContact(contact)
                if score > bestScore {
                    bestContact = contact
                    bestScore = score
                }

                if bestScore >= 10 {
                    stop.pointee = true
                }
            }
        } catch {
            DLog("\(error)")
        }
        guard let contact = bestContact else {
            throw ContactError.noContactFound
        }
        
        return extractContactData(from: contact)
    }
    
    // Get contact data for specific field types
    func getFieldData(for fieldTypes: [String]) async throws -> [String: String] {
        let contactData = try await getUserContact()
        var result: [String: String] = [:]
        
        for fieldType in fieldTypes {
            if let value = contactData[fieldType] {
                result[fieldType] = value
            }
        }
        
        return result
    }
    
    // Prepare autofill data for the specified fields
    func prepareAutofillData(for fields: [[String: Any]]) async throws -> [[String: String]] {
        let contactData = try await getUserContact()
        var fieldDataToFill: [[String: String]] = []
        
        for field in fields {
            guard let fieldType = field["type"] as? String,
                  let fieldId = field["id"] as? String?,
                  let fieldName = field["name"] as? String? else {
                continue
            }
            
            // Get the value for this field type from contact data
            if let value = contactData[fieldType], !value.isEmpty {
                var fieldData: [String: String] = [
                    "value": value
                ]
                
                if let id = fieldId, !id.isEmpty {
                    fieldData["id"] = id
                }
                if let name = fieldName, !name.isEmpty {
                    fieldData["name"] = name
                }
                
                fieldDataToFill.append(fieldData)
            }
        }
        
        return fieldDataToFill
    }
    
    // MARK: - Private Methods
    
    private func getUserContactKeys() -> [CNKeyDescriptor] {
        return [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
        ]
    }
    
    private func extractContactData(from contact: CNContact) -> [String: String] {
        var data: [String: String] = [:]
        
        // Name fields
        if !contact.givenName.isEmpty {
            data["firstName"] = contact.givenName
        }
        if !contact.familyName.isEmpty {
            data["lastName"] = contact.familyName
        }
        
        let fullName = CNContactFormatter.string(from: contact, style: .fullName)
        if let fullName = fullName, !fullName.isEmpty {
            data["fullName"] = fullName
        }
        
        // Email (prefer work, then home, then first available)
        if !contact.emailAddresses.isEmpty {
            var email: String?
            
            // Look for work email first
            for emailAddress in contact.emailAddresses {
                if let label = emailAddress.label {
                    if label.contains("work") || label.contains("Work") {
                        email = String(emailAddress.value)
                        break
                    }
                }
            }
            
            // Fallback to home email
            if email == nil {
                for emailAddress in contact.emailAddresses {
                    if let label = emailAddress.label {
                        if label.contains("home") || label.contains("Home") {
                            email = String(emailAddress.value)
                            break
                        }
                    }
                }
            }
            
            // Fallback to first email
            if email == nil {
                email = String(contact.emailAddresses.first?.value ?? "")
            }
            
            if let email = email, !email.isEmpty {
                data["email"] = email
            }
        }
        
        // Phone number (prefer mobile, then work, then home, then first available)
        if !contact.phoneNumbers.isEmpty {
            var phone: String?
            
            // Look for mobile first
            for phoneNumber in contact.phoneNumbers {
                if let label = phoneNumber.label {
                    if label.contains("mobile") || label.contains("Mobile") || 
                       label.contains("iPhone") || label.contains("Cell") {
                        phone = phoneNumber.value.stringValue
                        break
                    }
                }
            }
            
            // Fallback to work phone
            if phone == nil {
                for phoneNumber in contact.phoneNumbers {
                    if let label = phoneNumber.label {
                        if label.contains("work") || label.contains("Work") {
                            phone = phoneNumber.value.stringValue
                            break
                        }
                    }
                }
            }
            
            // Fallback to home phone
            if phone == nil {
                for phoneNumber in contact.phoneNumbers {
                    if let label = phoneNumber.label {
                        if label.contains("home") || label.contains("Home") {
                            phone = phoneNumber.value.stringValue
                            break
                        }
                    }
                }
            }
            
            // Fallback to first phone
            if phone == nil {
                phone = contact.phoneNumbers.first?.value.stringValue
            }
            
            if let phone = phone, !phone.isEmpty {
                data["phone"] = phone
            }
        }
        
        // Address (prefer home, then work, then first available)
        if !contact.postalAddresses.isEmpty {
            var address: CNPostalAddress?
            
            // Look for home address first
            for postalAddress in contact.postalAddresses {
                if let label = postalAddress.label {
                    if label.contains("home") || label.contains("Home") {
                        address = postalAddress.value
                        break
                    }
                }
            }
            
            // Fallback to work address
            if address == nil {
                for postalAddress in contact.postalAddresses {
                    if let label = postalAddress.label {
                        if label.contains("work") || label.contains("Work") {
                            address = postalAddress.value
                            break
                        }
                    }
                }
            }
            
            // Fallback to first address
            if address == nil {
                address = contact.postalAddresses.first?.value
            }
            
            if let address = address {
                if !address.street.isEmpty {
                    // Split street into address lines
                    let streetLines = address.street.components(separatedBy: "\n")
                    if streetLines.count > 0 && !streetLines[0].isEmpty {
                        data["address1"] = streetLines[0]
                    }
                    if streetLines.count > 1 && !streetLines[1].isEmpty {
                        data["address2"] = streetLines[1]
                    }
                }
                
                if !address.city.isEmpty {
                    data["city"] = address.city
                }
                
                if !address.state.isEmpty {
                    data["state"] = address.state
                }
                
                if !address.postalCode.isEmpty {
                    data["zip"] = address.postalCode
                }
                
                if !address.country.isEmpty {
                    data["country"] = address.country
                }
            }
        }
        
        // Organization
        if !contact.organizationName.isEmpty {
            data["company"] = contact.organizationName
        }
        
        return data
    }
    
    // Score a contact based on how much useful information it contains
    private func scoreContact(_ contact: CNContact) -> Int {
        var score = 0
        
        if !contact.givenName.isEmpty { score += 2 }
        if !contact.familyName.isEmpty { score += 2 }
        if !contact.emailAddresses.isEmpty { score += 3 }
        if !contact.phoneNumbers.isEmpty { score += 2 }
        if !contact.postalAddresses.isEmpty { score += 3 }
        if !contact.organizationName.isEmpty { score += 1 }
        
        return score
    }
}
