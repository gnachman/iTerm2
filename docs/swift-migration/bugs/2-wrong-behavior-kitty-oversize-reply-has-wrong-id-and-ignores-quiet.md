# A kitty image too large to store is refused with a reply that names image 0 and ignores the quiet flag

**Where:** `sources/InlineImages/KittyImageController.swift`, `reallyExecuteTransmit(_:payload:query:preDecodedData:)` (the abandoned-transmission branch near line 444) and `respondToTransmit(_:display:error:)` (near line 1139).

**What happens:** when a chunked kitty graphics transmission grows past the size cap, the image is abandoned, later chunks are dropped, and an `ENOSPC` reply is sent when the final chunk arrives. That reply is built from the final chunk's own command. The protocol has clients send the image id only in the first chunk, and the quiet flag (`q=`) in later chunks only optionally, so the reply says `i=0`, and it is sent at normal verbosity unless the final chunk repeats `q=`. A client waiting for the reply to its image id never sees one, and a client that asked for no replies at all (`q=2`) gets one anyway, which a shell that is not expecting it shows as stray text at the prompt. Only images over the cap are affected.

**Why:** the branch that handles the final chunk of a discarded transmission returns the error, and `executeTransmit` replies with `modifiedCommand`, the final chunk's command. The first chunk's command, which has the id and verbosity, was dropped when the accumulator was cleared; only its identifier is kept, in `discardedTransmissionIdentifier`.

**How to see it:** send a chunked `a=t` transmission with `i=5,q=2` in the first chunk whose total size exceeds the cap, ending with a chunk that has only `m=0`. The reply is `ESC _ G i=0;ENOSPC:... ESC \`. Seen by reading the code; not run.

**Suggested fix:** keep the first chunk's transmission (its id, image number and verbosity) when abandoning it, and reply with that command for the final chunk.

**Found:** 2026-11-21, hardening of the kitty graphics protocol, and its review.

**Checked against the tree:** 2026-11-27. The branch still returns `dataTooLargeError` with only the identifier kept, and the reply still uses the final chunk's command.
