//
//  MockTokenExecutorDelegate.swift
//  ModernTests
//
//  NOTE: The actual MockTokenExecutorDelegate implementation is defined in:
//  ModernTests/FairnessScheduler/TokenExecutorFairnessTests.swift
//
//  This file is intentionally empty. The mock is co-located with its tests
//  in TokenExecutorFairnessTests.swift for better locality and maintainability.
//
//  The mock implements TokenExecutorDelegate with:
//  - shouldQueueTokens/shouldDiscardTokens flags
//  - executedLengths tracking
//  - syncCount and willExecuteCount counters
//  - onWillExecute callback for expectations
//  - reset() method for test cleanup
//

import Foundation

// See TokenExecutorFairnessTests.swift for the MockTokenExecutorDelegate implementation.
