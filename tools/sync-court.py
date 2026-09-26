# -*- coding: utf-8 -*-
"""
Copy the court into Posted Up, or check that the two copies still match.

WHY THIS EXISTS. The court is one game in two mods -- Hoops on its own, and Posted Up with it
built in. Two hand-kept copies of the same game do not stay the same: one gets the fix, the
other gets the same bug reported a month later, and nobody can tell which is which by looking.

So src/Hoops/Court/ is the one source of truth, this copies it, and --check fails loudly when
the two have drifted. The rewrite is the namespace and nothing else -- the moment it needs to
be cleverer, they are not really the same game any more. Everything that DOES differ between
the mods goes through Court/CourtHost.cs, which each mod fills in as it starts.

    python tools/sync-court.py            copy the court -> hoodrich
    python tools/sync-court.py --check    report drift, change nothing (exit 1 if any)
"""
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FROM = os.path.join(HERE, "src", "Hoops", "Court")
TO = os.path.join(os.path.dirname(HERE), "hoodrich", "src", "Hoodrich", "Court")

RULES = [
    ("namespace Hoops.Court", "namespace Hoodrich.Court"),
]


def translate(text):
    for a, b in RULES:
        text = text.replace(a, b)
    return text


def leaks(text):
    """Code that names a mod: a using, or a namespace-qualified reference. The word in a log
    line or a comment is not a leak -- "Hoops:" is what both logs say -- and nor is the file's own
    namespace line, which the rules above just wrote."""
    text = "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("namespace "))
    found = re.findall(r"\busing\s+(?:Hoops|Hoodrich)\b[\w.]*|\b(?:Hoops|Hoodrich)\.(?:Core|UI|Court|Den|Locations)\b[\w.]*", text)
    return sorted(set(found))


def main():
    check = "--check" in sys.argv

    if not os.path.isdir(FROM):
        print("no court at " + FROM)
        return 1

    if not os.path.isdir(TO):
        if check:
            print("no copy at " + TO)
            return 1
        os.makedirs(TO)

    names = sorted(f for f in os.listdir(FROM) if f.endswith(".cs"))
    drift = 0
    wrote = 0
    leaked = 0

    for name in names:
        src = io.open(os.path.join(FROM, name), encoding="utf-8-sig").read()
        want = translate(src)

        left = leaks(want)
        if left:
            print("  LEAK  %-18s names %s -- the court must go through CourtHost" % (name, ", ".join(left)))
            leaked += 1
            continue

        dst = os.path.join(TO, name)
        have = io.open(dst, encoding="utf-8-sig").read() if os.path.exists(dst) else None

        if have == want:
            print("  same  " + name)
            continue

        drift += 1

        if check:
            print("  DIFF  " + name + ("" if have is not None else "  (missing there)"))
        else:
            io.open(dst, "w", encoding="utf-8-sig", newline="").write(want)
            print("  sync  " + name)
            wrote += 1

    # A file only Posted Up has is a fork starting. Said, never deleted: removing a file this
    # did not write is how a sync tool eats somebody's work.
    for extra in sorted(f for f in os.listdir(TO) if f.endswith(".cs") and f not in names):
        print("  ONLY  %-18s is in Posted Up's Court and not here -- move it here, or delete it there" % extra)
        drift += 1

    if leaked:
        print("%d file(s) not copied: they name a mod" % leaked)

    if check:
        print("in step" if drift == 0 and not leaked else "%d file(s) differ" % (drift + leaked))
        return 1 if drift or leaked else 0

    print("%d file(s) written" % wrote if wrote else "nothing to write")
    return 1 if leaked else 0


if __name__ == "__main__":
    sys.exit(main())
