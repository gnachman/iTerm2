# Merges the OSC 7501 reports relay.py logged and the hook payloads rec logged into one timeline.
# Usage: timeline.py HH:MM:SS [DIR]   (events from that time on; DIR defaults to
# $CC_CAPTURE_DIR or ~/cc-status-capture). See README.md.
import json, os, sys
if len(sys.argv) < 2:
    sys.exit("usage: timeline.py HH:MM:SS [DIR]")
start = sys.argv[1]
directory = sys.argv[2] if len(sys.argv) > 2 else os.environ.get("CC_CAPTURE_DIR", os.path.expanduser("~/cc-status-capture"))
ev = []
for l in open(os.path.join(directory, "osc7501.log")):
    if l.startswith("==="): continue
    t, rest = l.split(" ", 1)
    ev.append((t, "OSC  " + rest.strip().replace("app->term 7501 ", "")))
for l in open(os.path.join(directory, "hooks.log")):
    l = l.strip()
    if not l: continue
    t, js = l.split(" ", 1)
    j = json.loads(js)
    bt = j.get("background_tasks")
    bts = "" if bt is None else " bg=" + str([(x.get("type"), x.get("status"), x.get("id", "")[:6]) for x in bt])
    who = " agent=" + j["agent_id"][:6] if j.get("agent_id") else ""
    extra = ""
    if j.get("notification_type"): extra += " ntype=" + j["notification_type"]
    if j.get("hook_event_name") in ("PermissionRequest", "Notification"): extra += " msg=%r" % (j.get("message") or (j.get("tool_input") or {}).get("command"))
    if j.get("source"): extra += " source=" + j["source"]
    ev.append((t, "HOOK %s %s%s%s%s" % (j.get("hook_event_name"), j.get("tool_name", ""), who, bts, extra)))
for t, s in sorted(ev):
    if t >= start: print(t, s[:230])
