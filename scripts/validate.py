#!/usr/bin/env python3
"""Repo consistency check. Standard library only; run before push.

    python scripts/validate.py          check everything, change nothing
    python scripts/validate.py --fix    put right what can be put right, then check

Every tool folder is checked against the rules the updater block relies on at
runtime. The one that bites hardest is version drift: if manifest.json says
1.2.0 while tool.lua still says TOOL_VERSION = "1.1.0", every client downloads
the payload on every single load, forever, and throws it away at the last gate.
Nothing in game reports that. This does.

--fix is the drop-in path: put a folder under tools/ holding the object script
as tool.lua and a manifest.json beside it, run it, and the folder is a
publishable tool. It pastes updater/updater.lua onto the end of the script,
fills the config in from the folder name and the manifest, and re-pastes the
block over any copy that has drifted. It never touches the code above the
block, and it never decides a version: the manifest says what is
published, and tool.lua is made to agree with it.

A tool that also has an XML UI authors it as tool.xml in the same folder. That
file is not published - --fix splices it into tool.lua as a Lua long string,
and the block applies it at load - so what is checked here is that the spliced
copy is still the file beside it. Nothing fetches tool.xml, so a tool is one
file and an update cannot land half of one.
"""

import argparse
import difflib
import json
import re
import sys

from block import (SEMVER, TOOLS, UPDATER, BlockError, block_of, canonical,
                   head_of, literal, signature_for, stamp, stamp_xml,
                   without_config, write, xml_comment, xml_of)

# Release notes land in everyone's chat window at once, so they are held to a
# size. None of these are enforced in game - the block prints whatever it is
# given - which is exactly why the checks belong here, before the push.
# MAX_CATCHUP bounds the worst case: the oldest copy still out there wakes up
# and is told about every release it missed, all in one message.
# The only three lines in the block allowed to say "Global." at all: read
# the latch, write it, and drop the last asking's answer when a check starts.
GLOBAL_CALLS = (
    "Global.getVar(key)",
    "Global.setVar(key, value)",
    'Global.setVar(GLOBAL_KEY .. "_ANSWER", "")',
)

MAX_NOTES = 6
MAX_NOTE_CHARS = 160
MAX_CATCHUP = 24

problems = []


def fail(where, message, detail=None):
    problems.append((where, message, detail))


def rank(version):
    """Comparable form of a plain X.Y.Z, matching what the block does."""
    return tuple(int(part) for part in version.split("."))


def check_one_write(where, text):
    """The block's safety story in one line: one script write, and it is on self.

    Counted inside the block only. A tool writing scripts onto other objects -
    the importer handing every fighter its card - is the tool's own business
    and never blocked here; what is enforced is that the updater itself
    rewrites nothing but the object it lives on.
    """
    block = block_of(text) or text
    writes = [ln.strip() for ln in block.splitlines() if "setLuaScript" in ln]
    if len(writes) != 1:
        fail(where, "expected exactly 1 script write in the block, found %d"
             % len(writes), "\n".join("  " + w for w in writes))
    elif not re.search(r"\bself\.setLuaScript\s*\(", writes[0]):
        fail(where, "the block's script write does not target self",
             "  " + writes[0])

    # The UI write gets the same treatment, and for the same reason: it is
    # the line that applies the spliced layout at load. A tool driving its own
    # XML at runtime as well is ordinary and harmless.
    ui = [ln.strip() for ln in block.splitlines() if "UI.setXml(" in ln]
    if len(ui) != 1:
        fail(where, "expected exactly 1 UI write in the block, found %d" % len(ui),
             "\n".join("  " + u for u in ui))
    elif not re.search(r"\bself\.UI\.setXml\s*\(", ui[0]):
        fail(where, "the UI write does not target self", "  " + ui[0])

    # Global is touched for one thing: the latch that stops three copies of a
    # tool saying the same thing three times. Docs tell a suspicious mod author
    # to grep for it, so these are the only three lines that grep may find.
    uses = [ln.strip() for ln in block.splitlines()
            if "Global." in ln and not ln.strip().startswith("--")]
    stray = [u for u in uses if not any(a in u for a in GLOBAL_CALLS)]
    if stray or len(uses) > len(GLOBAL_CALLS):
        fail(where, "Global is only ever reached by the announce latch, on a "
                    "key built from the tool id",
             "\n".join("  " + u for u in uses))


def check_switch(where, text):
    """SELF_UPDATE is the one opt-out, and it ships as true.

    A published file with it set to false would install a dead updater on
    everyone who takes the update, and nothing in game would say why.
    """
    if re.search(r"^--\s*validate:\s*SELF_UPDATE=false is intentional\b", text, re.M):
        return   # fork exception: the file says so itself, in a reviewable line
    if not re.search(r"^local\s+SELF_UPDATE\s*=\s*true\b", text, re.M):
        fail(where, "SELF_UPDATE is not `true`, so every copy of this file "
                    "would stop updating for good",
             "  it is the switch a player flips in their own copy, never here")


def check_block_matches(where, text, canonical):
    embedded = block_of(text)
    if embedded is None:
        return fail(where, "carries no updater block (searched for its header)")
    mine = without_config(embedded).splitlines()
    theirs = without_config(canonical).splitlines()
    if mine != theirs:
        diff = list(difflib.unified_diff(theirs, mine, "updater/updater.lua",
                                         str(where), lineterm="", n=1))
        fail(where, "embedded block has drifted from updater/updater.lua",
             "\n".join("  " + d for d in diff[:24]))


def as_list(notes):
    """A notes field as the list of bullets it renders to, same as the block."""
    if isinstance(notes, str):
        return [notes]
    return notes if isinstance(notes, list) else []


def check_notes(where, entry):
    """Release notes: one string, or a list of them, one bullet per entry.

    A version with nothing to say about itself still updates fine, so this is
    the only rule here that is a house style rather than a runtime concern -
    the point of the whole feature is that players are told what changed.
    """
    notes = entry.get("notes")
    if isinstance(notes, str):
        notes = [notes]
    if notes is None:
        return fail(where, "no release notes, so an update announces a bare "
                           "version number and nothing else",
                    '  add "notes": ["what changed"] beside the version')
    if not isinstance(notes, list) or not all(isinstance(n, str) for n in notes):
        return fail(where, 'notes must be a string, or a list of strings for a '
                           'bulleted list')
    if not notes or any(not n.strip() for n in notes):
        return fail(where, "empty release note")
    if len(notes) > MAX_NOTES:
        fail(where, "%d release notes; more than %d fills the chat window on "
                    "every client at once" % (len(notes), MAX_NOTES))
    long = [n for n in notes if len(n) > MAX_NOTE_CHARS]
    if long:
        fail(where, "release note over %d characters, which wraps badly in TTS "
                    "chat" % MAX_NOTE_CHARS,
             "\n".join("  %s..." % n[:60] for n in long))
    return None


def check_history(where, manifest, current):
    """Past releases, newest first, every one of them older than the current.

    Optional: a tool with no history simply announces the release it is on.
    With one, a copy that skipped versions is caught up on all of them, so
    the order here is the order players read - the block trusts this list
    rather than sorting it.
    """
    history = manifest.get("history")
    if history is None:
        return None
    if not isinstance(history, list) or not all(isinstance(h, dict) for h in history):
        return fail(where, '"history" must be a list of past releases, each '
                           'shaped like the "stable" entry')

    ranks = []
    for entry in history:
        version = entry.get("version")
        if not isinstance(version, str) or not SEMVER.match(version):
            fail(where, "history version %r is not plain X.Y.Z, so the block "
                        "sorts it below everything" % (version,))
            continue
        ranks.append((rank(version), version))
        check_notes(where, entry)

    ordered = [r for r, _ in ranks]
    if ordered != sorted(set(ordered), reverse=True):
        fail(where, "history must run newest first with no repeats",
             "  found: " + ", ".join(v for _, v in ranks))
    stale = [v for r, v in ranks if r >= rank(current)]
    if stale:
        fail(where, "history holds v%s, which is not older than the published "
                    "v%s. Move the outgoing release into history on a bump, "
                    "not the incoming one." % (stale[0], current))

    total = sum(len(as_list(e.get("notes"))) for e in [manifest["stable"]] + history)
    if total > MAX_CATCHUP:
        fail(where, "%d notes across every published release; a copy old enough "
                    "to have missed all of them would be shown the lot in one "
                    "chat message. Trim the tail of history - nobody needs the "
                    "v1.0.1 line two years on." % total)
    return None


def check_ui(where, path, tool_id):
    """A tool's tool.xml, which is source rather than something published.

    There is no version in here and nothing to keep in step with the manifest,
    and no client ever downloads it: it is spliced into tool.lua, and
    check_payload is where that copy is held to the file. What is left is
    whether the thing being spliced is a layout at all.
    """
    text = path.read_text(encoding="utf-8")
    if not text.strip():
        return fail(where, "is empty, so the tool would splice in no layout")
    if signature_for(tool_id) not in text:
        fail(where, "carries no signature saying which tool it belongs to",
             "  put %s on the first line, or run: python scripts/validate.py "
             "--fix" % xml_comment(tool_id))
    if not text.lstrip().startswith("<"):
        fail(where, "does not start with a tag or a comment, so it is not the "
                    "XML that UI.setXml expects")
    return None


def check_payload(where, path, published, tool_id, repo_base, canonical):
    """A tool's tool.lua against the version its manifest publishes."""
    text = path.read_text(encoding="utf-8")

    declared = literal(text, "TOOL_VERSION")
    if declared != published:
        fail(where, "version drift, so every client re-downloads on every load",
             "  manifest.json  version      = %r\n"
             "  %-14s TOOL_VERSION = %r" % (published, path.name, declared))

    if literal(text, "TOOL_ID") != tool_id:
        fail(where, "TOOL_ID does not match the folder name, so this tool would "
                    "fetch someone else's payload",
             "  folder = %r, TOOL_ID = %r" % (tool_id, literal(text, "TOOL_ID")))

    signature = literal(text, "TOOL_SIGNATURE")
    if not signature:
        fail(where, "no TOOL_SIGNATURE literal")
    elif signature not in text:
        fail(where, "does not contain its own signature %r" % signature)

    # Not a runtime gate. The block brings an onLoad of its own, so a tool
    # without one loads and updates perfectly well - it simply never sets
    # anything up, which is a mistake far more often than it is a decision,
    # and nothing in game would say so.
    if "function onLoad" not in head_of(text):
        fail(where, "defines no onLoad, so nothing in the tool runs when the "
                    "object loads",
             "  the block supplies one for the layout, but it calls nothing")

    # The whole of publishing a UI now: the layout inside the file has to be
    # the file beside it. A stale splice is the drift version drift used to
    # be - it installs cleanly, looks fine, and shows the wrong layout.
    xml = path.parent / "tool.xml"
    spliced = xml_of(text)
    if xml.exists():
        wanted = xml.read_text(encoding="utf-8").rstrip("\n") + "\n"
        if spliced is None:
            fail(where, "tool.xml is here but no layout is spliced into this "
                        "file, so the tool would load with no UI",
                 "  run: python scripts/validate.py --fix")
        elif spliced != wanted:
            fail(where, "the spliced layout is not what tool.xml says",
                 "  the object would show a stale UI. Run: python "
                 "scripts/validate.py --fix")
    elif spliced is not None:
        fail(where, "splices a layout that has no tool.xml beside it",
             "  nothing can edit or review it. Restore the file, or drop the "
             "TOOL_XML literal.")

    minimum = int(literal(text, "MIN_BYTES") or 0)
    size = len(text.encode("utf-8"))
    if size <= minimum:
        fail(where, "%d bytes, at or under its own MIN_BYTES gate of %d, so "
                    "clients would reject it" % (size, minimum))

    if literal(text, "REPO_BASE") != repo_base:
        fail(where, "REPO_BASE differs from updater/updater.lua, so this file "
                    "updates from a different repository",
             "  updater/updater.lua = %r\n  %-19s = %r"
             % (repo_base, path.name, literal(text, "REPO_BASE")))

    check_block_matches(where, text, canonical)
    check_one_write(where, text)
    check_switch(where, text)


def repair_ui(xml, tool_id):
    """Stamp an XML UI with the signature, if there is one. LF, as ever.

    The counterpart to what stamp() does to the script: the only edit is the
    signature comment on the first line, and a file already carrying the right
    one comes back untouched.
    """
    if not xml.exists():
        return []
    text = xml.read_text(encoding="utf-8")
    fixed = stamp_xml(text, tool_id)
    if fixed == text:
        return []
    write(xml, fixed)
    return ["stamped %s with %s" % (xml.name, xml_comment(tool_id))]


def retire_xml_flag(manifest_path, manifest):
    """Drop the old "xml": true, which no longer means anything.

    It used to be what made a client fetch tool.xml as a second request. There
    is no second request now, and leaving the flag in would have old copies
    still asking for a file whose contents they already have in the payload.
    """
    if "xml" not in manifest.get("stable", {}):
        return []
    del manifest["stable"]["xml"]
    write(manifest_path, json.dumps(manifest, indent=2) + "\n")
    return ['dropped "xml" from manifest.json; the layout ships inside tool.lua']


def repair(folder):
    """Make one tool folder publishable, in place. Returns what it changed.

    Only ever rewrites the block, the four config values and the signature on
    the UI, and only ever downwards from the manifest: if tool.lua claims a
    version the manifest does not publish, that is a decision, not a typo, so
    it is reported instead.
    """
    tool_id, changed = folder.name, []
    manifest_path, lua = folder / "manifest.json", folder / "tool.lua"
    if not lua.exists():
        return changed                   # nothing to build on; the checks say so

    if not manifest_path.exists():
        write(manifest_path, json.dumps(
            {"stable": {"version": "1.0.0", "notes": ["First release."]}},
            indent=2) + "\n")
        changed.append("wrote manifest.json at 1.0.0 - it needs real notes "
                       "before the push")

    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        published = manifest["stable"]["version"]
    except (ValueError, KeyError, TypeError):
        return changed                   # unreadable; check_tool reports it properly
    if not isinstance(published, str) or not SEMVER.match(published):
        return changed

    changed += repair_ui(folder / "tool.xml", tool_id)
    changed += retire_xml_flag(manifest_path, manifest)

    text = lua.read_text(encoding="utf-8")
    declared = literal(text, "TOOL_VERSION")
    if declared and SEMVER.match(declared) and rank(declared) > rank(published):
        fail("tools/%s" % tool_id,
             "tool.lua declares v%s but manifest.json publishes v%s, so --fix "
             "left both alone" % (declared, published),
             "  bump the manifest to release it, or lower TOOL_VERSION - only "
             "the author knows which")
        return changed

    xml_path = folder / "tool.xml"
    xml = xml_path.read_text(encoding="utf-8") if xml_path.exists() else None
    if xml is not None and xml_of(text) != xml.rstrip("\n") + "\n":
        changed.append("spliced tool.xml into tool.lua as TOOL_XML")
    elif xml is None and xml_of(text) is not None:
        changed.append("removed the spliced layout; there is no tool.xml here")

    embedded = block_of(text)
    if embedded is None:
        changed.append("pasted updater/updater.lua onto the end of the script")
    elif without_config(embedded) != without_config(canonical()):
        changed.append("re-pasted updater/updater.lua over a drifted copy")
    if declared != published:
        changed.append("TOOL_VERSION %s -> %s, from manifest.json"
                       % (declared, published))
    if (literal(text, "TOOL_ID") != tool_id
            or literal(text, "TOOL_SIGNATURE") != signature_for(tool_id)):
        changed.append("set TOOL_ID and TOOL_SIGNATURE from the folder name")
    if literal(text, "REPO_BASE") != literal(canonical(), "REPO_BASE"):
        changed.append("set REPO_BASE from updater/updater.lua")

    try:
        fixed = stamp(text, tool_id, published, xml)
    except BlockError as exc:
        fail("tools/%s/tool.lua" % tool_id, str(exc))
        return changed
    if fixed != text:
        write(lua, fixed)
        if not changed:                  # whitespace, ordering, anything else
            changed.append("rewrote tool.lua around the current block")
    return changed


def check_tool(folder, canonical, repo_base):
    name = folder.name
    where = "tools/%s" % name
    manifest_path = folder / "manifest.json"

    if not manifest_path.exists():
        return fail(where, "missing manifest.json")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except ValueError as exc:
        return fail(where, "manifest.json does not parse: %s" % exc)
    if not isinstance(manifest, dict):
        return fail(where, 'manifest.json must be an object with a "stable" entry')

    entry = manifest.get("stable")
    if not isinstance(entry, dict) or not entry.get("version"):
        return fail(where, 'manifest.json needs {"stable": {"version": "..."}}')

    version = entry["version"]
    if not SEMVER.match(version):
        return fail(where, "version %r is not plain X.Y.Z, which is all the "
                           "block compares" % version)

    check_notes("%s/manifest.json" % where, entry)
    check_history("%s/manifest.json" % where, manifest, version)

    lua = folder / "tool.lua"
    if not lua.exists():
        return fail(where, "manifest.json publishes v%s, but tool.lua is missing"
                           % version)

    check_payload("%s/tool.lua" % where, lua, version, name, repo_base, canonical)

    # Nothing in a manifest describes the UI any more: the layout is part of
    # the payload, so a release either carries one or does not, and the file
    # that says which is tool.lua itself.
    if "xml" in entry:
        fail("%s/manifest.json" % where, '"xml" no longer does anything - the '
             'layout ships inside tool.lua',
             "  run: python scripts/validate.py --fix")

    xml = folder / "tool.xml"
    if xml.exists():
        check_ui("%s/tool.xml" % where, xml, name)
    return None


def main():
    parser = argparse.ArgumentParser(
        description="Check every tool folder against what the block needs at "
                    "runtime.")
    parser.add_argument("--fix", action="store_true",
                        help="first paste in the current block and fill the "
                             "config from the folder name and manifest, so a "
                             "folder dropped into tools/ becomes a "
                             "publishable tool")
    args = parser.parse_args()

    if not UPDATER.exists():
        print("cannot find %s" % UPDATER)
        return 2

    canon = canonical()
    repo_base = literal(canon, "REPO_BASE")
    check_one_write("updater/updater.lua", canon)
    check_switch("updater/updater.lua", canon)

    folders = sorted(p for p in TOOLS.iterdir() if p.is_dir()) if TOOLS.is_dir() else []

    if args.fix:
        done = [("tools/" + f.name, line) for f in folders for line in repair(f)]
        for where, line in done:
            print("%s: %s" % (where, line))
        if done:
            print()

    for folder in folders:
        check_tool(folder, canon, repo_base)

    if problems:
        print("FAILED %d check(s)\n" % len(problems))
        for where, message, detail in problems:
            print("  %s: %s" % (where, message))
            if detail:
                print(detail)
            print()
        return 1

    print("OK  %d tool(s): %s" % (len(folders), ", ".join(f.name for f in folders) or "none"))
    print("    block, signature, sizes, versions and notes all consistent")
    return 0


if __name__ == "__main__":
    sys.exit(main())
