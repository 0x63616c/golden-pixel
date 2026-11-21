#!/usr/bin/env python3
"""App Store listing tools for Golden Pixel.

  tools/appstore.py check [--online]
      Audit the listing in the repo: fastlane/metadata limits and ASO rules, the screenshots in
      fastlane/screenshots/en-US (sizes, alpha, counts, staleness against Core/ and App/), the
      privacy manifest, export compliance key and the hosted pages. Prints OK / WARN / FAIL per
      line; exits 1 on any FAIL. --online also fetches the support, marketing and privacy URLs.
      Standard library only.

  tools/appstore.py shots <raw-dir> <out-dir> <scene>...
      Turn simulator captures (<raw-dir>/<sim>/<scene>.png, as `ios/ios.sh capture` writes them)
      into deliver-ready files: <out-dir>/<sim>_<NN>_<scene>.png, alpha removed, sizes checked,
      in the order given. Clears old PNGs in <out-dir> first. Needs Pillow.

Run from the repo root. ios/ios.sh appstore calls `shots`; the appstore skill calls `check`.
"""
import os
import re
import struct
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
META = ROOT / "fastlane" / "metadata"
SHOTS = ROOT / "fastlane" / "screenshots" / "en-US"

# Simulator short name (ios/ios.sh use_sim) -> App Store display class, exact landscape size,
# and whether App Store Connect requires it. Source: App Store Connect Help, "Screenshot
# specifications" (checked 2026-11-20). One class per size; fastlane deliver maps by size.
CLASSES = {
    "duo": ("iPhone Duo inner (APP_IPHONE_DUO)", (2853, 2007),
            "optional now; required from April 2027 for apps built with the iOS 27.1 SDK or later; adds the Duo badge"),
    "duo_outer": ("iPhone Duo outer (APP_IPHONE_DUO)", (2034, 1398),
                  "optional now; required from April 2027 with the inner set"),
    "iphone": ("Dynamic Island medium, 6.3\" (APP_IPHONE_61)", (2622, 1206), "required"),
    "max": ("Dynamic Island large, 6.9\" (APP_IPHONE_67)", (2868, 1320),
            "required unless Face ID large 6.5\" is given; this one covers it"),
}
REQUIRED = {"iphone", "max"}

LIMITS = {  # characters, App Store Connect
    "en-US/name.txt": 30,
    "en-US/subtitle.txt": 30,
    "en-US/keywords.txt": 100,
    "en-US/promotional_text.txt": 170,
    "en-US/description.txt": 4000,
    "en-US/release_notes.txt": 4000,
}
URL_FILES = ["en-US/support_url.txt", "en-US/marketing_url.txt", "en-US/privacy_url.txt"]
# Guideline 2.3.7: no pricing terms in name, subtitle or keywords (the app is free; say so in
# the description and promotional text instead). Generic and Apple terms only waste space.
PRICING = {"free", "sale", "discount", "cheap", "deal"}
WASTE = {"app", "apps", "game", "games", "iphone", "apple", "best", "top"}

results = []


def report(level, msg):
    results.append(level)
    print(f"{level:4}  {msg}")


def read(rel):
    p = META / rel
    return p.read_text(encoding="utf-8") if p.exists() else None


def words(text):
    return {w for w in re.split(r"[^a-z0-9]+", text.lower()) if w}


def stem(w):
    return w[:-1] if len(w) > 3 and w.endswith("s") else w


def png_info(path):
    """(width, height, has_alpha) from the PNG header, no Pillow needed."""
    with open(path, "rb") as f:
        head = f.read(33)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    w, h, _depth, ctype = struct.unpack(">IIBB", head[16:26])
    alpha = ctype in (4, 6)
    if not alpha:  # a tRNS chunk also means transparency
        alpha = b"tRNS" in Path(path).read_bytes()[:65536]
    return w, h, alpha


def git_time(*paths):
    try:
        out = subprocess.run(["git", "-C", str(ROOT), "log", "-1", "--format=%ct", "--", *paths],
                             capture_output=True, text=True, check=True).stdout.strip()
        t = int(out) if out else 0
        dirty = subprocess.run(["git", "-C", str(ROOT), "status", "--porcelain", "--", *paths],
                               capture_output=True, text=True).stdout.strip()
        return t, bool(dirty)
    except Exception:
        return 0, False


def check_metadata():
    print("== Metadata (fastlane/metadata)")
    for rel, limit in LIMITS.items():
        text = read(rel)
        if text is None:
            report("FAIL" if "release_notes" not in rel else "WARN", f"{rel} missing")
            continue
        n = len(text.rstrip("\n")) if rel.endswith(("name.txt", "subtitle.txt", "keywords.txt")) else len(text)
        if not text.strip():
            report("FAIL", f"{rel} is empty")
        elif n > limit:
            report("FAIL", f"{rel}: {n}/{limit} characters")
        else:
            report("OK", f"{rel}: {n}/{limit}")
    name, sub, kw = (read(f"en-US/{f}.txt") or "" for f in ("name", "subtitle", "keywords"))
    if kw:
        if re.search(r",\s|\s,", kw) or "\n" in kw.strip():
            report("FAIL", "keywords: spaces or newlines around commas waste characters")
        terms = [t for t in kw.strip().split(",")]
        if any(not t for t in terms):
            report("FAIL", "keywords: empty term (double or trailing comma)")
        dupes = {t for t in terms if terms.count(t) > 1}
        if dupes:
            report("FAIL", f"keywords: repeated {sorted(dupes)}")
        visible = {stem(w) for w in words(name) | words(sub)}
        overlap = [t for t in terms if words(t) and all(stem(w) in visible for w in words(t))]
        if overlap:
            report("WARN", f"keywords already in name/subtitle (wasted): {overlap}")
        spare = 100 - len(kw.strip())
        if spare > 8:
            report("WARN", f"keywords: {spare} characters unused")
    for label, text in (("name", name), ("subtitle", sub), ("keywords", kw)):
        bad = sorted(words(text) & PRICING)
        if bad:
            report("FAIL", f"{label}: {bad} is pricing language (guideline 2.3.7)")
        waste = sorted(words(text) & WASTE) if label == "keywords" else []
        if waste:
            report("WARN", f"keywords: {waste} are generic or Apple terms and earn nothing")
    desc = read("en-US/description.txt") or ""
    if desc and len(desc.split("\n", 1)[0]) > 170:
        report("WARN", "description: first line is long; only ~3 lines show before 'more'")
    for rel in URL_FILES:
        url = (read(rel) or "").strip()
        if not url:
            report("FAIL" if "marketing" not in rel else "WARN", f"{rel} missing")
        elif not url.startswith("https://"):
            report("FAIL", f"{rel}: {url} is not https")
        else:
            report("OK", f"{rel}: {url}")
    for rel in ["copyright.txt", "primary_category.txt", "primary_first_sub_category.txt",
                "review_information/notes.txt"]:
        report("OK" if (read(rel) or "").strip() else "FAIL", f"{rel}{'' if (read(rel) or '').strip() else ' missing'}")
    copyright = (read("copyright.txt") or "").strip()
    year = subprocess.run(["date", "+%Y"], capture_output=True, text=True).stdout.strip()
    if copyright and year and not copyright.startswith(year):
        report("WARN", f"copyright.txt starts with {copyright[:4]}, this year is {year}")


def check_urls_online():
    print("== URLs (online)")
    for rel in URL_FILES:
        url = (read(rel) or "").strip()
        if not url:
            continue
        try:
            req = urllib.request.Request(url, method="GET", headers={"User-Agent": "appstore-check"})
            with urllib.request.urlopen(req, timeout=15) as r:
                report("OK" if r.status == 200 else "FAIL", f"{url} -> {r.status}")
        except Exception as e:
            report("FAIL", f"{url} -> {e.__class__.__name__}: {getattr(e, 'code', e)}")


def check_screenshots():
    print("== Screenshots (fastlane/screenshots/en-US)")
    files = sorted(SHOTS.glob("*.png")) if SHOTS.exists() else []
    if not files:
        report("FAIL", "no screenshots: run `just appstore-shots` (ios/ios.sh appstore)")
        return
    by_size = {size: key for key, (_, size, _) in CLASSES.items()}
    counts = {k: 0 for k in CLASSES}
    newest = 0
    for f in files:
        info = png_info(f)
        if not info:
            report("FAIL", f"{f.name}: not a PNG")
            continue
        w, h, alpha = info
        key = by_size.get((w, h))
        if not key:
            report("FAIL", f"{f.name}: {w}x{h} matches no App Store display class")
            continue
        counts[key] += 1
        if alpha:
            report("FAIL", f"{f.name}: has an alpha channel (App Store Connect rejects it)")
        newest = max(newest, int(f.stat().st_mtime))
    for key, (label, size, rule) in CLASSES.items():
        n = counts[key]
        if n == 0:
            report("FAIL" if key in REQUIRED else "WARN", f"{label} {size[0]}x{size[1]}: none ({rule})")
        elif n > 10:
            report("FAIL", f"{label}: {n} screenshots, max 10")
        else:
            report("OK", f"{label} {size[0]}x{size[1]}: {n}")
    sets = {counts[k] for k in ("duo", "iphone", "max") if counts[k]}
    if len(sets) > 1:
        report("WARN", f"sets differ in length: { {k: counts[k] for k in counts if counts[k]} }")
    changed, dirty = git_time("Core/Sources", "App")
    oldest = min(int(f.stat().st_mtime) for f in files)
    if changed > oldest or dirty:
        report("WARN", "screenshots are older than the last change to Core/Sources or App/"
               + (" (uncommitted changes there)" if dirty else "") + ": regenerate before uploading")


def check_compliance():
    print("== Privacy and compliance")
    info = (ROOT / "ios" / "Info.plist").read_text()
    m = re.search(r"<key>ITSAppUsesNonExemptEncryption</key>\s*<(true|false)/>", info)
    report("OK" if m and m.group(1) == "false" else "FAIL",
           "Info.plist ITSAppUsesNonExemptEncryption = " + (m.group(1) if m else "missing"))
    manifest = ROOT / "ios" / "PrivacyInfo.xcprivacy"
    proj = (ROOT / "ios" / "project.yml").read_text()
    report("OK" if manifest.exists() and "PrivacyInfo.xcprivacy" in proj else "FAIL",
           "ios/PrivacyInfo.xcprivacy present and listed in project.yml")
    # Anything that would change the privacy label from "Data Not Collected". StoreKit is allowed
    # in App/Rating.swift alone, and only to ask for a rating: nothing there may sell or read.
    risky = re.compile(r"\b(URLSession|NWConnection|import Network|import StoreKit|import AdSupport|"
                       r"import AppTrackingTransparency|import GameKit|import CloudKit|ASIdentifierManager|"
                       r"identifierForVendor|NSUbiquitousKeyValueStore|import FirebaseCore)\b")
    purchases = re.compile(r"\b(SKPayment\w*|SKProduct\w*|SKReceipt\w*|Product\.|Transaction\.|AppTransaction|"
                           r"SubscriptionStoreView|StoreView|ProductView|\.purchase\()")
    rating = "App/Rating.swift"
    hits = []
    for base in (ROOT / "App", ROOT / "Core" / "Sources" / "GoldenPixelCore"):
        for p in base.rglob("*.swift"):
            rel = str(p.relative_to(ROOT))
            for i, line in enumerate(p.read_text(errors="ignore").splitlines(), 1):
                code = line.split("//")[0]
                if rel == rating and "import StoreKit" in code:
                    continue
                if risky.search(line) or (rel == rating and purchases.search(code)):
                    hits.append(f"{rel}:{i}")
    if hits:
        report("FAIL", "code may collect data or need a new privacy answer: " + ", ".join(hits[:8]))
    else:
        report("OK", "no network, ads, tracking, purchase or identifier APIs in App/ or the core "
                     "(StoreKit only asks for a rating, in App/Rating.swift)")
    for page in ("site/privacy.md", "site/support.md"):
        report("OK" if (ROOT / page).exists() else "FAIL", page)
    report("OK" if (ROOT / "fastlane" / "app_rating_config.json").exists() else "FAIL",
           "fastlane/app_rating_config.json (age rating answers)")


def cmd_check(args):
    check_metadata()
    if "--online" in args:
        check_urls_online()
    check_screenshots()
    check_compliance()
    fails, warns = results.count("FAIL"), results.count("WARN")
    print(f"\n{fails} FAIL, {warns} WARN")
    return 1 if fails else 0


def cmd_shots(args):
    if len(args) < 3:
        print(__doc__)
        return 2
    raw, out, scenes = Path(args[0]), Path(args[1]), args[2:]
    if len(scenes) > 10:
        print("At most 10 screenshots per display class")
        return 2
    from PIL import Image  # noqa: E402 (only this command needs Pillow)

    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.png"):
        old.unlink()
    written, problems = 0, 0
    for sim in ("duo", "iphone", "max", "duo_outer"):
        folder = raw / "duo" / "outer" if sim == "duo_outer" else raw / sim
        if not folder.is_dir():
            continue
        label, size, _ = CLASSES[sim]
        for n, scene in enumerate(scenes, 1):
            src = folder / f"{scene}.png"
            if not src.exists():
                print(f"WARN  {sim}: no {scene}.png")
                problems += 1
                continue
            im = Image.open(src)
            if im.size != size:
                print(f"FAIL  {src}: {im.size[0]}x{im.size[1]}, {label} needs {size[0]}x{size[1]}")
                problems += 1
                continue
            rgb = Image.new("RGB", im.size, (0, 0, 0))
            rgb.paste(im.convert("RGBA"), mask=im.convert("RGBA").getchannel("A"))
            if sim == "duo_outer" and not rgb.getbbox():
                print(f"WARN  {src}: all black (the cover screen is off while the Duo is unfolded); skipped")
                problems += 1
                continue
            dst = out / f"{sim}_{n:02d}_{scene}.png"
            rgb.save(dst, optimize=True)
            st = src.stat()  # keep the capture time, so `check` can tell stale shots
            os.utime(dst, (st.st_atime, st.st_mtime))
            written += 1
    print(f"{written} screenshots in {out}" + (f", {problems} problems" if problems else ""))
    return 1 if written == 0 else 0


if __name__ == "__main__":
    os.chdir(ROOT)
    cmd, rest = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 1 else ("", [])
    if cmd == "check":
        sys.exit(cmd_check(rest))
    if cmd == "shots":
        sys.exit(cmd_shots(rest))
    print(__doc__)
    sys.exit(2)
