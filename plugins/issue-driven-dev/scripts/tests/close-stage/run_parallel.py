#!/usr/bin/env python3
"""Run scenarios.sh's scenarios in parallel (#392): each one builds its own throwaway repositories.

Top-level function definitions and the lines before the first scenario form the
prelude; each scenario (a line starting one, or a `for` loop) runs in its own
bash with the prelude in front and its own $WORK. A block that dies before its
summary counts as a failure, so a crash cannot read as a pass.
"""
import concurrent.futures as cf, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
START = re.compile(r"^(pr_scenario|direct_scenario|wf_scenario|new_scenario|for )\b")
FUNC = re.compile(r"^\w+\(\) *\{")

def split(lines):
    prelude, blocks, i = [], [], 0
    while i < len(lines):
        start, line = i, lines[i]
        doc = re.search(r"<<'?(\w+)'?\s*$", line)
        if FUNC.match(line) and not line.rstrip().endswith("}"):
            while lines[i].rstrip() != "}":
                i += 1
        elif doc:
            while lines[i + 1].strip() != doc.group(1):
                i += 1
            i += 1
        elif line.startswith("for "):
            while not lines[i].startswith("done"):
                i += 1
        chunk = lines[start:i + 1]
        i += 1
        if FUNC.match(line):
            prelude += chunk
        elif START.match(line):
            blocks.append(list(chunk))
        elif blocks:
            blocks[-1] += chunk
        else:
            prelude += chunk
    return prelude, blocks

def run(prelude, block):
    src = "\n".join(prelude + block + ['print_summary block'])
    p = subprocess.run(["bash", "-c", src, os.path.join(HERE, "scenarios.sh")], capture_output=True, text=True,
                       stdin=subprocess.DEVNULL)
    return p.stdout + p.stderr, p.returncode

def main():
    lines = [l for l in open(os.path.join(HERE, "scenarios.sh")).read().splitlines()
             if not l.startswith("print_summary") and not re.match(r'^echo "close-stage:', l)]
    prelude, blocks = split(lines)
    jobs = int(os.environ.get("IDD_TEST_JOBS") or os.cpu_count() or 4)
    passed = failed = 0
    with cf.ThreadPoolExecutor(jobs) as ex:
        for out, rc in ex.map(lambda b: run(prelude, b), blocks):
            m = re.search(r"PASS: (\d+)\nFAIL: (\d+)", out)
            if not m:
                failed += 1
                print("  ✗ a scenario died before its summary\n" + out[-800:])
                continue
            passed += int(m.group(1)); failed += int(m.group(2))
            if int(m.group(2)) or rc:
                print(out)
    print(f"\n─── close-stage ({len(blocks)} scenarios, {jobs} jobs) ───\nPASS: {passed}\nFAIL: {failed}")
    return 1 if failed else 0

sys.exit(main())
