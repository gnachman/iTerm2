//
//  SpikeCredentialExport.swift
//  iTerm2 Companion
//
//  REMOVED. This memory-spike scaffolding wrote the Noise static private key,
//  the room secret, and the pairing code into the shared App Group container so
//  the spike NSE could read them. The memory gate is passed (docs/push.txt
//  Verification gate 0), so the export and all of its call sites are deleted.
//
//  The real feature shares these credentials via a keychain access group
//  (docs/push.txt section 7) - never a plaintext container file. This file is
//  now empty; remove it from the Xcode project (right-click -> Delete) at your
//  convenience.
//
