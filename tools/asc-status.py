#!/usr/bin/env python3
"""Read-only App Store Connect status for Golden Pixel.

Mints a short-lived JWT from ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_CONTENT and issues
GET requests only. Prints a plain-text report to stdout, and to GITHUB_STEP_SUMMARY
when that is set. Never prints secrets, JWTs, review-contact values, or tester emails.

Run from anywhere: the three ASC_* variables must already be in the environment.
"""
from __future__ import annotations

import base64
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime
from zoneinfo import ZoneInfo

BUNDLE_ID = "co.worldwidewebb.goldenpixel"
API = "https://api.appstoreconnect.apple.com"
HST = ZoneInfo("Pacific/Honolulu")

# iPhone-only app (TARGETED_DEVICE_FAMILY = 1). Screenshot requirements follow
# App Store Connect Help, "Screenshot specifications" (checked 2026-11-20), same
# mapping as tools/appstore.py: APP_IPHONE_61 is required; APP_IPHONE_67 is
# required unless APP_IPHONE_65 is provided; APP_IPHONE_DUO is optional until
# April 2027.

# Version localization fields that block submission when empty. Marketing URL,
# promotional text and (on a first release) What's New are optional.
VERSION_REQUIRED = (
    ("description", "description"),
    ("keywords", "keywords"),
    ("supportUrl", "support URL"),
)
VERSION_OPTIONAL = (
    ("marketingUrl", "marketing URL"),
    ("promotionalText", "promotional text"),
    ("whatsNew", "what's new"),
)

# Review-contact attributes must never be printed; only present/missing.
REVIEW_CONTACT_FIELDS = (
    ("contactFirstName", "contact first name"),
    ("contactLastName", "contact last name"),
    ("contactEmail", "contact email"),
    ("contactPhone", "contact phone"),
    ("demoAccountName", "demo account name"),
    ("demoAccountPassword", "demo account password"),
    ("notes", "review notes"),
)

# Age-rating answers that should be filled in for a complete declaration.
# kidsAgeBand is only for Made for Kids, so it is not required here.
AGE_RATING_FIELDS = (
    "alcoholTobaccoOrDrugUseOrReferences",
    "contests",
    "gambling",
    "gamblingSimulated",
    "horrorOrFearThemes",
    "matureOrSuggestiveThemes",
    "medicalOrTreatmentInformation",
    "profanityOrCrudeHumor",
    "sexualContentGraphicAndNudity",
    "sexualContentOrNudity",
    "unrestrictedWebAccess",
    "violenceCartoonOrFantasy",
    "violenceRealistic",
    "violenceRealisticProlongedGraphicOrSadistic",
    "gamblingAndContests",
    "seventeenPlus",
    "lootBox",
    "advertising",
    "ageRatingOverride",
    "ageRatingOverrideV2",
)


class HttpError(Exception):
    def __init__(self, status: int, message: str):
        self.status = status
        super().__init__(message)


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _der_to_jose(der: bytes) -> bytes:
    """Convert an OpenSSL ECDSA DER signature to the raw r||s form JWT needs."""
    if not der or der[0] != 0x30:
        raise ValueError("openssl did not return a DER ECDSA signature")
    idx = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)

    def read_int(i: int) -> tuple[bytes, int]:
        if i >= len(der) or der[i] != 0x02:
            raise ValueError("malformed ECDSA signature")
        n = der[i + 1]
        v = der[i + 2 : i + 2 + n]
        return v, i + 2 + n

    r, idx = read_int(idx)
    s, _ = read_int(idx)
    r = (r.lstrip(b"\x00") or b"\x00").rjust(32, b"\x00")
    s = (s.lstrip(b"\x00") or b"\x00").rjust(32, b"\x00")
    if len(r) != 32 or len(s) != 32:
        raise ValueError("ECDSA signature components were not P-256")
    return r + s


def _pem(content: str) -> bytes:
    text = content.strip().replace("\r\n", "\n")
    if "BEGIN" in text:
        if not text.endswith("\n"):
            text += "\n"
        return text.encode()
    body = "".join(text.split())
    lines = [body[i : i + 64] for i in range(0, len(body), 64)]
    return ("-----BEGIN PRIVATE KEY-----\n" + "\n".join(lines) + "\n-----END PRIVATE KEY-----\n").encode()


def mint_jwt(key_id: str, issuer_id: str, key_content: str) -> str:
    now = int(time.time())
    header = _b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}, separators=(",", ":")).encode())
    payload = _b64url(
        json.dumps(
            {"iss": issuer_id, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
            separators=(",", ":"),
        ).encode()
    )
    signing_input = f"{header}.{payload}".encode()
    fd, path = tempfile.mkstemp(prefix="asc-", suffix=".p8")
    try:
        os.write(fd, _pem(key_content))
        os.close(fd)
        os.chmod(path, 0o600)
        der = subprocess.check_output(
            ["openssl", "dgst", "-sha256", "-sign", path],
            input=signing_input,
            stderr=subprocess.DEVNULL,
        )
    except Exception as exc:
        raise SystemExit(f"failed to mint an App Store Connect JWT ({exc.__class__.__name__})") from None
    finally:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    return f"{header}.{payload}.{_b64url(_der_to_jose(der))}"


def fmt_time(iso: str | None) -> str:
    if not iso:
        return "unknown"
    try:
        dt = datetime.fromisoformat(iso.replace("Z", "+00:00")).astimezone(HST)
    except ValueError:
        return iso
    return dt.strftime("%b %-d, %Y, %-I:%M %p") + " HST"


def present(value) -> bool:
    if value is None:
        return False
    if isinstance(value, str):
        return bool(value.strip())
    return True


def attr(resource, *keys):
    node = (resource or {}).get("attributes") or {}
    if len(keys) == 1:
        return node.get(keys[0])
    return {k: node.get(k) for k in keys}


def rel_id(resource, name: str) -> str | None:
    data = ((resource or {}).get("relationships") or {}).get(name, {}).get("data")
    if isinstance(data, dict):
        return data.get("id")
    return None


def rel_ids(resource, name: str) -> list[str]:
    data = ((resource or {}).get("relationships") or {}).get(name, {}).get("data")
    if isinstance(data, dict):
        return [data["id"]] if data.get("id") else []
    if isinstance(data, list):
        return [item["id"] for item in data if item.get("id")]
    return []


class Client:
    """App Store Connect client that can only GET."""

    def __init__(self, token: str):
        self._token = token

    def get(self, path: str, params: dict | None = None) -> dict:
        if path.startswith("http"):
            url = path
        else:
            if not path.startswith("/"):
                path = "/" + path
            url = API + path
        if params:
            # Keep bracketed filter keys as-is.
            query = urllib.parse.urlencode(params, doseq=True, safe="[]")
            url = url + ("&" if "?" in url else "?") + query
        req = urllib.request.Request(
            url,
            method="GET",
            headers={
                "Authorization": f"Bearer {self._token}",
                "Accept": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=45) as resp:
                body = resp.read()
                return json.loads(body.decode()) if body else {}
        except urllib.error.HTTPError as exc:
            raw = exc.read().decode("utf-8", errors="replace")
            message = _apple_error(raw) or f"HTTP {exc.code}"
            raise HttpError(exc.code, message) from None
        except urllib.error.URLError as exc:
            raise HttpError(0, f"network error ({exc.__class__.__name__})") from None

    def get_opt(self, path: str, params: dict | None = None) -> dict | None:
        try:
            return self.get(path, params)
        except HttpError as exc:
            if exc.status in (404, 403):
                return None
            raise

    def get_all(self, path: str, params: dict | None = None) -> tuple[list, list]:
        data, included = [], []
        params = dict(params or {})
        page = self.get(path, params)
        while True:
            data.extend(page.get("data") or [])
            included.extend(page.get("included") or [])
            nxt = (page.get("links") or {}).get("next")
            if not nxt:
                break
            page = self.get(nxt)
        return data, included


def _apple_error(raw: str) -> str:
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return raw.strip().splitlines()[0][:200] if raw.strip() else ""
    bits = []
    for err in payload.get("errors") or []:
        title = err.get("title") or ""
        detail = err.get("detail") or ""
        code = err.get("code") or ""
        bits.append(": ".join(p for p in (code, title, detail) if p))
    return "; ".join(bits)[:400]


def included_index(included: list) -> dict:
    return {(item.get("type"), item.get("id")): item for item in included if item.get("id")}


def find(index: dict, typ: str, ident: str | None):
    if not ident:
        return None
    return index.get((typ, ident))


class Report:
    def __init__(self):
        self.lines: list[str] = []
        self.blockers: list[str] = []
        self.notes: list[str] = []

    def add(self, line: str = "") -> None:
        self.lines.append(line)

    def section(self, title: str) -> None:
        if self.lines and self.lines[-1] != "":
            self.add()
        self.add(title)
        self.add("-" * len(title))

    def blocker(self, line: str) -> None:
        self.blockers.append(line)

    def note(self, line: str) -> None:
        self.notes.append(line)

    def flush(self) -> str:
        text = "\n".join(self.lines).rstrip() + "\n"
        sys.stdout.write(text)
        summary = os.environ.get("GITHUB_STEP_SUMMARY")
        if summary:
            with open(summary, "a", encoding="utf-8") as fh:
                fh.write(text)
                if not text.endswith("\n"):
                    fh.write("\n")
        return text


def missing_label(value, label: str) -> str:
    if present(value):
        return f"{label}: set"
    return f"{label}: missing"


def report_testflight(client: Client, app_id: str, report: Report) -> None:
    report.section("1. TestFlight beta review")
    builds, included = client.get_all(
        "/v1/builds",
        {
            "filter[app]": app_id,
            "include": "preReleaseVersion,buildBetaDetail,betaAppReviewSubmission,betaGroups,appEncryptionDeclaration",
            "sort": "-uploadedDate",
            "limit": "200",
            "limit[betaGroups]": "50",
        },
    )
    index = included_index(included)

    groups, _ = client.get_all(
        f"/v1/apps/{app_id}/betaGroups",
        {"limit": "200"},
    )

    in_review = []
    for build in builds:
        submission = find(index, "betaAppReviewSubmissions", rel_id(build, "betaAppReviewSubmission"))
        if not submission:
            # Relationship may be omitted from include; fetch per build only when present.
            if rel_id(build, "betaAppReviewSubmission"):
                body = client.get_opt(f"/v1/builds/{build['id']}/betaAppReviewSubmission")
                submission = (body or {}).get("data")
        state = (attr(submission, "betaReviewState") or "").upper()
        if state in {"WAITING_FOR_REVIEW", "IN_REVIEW"}:
            in_review.append((build, state, submission))

    if not builds:
        report.add("No TestFlight builds were returned for this app.")
    elif in_review:
        report.add("Yes — at least one build is in TestFlight beta review:")
        for build, state, _ in in_review:
            report.add(f"  - {_build_label(build, index)}: betaAppReviewSubmission {state}")
    else:
        report.add("No build is in TestFlight beta review (no WAITING_FOR_REVIEW or IN_REVIEW submissions).")

    report.add()
    report.add("Beta groups:")
    if not groups:
        report.add("  (none)")
        report.note("No TestFlight beta groups are set up.")
    else:
        for group in groups:
            name = attr(group, "name") or group["id"]
            kind = "internal" if attr(group, "isInternalGroup") else "external"
            bits = [kind]
            if attr(group, "hasAccessToAllBuilds"):
                bits.append("has access to all builds")
            if attr(group, "publicLinkEnabled"):
                bits.append("public link enabled")
            else:
                bits.append("no public link")
            report.add(f"  - {name} ({', '.join(bits)})")

    report.add()
    report.add("Builds (newest first):")
    if not builds:
        report.add("  (none)")
        return

    for build in builds:
        detail = find(index, "buildBetaDetails", rel_id(build, "buildBetaDetail"))
        if not detail:
            body = client.get_opt(f"/v1/builds/{build['id']}/buildBetaDetail")
            detail = (body or {}).get("data")
        submission = find(index, "betaAppReviewSubmissions", rel_id(build, "betaAppReviewSubmission"))
        if not submission and rel_id(build, "betaAppReviewSubmission"):
            body = client.get_opt(f"/v1/builds/{build['id']}/betaAppReviewSubmission")
            submission = (body or {}).get("data")
        group_names = []
        for gid in rel_ids(build, "betaGroups"):
            g = find(index, "betaGroups", gid)
            group_names.append((attr(g, "name") if g else None) or gid)
        if not group_names:
            # hasAccessToAllBuilds groups still apply, but may not be linked on the build.
            auto = [attr(g, "name") or g["id"] for g in groups if attr(g, "hasAccessToAllBuilds")]
            if auto:
                group_names = [f"{n} (all-builds access)" for n in auto]

        internal = attr(detail, "internalBuildState") or "unknown"
        external = attr(detail, "externalBuildState") or "unknown"
        review = attr(submission, "betaReviewState") if submission else "none"
        processing = attr(build, "processingState") or "unknown"
        encryption = attr(build, "usesNonExemptEncryption")
        if encryption is True:
            enc = "uses non-exempt encryption"
        elif encryption is False:
            enc = "usesNonExemptEncryption=false"
        else:
            enc = "export compliance unanswered (usesNonExemptEncryption is empty)"
        expired = ", expired" if attr(build, "expired") else ""
        report.add(f"  - {_build_label(build, index)}: processing {processing}{expired}")
        report.add(f"      internalBuildState={internal}, externalBuildState={external}")
        report.add(f"      betaAppReviewSubmission={review}")
        report.add(f"      groups: {', '.join(group_names) if group_names else 'none assigned'}")
        report.add(f"      {enc}; uploaded {fmt_time(attr(build, 'uploadedDate'))}")


def _build_label(build, index) -> str:
    version = attr(find(index, "preReleaseVersions", rel_id(build, "preReleaseVersion")), "version")
    number = attr(build, "version") or build["id"]
    if version:
        return f"{version} ({number})"
    return f"build {number}"


def report_app_store_review(client: Client, app_id: str, report: Report) -> tuple[list, dict]:
    report.section("2. App Store review")
    versions, included = client.get_all(
        f"/v1/apps/{app_id}/appStoreVersions",
        {
            "filter[platform]": "IOS",
            "include": "build,appStoreVersionLocalizations,appStoreReviewDetail",
            "limit": "50",
            "limit[appStoreVersionLocalizations]": "50",
        },
    )
    index = included_index(included)

    review_states = {
        "WAITING_FOR_REVIEW",
        "IN_REVIEW",
        "PENDING_APPLE_RELEASE",
        "PROCESSING_FOR_APP_STORE",
        "WAITING_FOR_EXPORT_COMPLIANCE",
    }
    in_review = []
    for version in versions:
        store = (attr(version, "appStoreState") or "").upper()
        ver_state = (attr(version, "appVersionState") or "").upper()
        if store in review_states or ver_state in review_states:
            in_review.append((version, store, ver_state))

    submissions = []
    sub_error = None
    try:
        submissions, _ = client.get_all(
            "/v1/reviewSubmissions",
            {"filter[app]": app_id, "filter[platform]": "IOS", "limit": "50"},
        )
    except HttpError as exc:
        sub_error = str(exc)

    active_sub_states = {"READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES", "CANCELING", "COMPLETING"}
    active_subs = [s for s in submissions if (attr(s, "state") or "").upper() in active_sub_states]

    if in_review or any((attr(s, "state") or "").upper() in {"WAITING_FOR_REVIEW", "IN_REVIEW"} for s in submissions):
        report.add("Yes — something is in App Store review:")
        for version, store, ver_state in in_review:
            report.add(f"  - version {attr(version, 'versionString')}: appStoreState={store or 'n/a'}, appVersionState={ver_state or 'n/a'}")
        for sub in submissions:
            state = (attr(sub, "state") or "").upper()
            if state in {"WAITING_FOR_REVIEW", "IN_REVIEW"}:
                report.add(f"  - review submission {sub['id']}: {state}, submitted {fmt_time(attr(sub, 'submittedDate'))}")
    else:
        report.add("Nothing is in App Store review.")

    report.add()
    report.add("App Store versions:")
    if not versions:
        report.add("  (none — no iOS App Store version exists yet)")
        report.blocker("No iOS App Store version exists yet.")
    else:
        for version in versions:
            store = attr(version, "appStoreState") or "n/a"
            ver_state = attr(version, "appVersionState") or "n/a"
            build = find(index, "builds", rel_id(version, "build"))
            build_no = attr(build, "version") if build else "none attached"
            created = fmt_time(attr(version, "createdDate"))
            report.add(
                f"  - {attr(version, 'versionString')}: appStoreState={store}, "
                f"appVersionState={ver_state}, build={build_no}, created {created}"
            )

    report.add()
    report.add("Review submissions:")
    if sub_error:
        report.add(f"  Could not list review submissions: {sub_error}")
    elif not submissions:
        report.add("  (none)")
    else:
        # Newest first by submitted or created date.
        def sub_key(s):
            return attr(s, "submittedDate") or attr(s, "createdDate") or ""

        for sub in sorted(submissions, key=sub_key, reverse=True):
            state = attr(sub, "state") or "n/a"
            submitted = fmt_time(attr(sub, "submittedDate")) if attr(sub, "submittedDate") else "not submitted"
            report.add(f"  - {sub['id']}: state={state}, submitted {submitted}")
            items_body = client.get_opt(f"/v1/reviewSubmissions/{sub['id']}/items", {"limit": "50"})
            for item in (items_body or {}).get("data") or []:
                report.add(f"      item {item.get('id')}: state={attr(item, 'state') or 'n/a'}")

    if active_subs and not in_review:
        # A draft READY_FOR_REVIEW submission is not yet in Apple's review queue.
        states = ", ".join(sorted({attr(s, "state") or "?" for s in active_subs}))
        report.add(f"  Open (not necessarily in review) submission states: {states}")

    return versions, index


def _screenshot_sets(client: Client, loc_id: str) -> dict[str, int]:
    sets, _ = client.get_all(
        f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets",
        {"limit": "200"},
    )
    counts: dict[str, int] = {}
    for shot_set in sets:
        display = attr(shot_set, "screenshotDisplayType") or "unknown"
        shots, _ = client.get_all(f"/v1/appScreenshotSets/{shot_set['id']}/appScreenshots", {"limit": "50"})
        # Count only screenshots that finished uploading.
        ready = 0
        for shot in shots:
            state = (attr(shot, "assetDeliveryState") or {})
            # assetDeliveryState can be a dict with state, or a string, depending on API version.
            if isinstance(state, dict):
                flag = (state.get("state") or "").upper()
            else:
                flag = str(state).upper()
            if flag in {"", "COMPLETE", "APPROVED"} or attr(shot, "fileSize"):
                ready += 1
        counts[display] = counts.get(display, 0) + ready
    return counts


def report_metadata(client: Client, app: dict, versions: list, version_index: dict, report: Report) -> None:
    report.section("3. Missing store metadata that would block an App Store submission")
    app_id = app["id"]

    # Prefer a version that is still editable / not yet shipped.
    editable_states = {
        "PREPARE_FOR_SUBMISSION",
        "DEVELOPER_REJECTED",
        "REJECTED",
        "METADATA_REJECTED",
        "INVALID_BINARY",
        "WAITING_FOR_REVIEW",
        "IN_REVIEW",
        "READY_FOR_REVIEW",
    }
    version = None
    for candidate in versions:
        state = (attr(candidate, "appStoreState") or attr(candidate, "appVersionState") or "").upper()
        if state in editable_states:
            version = candidate
            break
    if not version and versions:
        version = versions[0]

    if not version:
        report.add("No App Store version to inspect for listing metadata.")
        report.blocker("No App Store version, so listing metadata cannot be complete.")
    else:
        label = attr(version, "versionString") or version["id"]
        report.add(f"Inspecting version {label} (appStoreState={attr(version, 'appStoreState') or 'n/a'}).")
        loc_ids = rel_ids(version, "appStoreVersionLocalizations")
        locs = [find(version_index, "appStoreVersionLocalizations", i) for i in loc_ids]
        locs = [loc for loc in locs if loc]
        if not locs:
            fetched, _ = client.get_all(
                f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations",
                {"limit": "50"},
            )
            locs = fetched
        if not locs:
            report.add("  No version localizations (description, keywords, URLs, screenshots).")
            report.blocker("No App Store version localization is present.")
        for loc in locs:
            locale = attr(loc, "locale") or loc["id"]
            report.add()
            report.add(f"Version localization ({locale}):")
            first = (attr(version, "appStoreState") or "").upper() in {
                "PREPARE_FOR_SUBMISSION",
                "READY_FOR_REVIEW",
                "WAITING_FOR_REVIEW",
                "IN_REVIEW",
                "DEVELOPER_REJECTED",
                "REJECTED",
                "METADATA_REJECTED",
                "INVALID_BINARY",
            } and not any(
                (attr(v, "appStoreState") or "").upper() in {"READY_FOR_SALE", "PENDING_DEVELOPER_RELEASE", "PENDING_APPLE_RELEASE", "REPLACED_WITH_NEW_VERSION"}
                for v in versions
            )
            for key, name in VERSION_REQUIRED:
                value = attr(loc, key)
                if present(value):
                    extra = ""
                    if key == "description":
                        extra = f" ({len(str(value))} characters)"
                    elif key == "keywords":
                        extra = f" ({len(str(value))} characters)"
                    report.add(f"  - {name}: set{extra}")
                else:
                    report.add(f"  - {name}: missing")
                    report.blocker(f"{locale} {name} is missing.")
            for key, name in VERSION_OPTIONAL:
                value = attr(loc, key)
                if present(value):
                    report.add(f"  - {name}: set")
                elif key == "whatsNew" and first:
                    report.add(f"  - {name}: empty (optional on a first release)")
                    report.note(f"{locale} what's new is empty; that is optional on a first release.")
                else:
                    report.add(f"  - {name}: empty (optional)")
                    report.note(f"{locale} {name} is empty (optional).")

            counts = _screenshot_sets(client, loc["id"])
            report.add("  Screenshots by display type:")
            if not counts:
                report.add("    (none)")
            else:
                for display, n in sorted(counts.items()):
                    report.add(f"    - {display}: {n}")
            has_61 = counts.get("APP_IPHONE_61", 0) > 0
            has_67 = counts.get("APP_IPHONE_67", 0) > 0
            has_65 = counts.get("APP_IPHONE_65", 0) > 0
            if not has_61:
                report.add("    - APP_IPHONE_61: missing — required (iPhone with Dynamic Island, medium display)")
                report.blocker(f"{locale} is missing required screenshots for APP_IPHONE_61.")
            if not has_67 and not has_65:
                report.add("    - APP_IPHONE_67 / APP_IPHONE_65: missing — one of these is required for the large iPhone class")
                report.blocker(f"{locale} is missing required large-iPhone screenshots (APP_IPHONE_67 or APP_IPHONE_65).")
            if counts.get("APP_IPHONE_DUO", 0) == 0:
                report.add("    - APP_IPHONE_DUO: none (optional until April 2027)")
                report.note(f"{locale} has no iPhone Duo screenshots; they become required in April 2027 for the iOS 27.1 SDK or later.")

        # Review contact on this version — presence only, never values.
        report.add()
        report.add("Review contact details (values withheld; this repository is public):")
        detail = find(version_index, "appStoreReviewDetails", rel_id(version, "appStoreReviewDetail"))
        if not detail:
            body = client.get_opt(f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail")
            detail = (body or {}).get("data")
        if not detail:
            report.add("  - no review detail record is attached to this version")
            report.blocker("App Review contact details are missing.")
        else:
            for key, name in REVIEW_CONTACT_FIELDS:
                if key in {"demoAccountName", "demoAccountPassword"}:
                    continue
                report.add(f"  - {missing_label(attr(detail, key), name)}")
            required_contact = ("contactFirstName", "contactLastName", "contactEmail", "contactPhone")
            if not all(present(attr(detail, k)) for k in required_contact):
                report.blocker("App Review contact first name, last name, email or phone is missing.")
            demo_required = attr(detail, "demoAccountRequired")
            report.add(f"  - demo account required: {demo_required if demo_required is not None else 'not set'}")
            if demo_required is True:
                name_ok = present(attr(detail, "demoAccountName"))
                pass_ok = present(attr(detail, "demoAccountPassword"))
                report.add(f"  - demo account name: {'set' if name_ok else 'missing'}")
                report.add(f"  - demo account password: {'set' if pass_ok else 'missing'}")
                if not (name_ok and pass_ok):
                    report.blocker("A demo account is required, but the name or password is missing.")
            else:
                report.add("  - demo account credentials: not required")

        # Export compliance on the version's attached build, plus the latest build.
        report.add()
        report.add("Export compliance:")
        attached = find(version_index, "builds", rel_id(version, "build"))
        if attached:
            enc = attr(attached, "usesNonExemptEncryption")
            report.add(f"  - attached build {attr(attached, 'version')}: {_enc_label(enc)}")
            if enc is None:
                report.blocker(f"Export compliance is unanswered on attached build {attr(attached, 'version')}.")
        else:
            report.add("  - no build is attached to this App Store version")
            report.blocker("No build is attached to the App Store version.")

    # App information (name, subtitle, category, privacy, age rating, content rights).
    report.add()
    report.add("App information:")
    content_rights = attr(app, "contentRightsDeclaration")
    if present(content_rights):
        report.add(f"  - content rights declaration: {content_rights}")
    else:
        report.add("  - content rights declaration: missing")
        report.blocker("Content rights declaration is missing.")

    infos, info_included = client.get_all(
        f"/v1/apps/{app_id}/appInfos",
        {
            "include": "primaryCategory,primarySubcategoryOne,primarySubcategoryTwo,secondaryCategory,ageRatingDeclaration,appInfoLocalizations",
            "limit": "20",
            "limit[appInfoLocalizations]": "50",
        },
    )
    info_index = included_index(info_included)
    if not infos:
        report.add("  - no appInfos were returned")
        report.blocker("App information (name, category, age rating) is missing.")
        info = None
    else:
        # Prefer the state that can still be edited; fall back to the first.
        info = None
        for candidate in infos:
            if (attr(candidate, "appStoreState") or "").upper() in editable_states | {"PREPARE_FOR_SUBMISSION"}:
                info = candidate
                break
        info = info or infos[0]
        report.add(f"  - appInfo state: {attr(info, 'appStoreState') or 'n/a'}")
        rating = attr(info, "appStoreAgeRating")
        if rating:
            report.add(f"  - App Store age rating: {rating}")

        locs = [find(info_index, "appInfoLocalizations", i) for i in rel_ids(info, "appInfoLocalizations")]
        locs = [loc for loc in locs if loc]
        if not locs:
            fetched, _ = client.get_all(f"/v1/appInfos/{info['id']}/appInfoLocalizations", {"limit": "50"})
            locs = fetched
        if not locs:
            report.add("  - no app info localizations")
            report.blocker("App name / subtitle / privacy-policy localization is missing.")
        for loc in locs:
            locale = attr(loc, "locale") or loc["id"]
            name = attr(loc, "name")
            subtitle = attr(loc, "subtitle")
            privacy = attr(loc, "privacyPolicyUrl")
            report.add(f"  - {locale} name: {name if present(name) else 'missing'}")
            report.add(f"  - {locale} subtitle: {subtitle if present(subtitle) else 'empty (optional)'}")
            report.add(f"  - {locale} privacy policy URL: {privacy if present(privacy) else 'missing'}")
            if not present(name):
                report.blocker(f"{locale} app name is missing.")
            if not present(privacy):
                report.blocker(f"{locale} privacy policy URL is missing.")
            if not present(subtitle):
                report.note(f"{locale} subtitle is empty (optional).")

        cat = find(info_index, "appCategories", rel_id(info, "primaryCategory"))
        if not cat and rel_id(info, "primaryCategory"):
            body = client.get_opt(f"/v1/appInfos/{info['id']}/primaryCategory")
            cat = (body or {}).get("data")
        if cat:
            sub1 = find(info_index, "appCategories", rel_id(info, "primarySubcategoryOne"))
            sub2 = find(info_index, "appCategories", rel_id(info, "primarySubcategoryTwo"))
            secondary = find(info_index, "appCategories", rel_id(info, "secondaryCategory"))
            extras = []
            if sub1:
                extras.append(f"subcategory {sub1.get('id')}")
            if sub2:
                extras.append(f"subcategory {sub2.get('id')}")
            if secondary:
                extras.append(f"secondary {secondary.get('id')}")
            suffix = f" ({', '.join(extras)})" if extras else ""
            report.add(f"  - primary category: {cat.get('id')}{suffix}")
        else:
            report.add("  - primary category: missing")
            report.blocker("Primary category is missing.")

        # Age rating declaration completeness.
        decl = find(info_index, "ageRatingDeclarations", rel_id(info, "ageRatingDeclaration"))
        if not decl:
            body = client.get_opt(f"/v1/appInfos/{info['id']}/ageRatingDeclaration")
            decl = (body or {}).get("data")
        if not decl:
            report.add("  - age rating declaration: missing")
            report.blocker("Age rating declaration is missing.")
        else:
            attrs = decl.get("attributes") or {}
            # Prefer the known field list when those keys exist; otherwise use whatever came back.
            keys = [k for k in AGE_RATING_FIELDS if k in attrs] or list(attrs)
            unset = [k for k in keys if attrs.get(k) is None]
            set_n = sum(1 for k in keys if attrs.get(k) is not None)
            if rating and not unset:
                report.add(f"  - age rating declaration: complete ({set_n} answers set; rating {rating})")
            elif rating and unset:
                # Some keys (overrides, loot boxes, advertising) can legitimately be null.
                optional_null = {
                    "kidsAgeBand",
                    "ageRatingOverride",
                    "ageRatingOverrideV2",
                    "seventeenPlus",
                    "gamblingAndContests",
                    "lootBox",
                    "advertising",
                }
                needed = [k for k in unset if k not in optional_null]
                if needed:
                    report.add(f"  - age rating declaration: incomplete; unset: {', '.join(needed)}")
                    report.blocker("Age rating declaration is incomplete: " + ", ".join(needed) + ".")
                else:
                    report.add(
                        f"  - age rating declaration: present (rating {rating}; "
                        f"optional unset fields: {', '.join(unset) if unset else 'none'})"
                    )
            elif unset:
                report.add(f"  - age rating declaration: incomplete; unset: {', '.join(unset)}")
                report.blocker("Age rating declaration is incomplete: " + ", ".join(unset) + ".")
            else:
                report.add(f"  - age rating declaration: present ({set_n} answers set)")

    # Pricing and availability.
    report.add()
    report.add("Pricing and availability:")
    schedule = client.get_opt(f"/v1/apps/{app_id}/appPriceSchedule", {"include": "baseTerritory,manualPrices"})
    if not schedule or not schedule.get("data"):
        report.add("  - price schedule: missing")
        report.blocker("Pricing is not set (no app price schedule).")
    else:
        data = schedule["data"]
        inc = included_index(schedule.get("included") or [])
        base = find(inc, "territories", rel_id(data, "baseTerritory"))
        base_id = (base or {}).get("id") or rel_id(data, "baseTerritory") or "unknown"
        prices = rel_ids(data, "manualPrices")
        # The include may already have appPrices; if not, fetch.
        if not prices:
            fetched = client.get_opt(f"/v1/appPriceSchedules/{data['id']}/manualPrices", {"include": "territory", "limit": "200"})
            if fetched:
                prices = [p["id"] for p in fetched.get("data") or []]
                inc.update(included_index(fetched.get("included") or []))
        report.add(f"  - price schedule: present, base territory {base_id}, {len(prices)} manual price(s)")
        # Try to show the base price point if included, without assuming paid vs free incorrectly.
        for pid in prices[:5]:
            price = inc.get(("appPrices", pid))
            if not price:
                continue
            # Newer appPrices have a start date; the actual customer price needs the price point.
            start = attr(price, "startDate") or "current"
            report.add(f"      manual price {pid}: start {start}")

    try:
        avail = client.get_opt(
            f"/v1/apps/{app_id}/appAvailabilityV2",
            {"include": "territoryAvailabilities", "limit[territoryAvailabilities]": "50"},
        )
        if not avail or not avail.get("data"):
            avail = client.get_opt(f"/v1/apps/{app_id}/appAvailability")
        if not avail or not avail.get("data"):
            report.add("  - availability: not returned by the API (check App Store Connect if territories are selected)")
            report.note("Territory availability was not returned by the API.")
        else:
            data = avail["data"]
            if isinstance(data, list):
                data = data[0] if data else {}
            territories, _ = [], []
            # Prefer a paginated relationship list; the include cap is 50.
            if data.get("id") and "appAvailabilities" in (data.get("type") or "appAvailabilities"):
                try:
                    territories_res, _ = client.get_all(
                        f"/v2/appAvailabilities/{data['id']}/territoryAvailabilities",
                        {"limit": "50"},
                    )
                    territories = [item["id"] for item in territories_res]
                except HttpError:
                    territories = rel_ids(data, "territoryAvailabilities")
            else:
                territories = rel_ids(data, "territoryAvailabilities")
            available_in_new = attr(data, "availableInNewTerritories")
            report.add(
                f"  - availability: {len(territories)} territor"
                f"{'y' if len(territories) == 1 else 'ies'} listed"
                + (f", availableInNewTerritories={available_in_new}" if available_in_new is not None else "")
            )
            if not territories:
                report.blocker("No App Store territories are listed as available.")
    except HttpError as exc:
        report.add(f"  - availability: could not be read ({exc})")
        report.note(f"Territory availability could not be read: {exc}")

    # App privacy / data usage — the API often does not expose the published nutrition label.
    report.add()
    report.add("App privacy (data usage):")
    privacy_paths = [
        f"/v1/apps/{app_id}/appDataUsages",
        f"/v1/appDataUsages?filter[app]={urllib.parse.quote(app_id)}",
        f"/v1/apps/{app_id}/dataAndPrivacy",
        f"/v1/apps/{app_id}/appDataUsage",
    ]
    privacy_found = False
    for path in privacy_paths:
        body = None
        try:
            body = client.get(path)
        except HttpError as exc:
            if exc.status not in (400, 404, 403, 405):
                report.add(f"  - privacy endpoint failed: {exc}")
            continue
        if body and body.get("data"):
            privacy_found = True
            data = body["data"]
            n = len(data) if isinstance(data, list) else 1
            report.add(f"  - API returned app data usage data ({n} record(s) from {path})")
            break
    if not privacy_found:
        report.add("  - the App Store Connect API does not expose the published App Privacy nutrition-label status")
        report.note(
            "App Privacy (data usage) could not be confirmed through the API; "
            "it still has to be published in App Store Connect before submission."
        )

    # Latest-build export compliance as an extra signal if no version is attached.
    latest, latest_inc = client.get_all(
        "/v1/builds",
        {"filter[app]": app_id, "sort": "-uploadedDate", "limit": "1"},
    )
    if latest:
        enc = attr(latest[0], "usesNonExemptEncryption")
        report.add(f"  - latest uploaded build {attr(latest[0], 'version')}: {_enc_label(enc)}")


def _enc_label(enc) -> str:
    if enc is True:
        return "usesNonExemptEncryption=true"
    if enc is False:
        return "usesNonExemptEncryption=false (complete)"
    return "usesNonExemptEncryption is empty (export compliance unanswered)"


def main() -> int:
    key_id = os.environ.get("ASC_KEY_ID", "").strip()
    issuer_id = os.environ.get("ASC_ISSUER_ID", "").strip()
    key_content = os.environ.get("ASC_KEY_CONTENT", "").strip()
    if not (key_id and issuer_id and key_content):
        sys.stderr.write("Missing ASC_KEY_ID, ASC_ISSUER_ID or ASC_KEY_CONTENT.\n")
        return 2

    token = mint_jwt(key_id, issuer_id, key_content)
    # Drop key material from this process's view of the environment after minting.
    os.environ.pop("ASC_KEY_CONTENT", None)
    client = Client(token)
    report = Report()

    now = datetime.now(HST).strftime("%b %-d, %Y, %-I:%M %p") + " HST"
    report.add(f"Golden Pixel ({BUNDLE_ID}) — App Store Connect status")
    report.add(f"Checked at {now}. Read-only GET requests only; nothing was submitted or changed.")

    try:
        body = client.get("/v1/apps", {"filter[bundleId]": BUNDLE_ID, "limit": "5"})
    except HttpError as exc:
        report.add(f"Failed to list apps: {exc}")
        report.flush()
        return 1

    apps = body.get("data") or []
    if not apps:
        report.add("No App Store Connect app record exists for this bundle ID.")
        report.section("1. TestFlight beta review")
        report.add("Cannot check builds; there is no app record.")
        report.section("2. App Store review")
        report.add("Cannot check review state; there is no app record.")
        report.section("3. Missing store metadata that would block an App Store submission")
        report.add("Everything is missing until the app record exists.")
        report.blocker("No App Store Connect app record exists for co.worldwidewebb.goldenpixel.")
        report.section("Summary of blockers")
        for item in report.blockers:
            report.add(f"- {item}")
        report.flush()
        return 1

    app = apps[0]
    report.add(f"App record found: {attr(app, 'name') or 'unnamed'} (SKU {attr(app, 'sku') or 'n/a'}).")

    try:
        report_testflight(client, app["id"], report)
        versions, version_index = report_app_store_review(client, app["id"], report)
        report_metadata(client, app, versions, version_index, report)
    except HttpError as exc:
        report.add()
        report.add(f"Part of the report could not be finished: {exc}")
        report.note(f"The check hit an API error and stopped early: {exc}")

    report.section("Summary of blockers")
    if report.blockers:
        for item in report.blockers:
            report.add(f"- {item}")
    else:
        report.add("No missing required items were detected by this check.")
    if report.notes:
        report.add()
        report.add("Notes (not necessarily blockers):")
        for item in report.notes:
            report.add(f"- {item}")

    report.flush()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as exc:
        # Never dump env or tokens if something unexpected blows up.
        sys.stderr.write(f"asc-status failed: {exc.__class__.__name__}: {exc}\n")
        sys.exit(1)
