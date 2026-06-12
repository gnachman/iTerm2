//
//  HTTPHelpers.swift
//  iTerm2
//
//  Created by George Nachman on 6/6/25.
//

/// Builds the multipart/form-data body for uploading a file along with any additional fields.
/// - Parameters:
///   - fileURL: Local file URL to upload.
///   - fieldName: The name of the form field for the file (e.g., "file").
///   - fileName: The filename to report in the upload (e.g., "document.txt").
///   - mimeType: The MIME type of the file (e.g., "text/plain").
///   - parameters: Any additional string fields to include in the form.
/// - Returns: A tuple containing the constructed body `Data` and the boundary string.
/// Builds the multipart/form-data body for uploading a file to OpenAI (vector store / assistants).
/// - Parameters:
///   - fileData: Raw bytes of the file to upload.
///   - fieldName: Must be "file" for OpenAI’s API.
///   - fileName: A descriptive name (e.g., "my_document.txt") to help identify the file later.
///   - mimeType: The true MIME type (e.g., "text/plain" or "application/pdf").
///   - parameters: Additional form fields (e.g., ["purpose":"assistants"]).
///   - boundary: A unique boundary string (e.g., "Boundary-<UUID>").
/// - Returns: The Data representing the full multipart body.
func createMultipartBody(
    fileData: Data,
    fieldName: String,
    fileName: String,
    mimeType: String,
    parameters: [String: String],
    boundary: String
) throws -> Data {
    var body = Data()

    // 1. Append text parameters (e.g., "purpose":"assistants")
    for (key, value) in parameters {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(value)\r\n".data(using: .utf8)!)
    }

    // 2. Append the file part with name="file"
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
    body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
    body.append(fileData)
    body.append("\r\n".data(using: .utf8)!)

    // 3. Close the multipart form
    body.append("--\(boundary)--\r\n".data(using: .utf8)!)

    return body
}

