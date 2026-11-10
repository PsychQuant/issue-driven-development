#!/usr/bin/env python3
"""A stand-in for idd-ci-gate.sh used by the close-stage suite.

Exit code from $FAKE_GH_DIR/ci-gate.rc (default 10: remote mode, so a scenario that says nothing about local CI
exercises the remote-check path as before). Prints RESULT=<name> like the real gate and logs the call to
calls.log as ["ci-gate", args...]. If $FAKE_GH_DIR/on-ci-gate.sh exists it is run once before answering.
"""
import json, os, sys
d = os.environ["FAKE_GH_DIR"]
with open(os.path.join(d, "calls.log"), "a") as fh:
    fh.write(json.dumps(["ci-gate"] + sys.argv[1:]) + "\n")
hook = os.path.join(d, "on-ci-gate.sh")   # runs once, while "CI runs": lets a scenario change what GitHub says meanwhile
if os.path.exists(hook):
    import subprocess
    os.rename(hook, hook + ".done")
    subprocess.run(["bash", hook + ".done"], capture_output=True)
p = os.path.join(d, "ci-gate.rc")
rc = int(open(p).read().strip()) if os.path.exists(p) else 10
names = {0: "pass", 1: "fail", 2: "timeout", 3: "not-configured", 4: "error", 10: "remote"}
print(f"RESULT={names.get(rc, 'unknown')}")
sys.exit(rc)
