 There are actually two different high-priority paths:                                  
                                                                                                                      
  ┌─────────────────────────────────────────────────────────────────────────────────┐                                 
  │                           REGULAR TOKEN FLOW                                     │                                
  │                                                                                  │                                
  │  TaskNotifier Thread                                                             │                                
  │  ┌─────────────────┐                                                             │                                
  │  │ select() loop   │                                                             │                                
  │  │ detects FD      │                                                             │                                
  │  │ readable        │                                                             │                                
  │  └────────┬────────┘                                                             │                                
  │           │                                                                      │                                
  │           ▼                                                                      │                                
  │  ┌─────────────────┐                                                             │                                
  │  │ PTYTask         │                                                             │                                
  │  │ .processRead()  │                                                             │                                
  │  │ reads bytes     │                                                             │                                
  │  └────────┬────────┘                                                             │                                
  │           │                                                                      │                                
  │           ▼                                                                      │                                
  │  ┌─────────────────┐                                                             │                                
  │  │ VT100ScreenMutableState                                                       │                                
  │  │ .threadedReadTask:length:                                                     │                                
  │  │ parses → tokens │                                                             │                                
  │  └────────┬────────┘                                                             │                                
  │           │                                                                      │                                
  │           ▼                                                                      │                                
  │  ┌─────────────────┐                                                             │                                
  │  │ addTokens:      │                                                             │                                
  │  │ highPriority:NO │                                                             │                                
  │  └────────┬────────┘                                                             │                                
  │           │                                                                      │                                
  │           ▼                                                                      │                                
  │  ┌─────────────────────────────────────┐                                         │                                
  │  │ TokenExecutor.addTokens()           │                                         │                                
  │  │                                     │                                         │                                
  │  │  semaphore.wait() ◄─── BLOCKS HERE  │                                         │                                
  │  │  if queue full                      │                                         │                                
  │  │                                     │                                         │                                
  │  │  reallyAddTokens()                  │                                         │                                
  │  │    → tokenQueue.queues[1].append()  │ ◄─── QUEUE 1 (normal priority)          │                                
  │  │                                     │                                         │                                
  │  │  queue.async { didAddTokens() }     │ ◄─── Schedules execution on             │                                
  │  └─────────────────────────────────────┘      mutation queue                     │                                
  │                                                                                  │                                
  └─────────────────────────────────────────────────────────────────────────────────┘                                 
                                                                                                                      
                                                                                                                      
  ┌─────────────────────────────────────────────────────────────────────────────────┐                                 
  │                     HIGH-PRIORITY FLOW #1: External (API/Startup)                │                                
  │                                                                                  │                                
  │  Any Thread (Main, API socket, etc.)                                             │                                
  │  ┌─────────────────┐                                                             │                                
  │  │ iTermAPIHelper  │    OR    ┌─────────────────┐                                │                                
  │  │ .inject:into:   │          │ iTermController │                                │                                
  │  └────────┬────────┘          │ (startup)       │                                │                                
  │           │                   └────────┬────────┘                                │                                
  │           └───────────┬────────────────┘                                         │                                
  │                       ▼                                                          │                                
  │              ┌─────────────────┐                                                 │                                
  │              │ PTYSession      │                                                 │                                
  │              │ .injectData:    │                                                 │                                
  │              └────────┬────────┘                                                 │                                
  │                       ▼                                                          │                                
  │              ┌─────────────────┐                                                 │                                
  │              │ VT100Screen     │                                                 │                                
  │              │ .injectData:    │                                                 │                                
  │              └────────┬────────┘                                                 │                                
  │                       │                                                          │                                
  │                       ▼                                                          │                                
  │  ┌─────────────────────────────────────────────────────────────┐                 │                                
  │  │ mutateAsynchronously: { mutableState.injectData: }          │                 │                                
  │  │                                                             │                 │                                
  │  │ Dispatches block to MUTATION QUEUE                          │                 │                                
  │  └─────────────────────────────────────────────────────────────┘                 │                                
  │                       │                                                          │                                
  │                       ▼                                                          │                                
  │                                                                                  │                                
  │  ════════════════ MUTATION QUEUE ════════════════════════════                    │                                
  │                                                                                  │                                
  │              ┌─────────────────┐                                                 │                                
  │              │ VT100ScreenMutableState                                           │                                
  │              │ .injectData:    │                                                 │                                
  │              │ parses → tokens │                                                 │                                
  │              └────────┬────────┘                                                 │                                
  │                       ▼                                                          │                                
  │              ┌─────────────────┐                                                 │                                
  │              │ addTokens:      │                                                 │                                
  │              │ highPriority:YES│                                                 │                                
  │              └────────┬────────┘                                                 │                                
  │                       ▼                                                          │                                
  │  ┌─────────────────────────────────────┐                                         │                                
  │  │ TokenExecutor.addTokens()           │                                         │                                
  │  │                                     │                                         │                                
  │  │  (NO semaphore wait)                │ ◄─── Does NOT block                     │                                
  │  │                                     │                                         │                                
  │  │  reallyAddTokens()                  │                                         │                                
  │  │    → tokenQueue.queues[0].append()  │ ◄─── QUEUE 0 (high priority)            │                                
  │  │                                     │                                         │                                
  │  │  return (no queue.async!)           │ ◄─── Does NOT schedule execution        │                                
  │  └─────────────────────────────────────┘                                         │                                
  │                                                                                  │                                
  │  Tokens sit in queue[0] until something else triggers execute()                  │                                
  │                                                                                  │                                
  └─────────────────────────────────────────────────────────────────────────────────┘                                 
                                                                                                                      
                                                                                                                      
  ┌─────────────────────────────────────────────────────────────────────────────────┐                                 
  │              HIGH-PRIORITY FLOW #2: Trigger (during token execution)             │                                
  │                                                                                  │                                
  │  ════════════════ ALREADY ON MUTATION QUEUE ═══════════════════                  │                                
  │                                                                                  │                                
  │  ┌─────────────────────────────────────────────────┐                             │                                
  │  │ TokenExecutor.execute()                         │                             │                                
  │  │   └─► executeTokenGroups()                      │                             │                                
  │  │         └─► VT100Terminal.execute(token)        │                             │                                
  │  │               └─► trigger fires                 │                             │                                
  │  │                     └─► InjectTrigger           │                             │                                
  │  └──────────────────────────┬──────────────────────┘                             │                                
  │                             │                                                    │                                
  │                             ▼                                                    │                                
  │              ┌─────────────────────────────┐                                     │                                
  │              │ triggerSession:injectData:  │                                     │                                
  │              │ (VT100ScreenMutableState)   │                                     │                                
  │              └──────────────┬──────────────┘                                     │                                
  │                             │                                                    │                                
  │                             ▼                                                    │                                
  │              ┌─────────────────┐                                                 │                                
  │              │ VT100ScreenMutableState                                           │                                
  │              │ .injectData:    │  ◄─── Called DIRECTLY (no mutateAsynchronously) │                                
  │              │ parses → tokens │                                                 │                                
  │              └────────┬────────┘                                                 │                                
  │                       ▼                                                          │                                
  │              ┌─────────────────┐                                                 │                                
  │              │ addTokens:      │                                                 │                                
  │              │ highPriority:YES│                                                 │                                
  │              └────────┬────────┘                                                 │                                
  │                       ▼                                                          │                                
  │  ┌─────────────────────────────────────┐                                         │                                
  │  │ TokenExecutor.addTokens()           │                                         │                                
  │  │                                     │                                         │                                
  │  │  (NO semaphore wait)                │                                         │                                
  │  │                                     │                                         │                                
  │  │  reallyAddTokens()                  │                                         │                                
  │  │    → tokenQueue.queues[0].append()  │ ◄─── QUEUE 0 (high priority)            │                                
  │  │                                     │                                         │                                
  │  │  return                             │                                         │                                
  │  └─────────────────────────────────────┘                                         │                                
  │                             │                                                    │                                
  │                             │ Returns to...                                      │                                
  │                             ▼                                                    │                                
  │  ┌─────────────────────────────────────────────────┐                             │                                
  │  │ ...executeTokenGroups() continues               │                             │                                
  │  │                                                 │                             │                                
  │  │ Next iteration of enumerateTokenArrayGroups     │                             │                                
  │  │ will pull from queue[0] FIRST (high priority)   │                             │                                
  │  │ before continuing with queue[1]                 │                             │                                
  │  └─────────────────────────────────────────────────┘                             │                                
  │                                                                                  │                                
  └─────────────────────────────────────────────────────────────────────────────────┘                                 
                                                                                                                      
                                                                                                                      
  ┌─────────────────────────────────────────────────────────────────────────────────┐                                 
  │                              EXECUTION (Consumption)                             │                                
  │                                                                                  │                                
  │  ════════════════ MUTATION QUEUE ═══════════════════════════════                 │                                
  │                                                                                  │                                
  │  ┌─────────────────────────────────────────────────────────────┐                 │                                
  │  │ TokenExecutorImpl.execute()                                 │                 │                                
  │  │                                                             │                 │                                
  │  │   tokenQueue.enumerateTokenArrayGroups { group, priority    │                 │                                
  │  │                                                             │                 │                                
  │  │     nextQueueAndTokenArrayGroup:                            │                 │                                
  │  │       for i in [0, 1]:           ◄─── Checks queue[0] FIRST │                 │                                
  │  │         if queues[i].firstGroup:                            │                 │                                
  │  │           return it                                         │                 │                                
  │  │                                                             │                 │                                
  │  │     executeTokenGroups(group, priority)                     │                 │                                
  │  │       for each token:                                       │                 │                                
  │  │         terminal.execute(token)                             │                 │                                
  │  │         (triggers may fire here → re-entrant injection)     │                 │                                
  │  │   }                                                         │                 │                                
  │  └─────────────────────────────────────────────────────────────┘                 │                                
  │                                                                                  │                                
  └─────────────────────────────────────────────────────────────────────────────────┘                                 
                                                                                                                      
  Key Observations                                                                                                    
                                                                                                                      
  1. Regular tokens (PTY): Block on semaphore, go to queue[1], trigger async execution                                
  2. External high-priority (API/startup): No semaphore, go to queue[0], but don't trigger execution - they wait for  
  something else to call execute()                                                                                    
  3. Trigger high-priority: No semaphore, go to queue[0], execution continues immediately in the same call stack      
  (re-entrant)                                                                                                        
  4. Consumption: Always drains queue[0] completely before touching queue[1]  
