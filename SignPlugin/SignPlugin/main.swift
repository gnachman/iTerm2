//
//  main.swift
//  SignPlugin
//
//  Created by George Nachman on 6/1/24.
//

import Foundation
import CryptoKit

var standardError = FileHandle.standardError

extension FileHandle: TextOutputStream {
  public func write(_ string: String) {
    let data = Data(string.utf8)
    self.write(data)
  }
}

struct PrivateKeys {
    var privateEdKey: Data?
    var publicEdKey: Data?
}

func sign(privateEdKey: Data, message: Data) {
    do {
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateEdKey)
        let signature = try privateKey.signature(for: message)
        print(signature.base64EncodedString())
    } catch {
        print(error, to: &standardError)
        exit(1)
    }
}

func generate() {
    let privateKey = Curve25519.Signing.PrivateKey()
    let publicKey = privateKey.publicKey
    print("public key:")
    print(publicKey.rawRepresentation.base64EncodedString())
    print("private key:")
    print(privateKey.rawRepresentation.base64EncodedString())
}

func verify(publicEdKey: Data, message: Data, signature: Data) {
    do {
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicEdKey)
        if publicKey.isValidSignature(signature, for: message) {
            print("Signature is valid")
            exit(0)
        }
        print("Signature invalid")
        exit(1)
    } catch {
        print("Invalid public key")
        exit(1)
    }
}

do {
    switch CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil {
    case "sign":
        guard CommandLine.arguments.count == 4 else {
            print("usage: SignPlugin sign privkey path", to: &standardError)
            exit(1)
        }
        guard let privateKey = Data(base64Encoded: CommandLine.arguments[2]) else {
            print("Malformed key", to: &standardError)
            exit(1)
        }
        let message = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
        sign(privateEdKey: privateKey, message: message)

    case "generate":
        guard CommandLine.arguments.count == 1 else {
            print("usage: SignPlugin generate", to: &standardError)
            exit(1)
        }
        generate()

    case "verify":
        guard CommandLine.arguments.count == 4 else {
            print("usage: SignPlugin verify pubkey signature msgpath", to: &standardError)
            exit(1)
        }
        guard let publicKey = Data(base64Encoded: CommandLine.arguments[2]) else {
            print("Malformed key", to: &standardError)
            exit(1)
        }
        guard let signature = Data(base64Encoded: CommandLine.arguments[3]) else {
            print("Malformed signature", to: &standardError)
            exit(1)
        }
        let message = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[4]))
        verify(publicEdKey: publicKey, message: message, signature: signature)

    default:
        print("Unrecognized command. Usage:", to: &standardError)
        print("  SignPlugin generate", to: &standardError)
        print("  SignPlugin sign privkey path", to: &standardError)
        print("  SignPlugin verify pubkey signature msgpath", to: &standardError)
        exit(1)
    }
} catch {
    print(error.localizedDescription, to: &standardError)
    exit(1)
}
