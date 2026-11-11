# compare_0010_acl.py PRE POST
# Compares two 0006b_state_snapshot.sql outputs taken before and after 0010. Every 'table' line must match exactly once
# TRUNCATE grants to PUBLIC, anon and authenticated are removed from the PRE side. Anything else that differs fails.
import re
import sys

def table_lines(path):
    out = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.startswith("table "):
                continue
            _, name, acl = (line.split(" ", 2) + [""])[:3]
            out[name] = acl
    return out

def strip_truncate(acl):
    entries = [e for e in acl.split(",") if e and not re.match(r"^(PUBLIC|anon|authenticated)=TRUNCATE\*?$", e)]
    return ",".join(entries)

expected_removed = int(sys.argv[3]) if len(sys.argv) > 3 else None
pre = table_lines(sys.argv[1])
post = table_lines(sys.argv[2])
if set(pre) != set(post):
    sys.exit(f"table sets differ: only pre {sorted(set(pre) - set(post))}, only post {sorted(set(post) - set(pre))}")
bad = []
removed = 0
for name in sorted(pre):
    expected = strip_truncate(pre[name])
    if expected != post[name]:
        bad.append(f"{name}: expected [{expected}] got [{post[name]}]")
    if pre[name] != expected:
        removed += 1
if bad:
    sys.exit("ACL differences other than TRUNCATE:\n" + "\n".join(bad))
if expected_removed is not None and removed != expected_removed:
    sys.exit(f"expected TRUNCATE to be removed from {expected_removed} tables, saw {removed}")
print(f"passed: {len(pre)} tables; only TRUNCATE removed ({removed} tables had TRUNCATE entries)")
