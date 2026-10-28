"""How the updater block is embedded in a tool file. Standard library only.

Both scripts here work on the same thing - a tool.lua is the script with
updater/updater.lua pasted onto the end and four config values filled in - so
that one operation lives here rather than in two slightly different copies.

A tool may also have an XML UI, authored as tool.xml beside it. That file is
not published: stamp() splices it into tool.lua as a Lua long string, and the
block applies it at load. One file is the whole tool, which is why an update
cannot land half of one - there are no halves to land.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UPDATER = ROOT / "updater" / "updater.lua"
TOOLS = ROOT / "tools"

# Fork exception: a tool whose own code says this on a line of its own keeps
# SELF_UPDATE=false. validate.py accepts it and --fix does not flip it back.
PIN_MARKER = re.compile(r"^--\s*validate:\s*SELF_UPDATE=false is intentional\b", re.M)
SELF_UPDATE_LINE = re.compile(r"^local\s+SELF_UPDATE\s*=.*$", re.M)
CONFIG_KEYS = ("REPO_BASE", "TOOL_ID", "TOOL_VERSION", "TOOL_SIGNATURE")
SEMVER = re.compile(r"^\d+\.\d+\.\d+$")

# Any signature comment, whoever it names: the stamps strip these before they
# write the right one, so a file copied from another tool - or a folder that
# was renamed - cannot keep a signature that would make clients refuse it, or
# end up carrying two.
XML_SIGNATURE_LINE = re.compile(r"^\s*<!--\s*TTS-SELFUPDATE:[^>]*-->\s*$")
LUA_SIGNATURE_LINE = re.compile(r"^--\s*TTS-SELFUPDATE:\S*\s*$")

DIVIDER = (
    "\n-- ===========================================================================\n"
    "-- Everything below this line is updater/updater.lua, pasted unchanged.\n"
    "-- ===========================================================================\n\n"
)

XML_DIVIDER = (
    "\n-- ===========================================================================\n"
    "-- The tool's UI, spliced in from tool.xml. Edits in that file, not this copy.\n"
    "-- ===========================================================================\n\n"
)

# The spliced literal, read back out of a published file exactly as Lua sees
# it: the newline straight after the opening bracket is not part of the string.
TOOL_XML_LITERAL = re.compile(r"^local TOOL_XML = \[(=*)\[\n(.*?)\]\1\]$",
                              re.M | re.S)


class BlockError(Exception):
    """Something about the block itself is wrong, and no file was written."""


def canonical():
    return UPDATER.read_text(encoding="utf-8")


def signature_for(tool_id):
    return "TTS-SELFUPDATE:" + tool_id


def xml_comment(tool_id):
    """The signature as it appears in an XML UI: a comment, and nothing else.

    XML has no line comments and nowhere to keep a literal, so the gate a
    client applies to a UI download is this exact string appearing in it.
    """
    return "<!-- %s -->" % signature_for(tool_id)


def write(path, text):
    """Always LF, whatever platform this runs on - these files ship as-is."""
    with open(str(path), "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)


def literal(text, name):
    """Value of `local NAME = "value"` or `local NAME = 123`."""
    m = re.search(r'^local\s+%s\s*=\s*"([^"]*)"' % name, text, re.M)
    if m:
        return m.group(1)
    m = re.search(r"^local\s+%s\s*=\s*(\d+)" % name, text, re.M)
    return m.group(1) if m else None


def set_config(block, key, value):
    """Rewrite `local KEY = "..."` in a copy of the block."""
    pattern = r'^local\s+%s(\s*)=\s*"[^"]*"([ \t]*--.*)?$' % key
    replacement = lambda m: 'local %s%s= "%s"%s' % (key, m.group(1), value,
                                                    m.group(2) or "")
    block, count = re.subn(pattern, replacement, block, flags=re.M)
    if count != 1:
        raise BlockError("expected one %s line in updater/updater.lua, found %d"
                         % (key, count))
    return block


def opener_at(text):
    """Where the block's first line starts in `text`, or -1.

    Matched as a whole line, never a prefix: a tool can carry another script
    of its own whose header opens with the same run of `=`, and that is not
    the block. The last match wins for the same reason - the block is pasted
    onto the end, so anything earlier is the tool's.
    """
    opener = canonical().splitlines()[0]
    found = -1
    for m in re.finditer(r"^%s$" % re.escape(opener), text, re.M):
        found = m.start()
    return found


def block_of(text):
    """The updater block as embedded in a distributable file, or None."""
    index = opener_at(text)
    return None if index < 0 else text[index:]


def head_of(text):
    """The tool's own script: everything above the spliced UI and the block.

    Stopping at the UI matters for more than tidiness - the payload gate looks
    for `function onLoad` in here, and a layout is perfectly capable of
    carrying that string somewhere in a comment.
    """
    # Only the dividers' first two lines are matched, up to the full stop: the
    # rest is wording, and rewording it must not orphan every file stamped
    # with the old one - the next --fix would splice the layout in twice.
    for mark in (XML_DIVIDER, DIVIDER):
        index = text.find(mark[:mark.index(".") + 1])
        if index >= 0:
            return text[:index]
    index = opener_at(text)
    return text if index < 0 else text[:index]


def long_string(text):
    """`text` as a Lua long-bracket literal, at a level it cannot close itself.

    The level goes up until the closing sequence is absent from the body, so
    no layout can end the string early however many brackets it has in it.
    Lua drops the newline straight after the opening bracket, which is why one
    is written there: the string starts at tool.xml's own first character.
    """
    level = 0
    while ("]" + "=" * level + "]") in text:
        level += 1
    eq = "=" * level
    return "local TOOL_XML = [%s[\n%s]%s]\n" % (
        eq, text.rstrip("\n") + "\n", eq)


def xml_of(text):
    """The UI spliced into a published file, or None. The inverse of above."""
    match = TOOL_XML_LITERAL.search(text)
    return match.group(2) if match else None


def without_config(text):
    """Blank the four config values so copies compare equal across tools."""
    for key in CONFIG_KEYS:
        text = re.sub(r'^local\s+%s\s*=.*$' % key,
                      "local %s = <config>" % key, text, flags=re.M)
    # SELF_UPDATE is compared by check_switch (true, or pinned by its marker),
    # not here, so a pinned fork copy still matches the block otherwise.
    text = SELF_UPDATE_LINE.sub("local SELF_UPDATE = <switch>", text)
    return text


def stamp(text, tool_id, version, xml=None):
    """A tool file rebuilt around the current block, config filled in.

    `text` is either a finished tool.lua or a bare object script with no block
    in it yet; both come out the same shape. `xml` is the tool.xml beside it,
    spliced in between the two. Rebuilding all three parts on every pass is
    the point - a tool folder can never drift, and the file stays an ordinary
    readable one that diffs cleanly afterwards.
    """
    head = head_of(text).rstrip("\n") + "\n"

    signature = signature_for(tool_id)
    # Drop a header from a name this tool used to have before writing the one
    # it has now. Renaming a folder is how a file ends up with two of them,
    # and the stale one names a tool that no longer exists.
    lines = head.splitlines(True)
    while lines and LUA_SIGNATURE_LINE.match(lines[0]):
        lines.pop(0)
        if lines and lines[0].strip() == "--":
            lines.pop(0)
    head = "-- %s\n--\n%s" % (signature, "".join(lines))

    ui = "" if xml is None else XML_DIVIDER + long_string(xml)

    block = canonical()
    block = set_config(block, "TOOL_ID", tool_id)
    block = set_config(block, "TOOL_VERSION", version)
    block = set_config(block, "TOOL_SIGNATURE", signature)
    if PIN_MARKER.search(head):
        block = SELF_UPDATE_LINE.sub("local SELF_UPDATE    = false", block)
    return head + ui + DIVIDER + block


def stamp_xml(text, tool_id):
    """An XML UI file with this tool's signature comment as its first line.

    The signature is no longer a gate - the layout travels inside a payload
    that is already checked three ways - but it still says which tool a loose
    file belongs to, and it rides along into the splice. Nothing else in the
    file is touched, and running it twice changes nothing the second time.
    """
    lines = [ln for ln in text.splitlines() if not XML_SIGNATURE_LINE.match(ln)]
    return "\n".join([xml_comment(tool_id)] + lines).rstrip("\n") + "\n"
