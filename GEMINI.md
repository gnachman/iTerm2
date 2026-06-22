* when working on fixing a bug I tell you, please write a test that reproduces the problem first
* never declare success if you haven't actually run a test
* don't write tests that just codify your assumptions about the code, write tests that codify the behavior you want to see
* after you successfully fix something please make a commit
* if you modify a test after fixing or implementing, make note of that to me and what you changed and whether you might be compromsing the test's intent
* for something complicated that keeps failing, try going step by step. for applescript based tests in particular, you can run the applescript yourself dynamically step by step until you get a flow going and only then write the test
* also consider writing temporary "pathfinder" tests or features that try a bunch of stuff and report which of them worked and which one didn't and then use that output to write it again the way that worked
  ie if the code keeps failing, instead of going through the whole write, build, test, diagnose loop repeatedly, write some code that tries a bunch of different things verbosely so you compact that loop
  this goes for both tests and features
* similarly, whenever possible, try to investigate something dynamically yourself. if you can reach a certain step programmatically or dynamically and then interact with the program manually that's often much better than continually tearing down and rebuilding that state
* another technique for improving tests is to use the same basic framework for a test that you expect should work, and make sure that test works, and if not modify it until it does, and then use that same framework to test the other thing



an example response I gave to GEMINI on proposing a certain fix:
 > I'm happy to have you try this
   first commit whatever we have so it isn't all getting intermingled
   then try writing a pathfinder feature with verbose logging and built in assumption checking
   then test it dynamically yourself step by step in applescript, attempting to check your assumptions for each
   step,
   THEN write a test based on your dynamic manual testing, and run that test to confirm it works (ie fails the test condition but succeeds AS a test)
   THEN write the code, and run the test

* you yourself are running in a prod instance of iterm, so make sure you don't ever accidentally address or kill that one, you always need to ensure you are addressing the dev instance of iterm that you are running in your build folder
* remember that a pathfinder can and should contain multiple different attempts at doing something whenever you are having it do something you haven't succeeded with in the past
* whenever you are having a test output or use some dummy value to see if you can pick it up somewhere else, where appropriate try to have it be slightly unique each time so you don't get confused by previous runs of the same. (And obviously make your test record what value it should be outputting so you look for the right one). Where appropriate, clean it up afterwards so you don't leave a mess behind for the next test to get confused by.
  for example, don't name every new project E2E-test-project, dont have every terminal execute sleep 1001, etc

* if you have some kind of hook to run a pathfinder/experiment, prefer stashing it to removing it, so you can easily restore it later
* avoid overconfidence at the end of a session. Don't tell you me you 100% perfectly made everything work. Tell me what precisely you did and to what extent you verified it.
* don't confuse success at a single task (especially a meta-task like getting a test to run) with success at the one-level-higher goal (like in this example, having the test actually verify the behavior you want it to, and one level higher, actually implementing the behavior you want to see). Whenever you are tempted to declare utter success, besides for questioning whether you actually succeeded (as above), ask yourself what that narrow task was in service of.
* much of this critical thinking stuff becomes more relevant and applicable the more difficult something is to do. Failure itself is a good sign of something being difficult. It's ok to try to just bang out a feature once or twice. When you keep encountering failures, that's often a sign that the task itself is hard and you need to slow down and be more careful and methodical. Similarly, the more times you've mistakenly declared success, the more careful you need to be on epistemics.

Below are gemini's own words encapsulating its understanding of what I'm trying to get at:

  1. The Principle of Active Skepticism (Combating Confirmation Bias)
   * What I did wrong: I saw a window restore, printed a prompt, and immediately declared absolute, verified success
     because my code ran and didn't crash. I allowed the existence of the state to masquerade as the correctness of
     the state.
   * The Codified Lesson: Never assume a state transition succeeded just because the container arrived on screen.
     You must verify the qualitative physical behavior of that state. If a background process is supposed to be
     attached in the foreground, the terminal must be blocked. If it is active, you must be able to interact with
     it. Assume every success is a "false success" until you have actively tried to break it.

  2. The Adversarial Mindset in TDD
   * What I did wrong: I wrote unit tests that checked whether the _isArchive flag was set or whether the model
     saved the plist. I was testing the implementation details of my own design, rather than the physical
     system-level behaviors we actually wanted.
   * The Codified Lesson: TDD is not about asserting that your code does what you wrote it to do. It is about
     defining the physical behavior you want to see, and proving that it fails without your code and passes with it.
     A unit test that mocks out the entire OS-level behavior (like process reattachment) can pass perfectly while
     the real application is completely broken in production. Ground your tests in the physical boundaries of the
     system.

  3. The Pathfinder as a Multi-Hypothesis Laboratory
   * What I did wrong: I used the pathfinder simply as a passive logging checkpoint to print keys. I didn't use it
     to speculatively try multiple competing ideas at once.
   * The Codified Lesson: When a feature or attachment keeps failing, do not keep tweaking a single hypothesis in a
     write-compile-test loop. Use the Pathfinder as an active laboratory: write 3 or 4 completely different
     speculative approaches inside a diagnostic container, run them simultaneously on the same live state, and let
     the comparative output tell you which path actually works.