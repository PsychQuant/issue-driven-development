#!/usr/bin/env python3
"""Exhaustive checks of the two tables in rest-queue.py (#478): argument forms and issue classes.

Each table is stated a second time here, independently, and compared with the helper over every
combination of a small world. Prints one line per failure; exit 0 only when there is none.
"""
import importlib.util
import itertools
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = importlib.util.spec_from_file_location("rest_queue", os.path.join(HERE, "..", "..", "rest-queue.py"))
rq = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(rq)

failures, checks = [], 0


def check(name, expected, actual):
    global checks
    checks += 1
    if expected != actual:
        failures.append(f"{name}: expected {expected!r}, got {actual!r}")


# spec-example: idd-all-rest / argument forms
ARG_ROWS = [
    ([], "rest"),
    (["rest"], "rest"),
    (["--pr"], "rest"),
    (["--review", "--cwd", "/tmp/x"], "rest"),
    (["rest", "--no-pr"], "rest"),
    (["rest", "#12"], "refuse"),
    (["#12", "rest"], "refuse"),
    (["--in-chain"], "refuse"),
    (["rest", "--in-chain"], "refuse"),
    (["--reveiw"], "refuse"),
    (["--cwd"], "refuse"),
    (["#12"], "other"),
    (["#12", "#13"], "other"),
    (["Rest"], "other"),
    (["rest in peace"], "other"),
    (["#12", "--in-chain"], "other"),
]
for argv, mode in ARG_ROWS:
    got, reason = rq.classify_args(argv)
    check(f"args {argv}", mode, got)
    check(f"args {argv} has a reason only when refused", mode == "refuse", bool(reason))

# The value of --cwd is never a positional argument, whatever it looks like.
for argv, mode in [(["--cwd", "rest"], "rest"), (["--cwd=rest"], "rest"), (["--cwd", "--pr"], "refuse"),
                   (["--cwd="], "refuse"), (["--cwd", "x", "#12"], "other")]:
    check(f"args {argv}", mode, rq.classify_args(argv)[0])


def args_oracle(positionals, flags, unknown):
    if unknown:
        return "refuse"
    if len(positionals) >= 2 and "rest" in positionals:
        return "refuse"
    if not positionals or positionals == ["rest"]:
        return "refuse" if "--in-chain" in flags else "rest"
    return "other"


WORDS = ["rest", "#12", "some text"]
FLAGS = ["--pr", "--no-pr", "--review", "--in-chain", "--cwd"]
for k in range(3):
    for positionals in itertools.product(WORDS, repeat=k):
        for r in range(len(FLAGS) + 1):
            for flags in itertools.combinations(FLAGS, r):
                for unknown in (False, True):
                    tokens = []
                    for f in flags:
                        tokens += [f, "/tmp/x"] if f == "--cwd" else [f]
                    if unknown:
                        tokens.append("--bogus")
                    expected = args_oracle(list(positionals), flags, unknown)
                    for argv in (list(positionals) + tokens, tokens + list(positionals)):
                        got = rq.classify_args(argv)[0]
                        check(f"args small world {argv}", expected, got)
                        if got == "rest":   # the property the mode exists for
                            check(f"rest implies no other positional {argv}", True, set(positionals) <= {"rest"})

# spec-example: idd-all-rest / class precedence
YES, NO = True, False
CLASS_ROWS = [
    # author writes, editor writes, commenters write, tracker, readable, open clarity, gate group, meeting, verified → class
    (NO, YES, YES, NO, YES, NO, "actionable", NO, NO, "outsider"),
    (YES, NO, YES, NO, YES, NO, "actionable", NO, NO, "outsider"),
    (YES, YES, NO, NO, YES, NO, "actionable", NO, NO, "outsider"),
    (NO, YES, YES, YES, YES, YES, "parked", NO, YES, "outsider"),
    (NO, YES, YES, NO, NO, NO, "actionable", NO, NO, "outsider"),
    (YES, YES, YES, YES, YES, YES, "blocked", NO, NO, "tracker"),
    (YES, YES, YES, YES, NO, NO, "actionable", NO, NO, "tracker"),
    (YES, YES, YES, NO, NO, NO, "actionable", NO, NO, "unreadable"),
    (YES, YES, YES, NO, NO, NO, "blocked", YES, NO, "unreadable"),
    (YES, YES, YES, NO, YES, YES, "blocked", NO, YES, "needs-person"),
    (YES, YES, YES, NO, YES, NO, "parked", YES, YES, "parked"),
    (YES, YES, YES, NO, YES, NO, "blocked", NO, YES, "blocked"),
    (YES, YES, YES, NO, YES, NO, "actionable", YES, YES, "meeting"),
    (YES, YES, YES, NO, YES, NO, "actionable", NO, YES, "verified"),
    (YES, YES, YES, NO, YES, NO, "actionable", NO, NO, "candidate"),
    (YES, YES, YES, NO, YES, NO, "undiagnosed", NO, NO, "candidate"),
]
KEYS = ("author_writes", "editor_writes", "commenters_write", "tracker", "readable", "open_clarity", "group", "meeting",
        "verified")


def classify(facts):
    """rq.classify, or the name of the exception: a table that does not know an input fails the check, not the run."""
    try:
        return rq.classify(facts)
    except Exception as exc:
        return f"<{type(exc).__name__}>"


for row in CLASS_ROWS:
    check(f"class {row[:-1]}", row[-1], classify(dict(zip(KEYS, row[:-1]))))


def class_oracle(f):
    if not f["author_writes"] or not f["editor_writes"] or not f["commenters_write"]:
        return "outsider"
    if f["tracker"]:
        return "tracker"
    if not f["readable"]:
        return "unreadable"
    if f["open_clarity"]:
        return "needs-person"
    if f["group"] == "parked":
        return "parked"
    if f["group"] == "blocked":
        return "blocked"
    if f["meeting"]:
        return "meeting"
    if f["verified"]:
        return "verified"
    return "candidate"


EXPECTED_CLASSES = ("outsider", "tracker", "unreadable", "needs-person", "parked", "blocked", "meeting", "verified",
                    "candidate")
check("the table lists the nine classes in order", EXPECTED_CLASSES, tuple(name for name, _ in rq.TABLE))
check("CLASSES matches the table", EXPECTED_CLASSES, tuple(rq.CLASSES))
check("every class has a label", set(EXPECTED_CLASSES), set(rq.LABELS))
combos = 0
for values in itertools.product((YES, NO), (YES, NO), (YES, NO), (YES, NO), (YES, NO), (YES, NO),
                                ("actionable", "parked", "blocked", "undiagnosed"), (YES, NO), (YES, NO)):
    facts = dict(zip(KEYS, values))
    combos += 1
    got = classify(facts)
    check(f"class of {values}", class_oracle(facts), got)
    check(f"exactly one rule decides {values}", True, got in EXPECTED_CLASSES)
    # only a candidate is run, and a candidate has none of the reasons to hold it back
    if got == "candidate":
        check(f"candidate has no hold-back {values}", True,
              facts["author_writes"] and facts["editor_writes"] and facts["commenters_write"]
              and not facts["tracker"] and facts["readable"] and not facts["open_clarity"]
              and facts["group"] in ("actionable", "undiagnosed") and not facts["meeting"] and not facts["verified"])
check("1024 combinations were checked", 1024, combos)

for line in failures:
    print("FAIL " + line)
print(f"tables_check: {checks} checks, {len(failures)} failed")
sys.exit(1 if failures else 0)
