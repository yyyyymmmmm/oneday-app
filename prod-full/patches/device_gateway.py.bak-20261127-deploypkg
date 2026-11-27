#!/usr/bin/env python3
"""device-bridge: tool-call facade between Hermes and the OneDay iOS app
(batch-1 skeleton, pre-built 2026-11-10; NOT yet registered in Hermes
config, nginx routes exist only as a draft).

Model (design: oneday-design-review/device-connectors-design-20261110.md
as amended by device-sync-design-20261110.md, user decisions
2026-11-10 21:52 + 21:58):
- Record-type datasets (contacts, calendar, reminders, photo index,
  per-day step aggregates) are SYNCED as field-minimised copies into
  device_sync's SQLite store on this service; the query tools answer
  from the copy and always carry its sync time plus a plain-language
  freshness sentence. Permission revoked => the copy stops serving
  entirely (2026-11-10 21:58 ruling).
- Realtime and action tools keep the original tool-call model:
  authorization and data stay on the phone, the app reads/writes
  live. Same-name query tools fall back to a live read when the copy
  has never been synced or was deleted, and say so in the result.
- On disk: the audit log (metadata, no payload content), the
  write-key store (idempotency key -> object id, no content), and
  the sync store (sync.db, the one sanctioned copy).

Surfaces (all but /health need this bridge's own Bearer,
DEVICE_BRIDGE_KEY env; fail-closed when unset):
- GET  /health                 -> {"ok": true, ...} (no auth, no data)
- POST /mcp                    -> MCP streamable-http facade (JSON-RPC):
                                  initialize / ping / tools/list /
                                  tools/call
- POST /device/session         -> app registers a session {deviceId,
                                  appVersion, permissions, tools}
- POST /device/heartbeat       -> {sessionId} keep-alive
- GET  /device/poll?sessionId= -> long-poll (<=25s) for the next call
- POST /device/respond         -> {sessionId, callId, status, result?,
                                  error?} completes a call
- POST /device/resume          -> {resumeToken} re-dispatches a parked
                                  call once (§244 permission flow)
- POST /device/park-state      -> {resumeToken} read-only park truth
                                  for card reconciliation (§261: exists,
                                  expiry, ask outcome; never consumes)
- POST /device/disconnect      -> {sessionId} drops the session
- POST /device/sync/batch      -> stage one sync batch (<=500 records)
- POST /device/sync/complete   -> confirm + atomically swap a batch in
- POST /device/sync/manifest   -> contacts id/fingerprint diff
- POST /device/sync/state      -> app reports permission/range changes
- POST /device/sync/delete     -> delete synced copies (one or all)
- GET  /device/sync/status     -> per-dataset sync state, no content

Call flow: tools/call -> session offline => structured error
device_offline (never stale data); source permission not granted =>
the §244 permission gate (see _permission_gate): never-asked
permissions are asked in the chat itself via a permission_ask
pseudo-call when the app supports it, decided/switch-blocked calls
are parked under a resumeToken and the facade answers
permission_required; otherwise the call is
queued, the app picks it up via poll, executes live, responds; the
facade returns the result. Whole-call timeout DEVICE_CALL_TIMEOUT_SEC
(default 30s) => device_timeout; the presence tools (camera_capture,
vision_document_scan, auth_biometric) wait on the user in person
and get DEVICE_PRESENCE_TIMEOUT_SEC (default 150s) instead
(DESIGN §114.5.4). The §115 batch adds six more presence tools to
that same tier (compose_sms, compose_email, share_sheet,
shortcut_run, file_preview, file_print — DESIGN §115.5.4);
shortcut_run's own app-side callback wait caps at 100s, inside
the 150s bridge tier.

Write tools carry an idempotencyKey (one user confirmation = one key).
A repeated key returns the stored outcome without re-forwarding to the
phone; the app keeps its own 24h key set as the second layer.

Audit: one JSONL line per call {ts, callId, tool, source, status,
durationMs, errorCode, objectId?} -- arguments and result content are
never written.

Gateway home (bridge-retirement batch 5, hermes-deploy 2.0.0):
this module now lives in the gateway process as device_gateway.
The engine below is the bridge's, verbatim; only the transport
changed -- the standalone ThreadingHTTPServer is replaced by the
dispatch adapter at the bottom of this file, driven from
api_server's aiohttp face (/api/device-bridge/* shape-preserving
mounts and /api/device-mcp) with the engine executing on worker
threads (asyncio.to_thread), so the session table, the
pending-call records and the section-244 park flow keep their
exact threading semantics in-process. Two instance bindings
changed with the move: the data dir defaults to /opt/data/device
(DEVICE_DATA_DIR override), and the accepted Bearer is the
deployment's single key (API_SERVER_KEY) -- the bridge's own
DEVICE_BRIDGE_KEY is retired with the bridge (single-key
endgame).
"""

from __future__ import annotations

import hmac
import io
import json
import os
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

try:
    from gateway.platforms import device_sync
except ImportError:  # direct module load (selftest / tooling)
    import device_sync

API_KEY = os.environ.get("API_SERVER_KEY", "")  # single key (batch 5: the bridge-scoped DEVICE_BRIDGE_KEY is retired)
DATA_DIR = Path(os.environ.get("DEVICE_DATA_DIR", "/opt/data/device"))
PORT = int(os.environ.get("DEVICE_PORT", "8647"))
MAX_BODY = 1_048_576
CALL_TIMEOUT = float(os.environ.get("DEVICE_CALL_TIMEOUT_SEC", "30"))
# Presence tools (DESIGN §114.5.4) wait on a human standing at the
# phone — framing a photo, scanning several pages, answering a
# Face ID prompt: the default 30s would cut them off mid-gesture.
# Their per-tool timeout is 150s: the §114.5 floor of 120s plus
# headroom for multi-page scans and a biometric retry. Nothing
# else in this bridge caps a single call below that: the phone
# long-polls in <=25s cycles and re-polls, and a pending call
# record does not depend on poll cadence. The app closes its own
# UI and answers with an error if its wait is cancelled, so a
# longer bridge timeout cannot hang a call forever.
PRESENCE_TIMEOUT = float(os.environ.get(
    "DEVICE_PRESENCE_TIMEOUT_SEC", "150"))
# §115.5.4: the batch-four presence tools wait on the user working
# a system surface (composing, sharing, reading a preview) or on
# an x-callback receipt (shortcut_run, whose app-side wait itself
# caps at 100s), so they share this tier. call_start is NOT here:
# it only opens the system dial prompt and answers "initiated"
# at once — it never waits for the call to happen. The batch-four
# live reads (location_*, media_*, device_info) answer on the
# spot and stay on the default timeout.
TOOL_TIMEOUTS = {"camera_capture": PRESENCE_TIMEOUT,
                 "vision_document_scan": PRESENCE_TIMEOUT,
                 "auth_biometric": PRESENCE_TIMEOUT,
                 "compose_sms": PRESENCE_TIMEOUT,
                 "compose_email": PRESENCE_TIMEOUT,
                 "share_sheet": PRESENCE_TIMEOUT,
                 "shortcut_run": PRESENCE_TIMEOUT,
                 "file_preview": PRESENCE_TIMEOUT,
                 "file_print": PRESENCE_TIMEOUT}
POLL_MAX_WAIT = 25.0
SESSION_TTL = 45.0  # seconds since last heartbeat/poll => offline
# §244 permission flow (in-chat authorization, spec
# permission-system-redesign-20261113): when a tool call hits a
# never-asked permission, the bridge asks in the chat itself through
# a permission_ask pseudo-call and waits this long for the user's
# answer before parking the call; parked calls live 24h (the card in
# the chat mirrors the same horizon), single-use resume tokens.
ASK_TIMEOUT = float(os.environ.get("DEVICE_ASK_TIMEOUT_SEC", "120"))
PARK_TTL = 24 * 3600.0
PERMISSION_ASK_TOOL = "permission_ask"
PERMISSION_ASK_CAPABILITY = "permission_ask_v1"

# ---------------------------------------------------------------- tools
# source = the on-device data domain whose permission gates the tool.
TOOLS = [
    {"name": "device_status", "source": "bridge",
     "description": "Device session status: online or not, per-domain "
                    "permission states as last reported by the app, "
                    "plus per-dataset sync state (how many records "
                    "the copy holds, when it was synced, whether it "
                    "is expired, full or partial). Check this before "
                    "answering freshness questions. Answered by the "
                    "bridge itself, no phone round-trip. When a call "
                    "is parked for authorization, it resumes by "
                    "itself once the user acts on the card in the "
                    "chat -- never ask the user to repeat their "
                    "request.",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "calendar_list_events", "source": "calendar",
     "description": "List the phone's calendar events in a window. "
                    "Reads the synced copy of the phone's local "
                    "calendars first (the copy covers a stated date "
                    "range and carries its sync time); any part of "
                    "the window outside the copy's coverage is read "
                    "live from the phone and labelled as such. Use "
                    "this for the user's own schedule questions; do "
                    "not go looking in account connectors for the "
                    "phone's calendar.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "start": {"type": "string",
                                   "description": "ISO 8601 start"},
                         "end": {"type": "string",
                                 "description": "ISO 8601 end"}},
                     "required": ["start", "end"]}},
    {"name": "calendar_search", "source": "calendar",
     "description": "Search the synced copy of the phone's local "
                    "calendars by keyword in title, place or calendar "
                    "name. The result carries the copy's sync time; "
                    "it only covers the copy's stated date range.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "query": {"type": "string"}},
                     "required": ["query"]}},
    {"name": "calendar_count", "source": "calendar",
     "description": "Count events in a window in the synced copy of "
                    "the phone's local calendars. Use for questions "
                    "like how many things are on this week; the count "
                    "is computed on the copy, which carries its sync "
                    "time and coverage range.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "start": {"type": "string",
                                   "description": "ISO 8601 start"},
                         "end": {"type": "string",
                                 "description": "ISO 8601 end"}},
                     "required": ["start", "end"]}},
    {"name": "calendar_create_event", "source": "calendar",
     "description": "Create a calendar event on the phone (write; the "
                    "caller must have the user's explicit confirmation "
                    "of all fields first).",
     "inputSchema": {"type": "object",
                     "properties": {
                         "title": {"type": "string"},
                         "start": {"type": "string"},
                         "end": {"type": "string"},
                         "allDay": {"type": "boolean"},
                         "calendarName": {"type": "string"},
                         "location": {"type": "string"},
                         "notes": {"type": "string"},
                         "idempotencyKey": {"type": "string"}},
                     "required": ["title", "start", "end",
                                  "idempotencyKey"]}},
    {"name": "calendar_update_event", "source": "calendar",
     "description": "Update fields of an existing calendar event "
                    "(write; explicit user confirmation required).",
     "inputSchema": {"type": "object",
                     "properties": {
                         "eventId": {"type": "string"},
                         "title": {"type": "string"},
                         "start": {"type": "string"},
                         "end": {"type": "string"},
                         "location": {"type": "string"},
                         "notes": {"type": "string"},
                         "idempotencyKey": {"type": "string"}},
                     "required": ["eventId", "idempotencyKey"]}},
    {"name": "reminders_list", "source": "reminders",
     "description": "List the phone's incomplete reminders from the "
                    "synced copy (sync time included). If the copy "
                    "has never been synced, the phone is asked live "
                    "instead and the result says so.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "listName": {"type": "string",
                                      "description": "only this list, "
                                                     "optional"}}}},
    {"name": "reminders_count", "source": "reminders",
     "description": "Counts from the synced copy of the phone's "
                    "reminders: how many are incomplete, due today, "
                    "overdue, and how many were completed today. "
                    "Computed on the copy; carries its sync time.",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "reminders_search", "source": "reminders",
     "description": "Search the synced copy of the phone's incomplete "
                    "reminders by keyword in the title. Carries the "
                    "copy's sync time.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "query": {"type": "string"}},
                     "required": ["query"]}},
    {"name": "reminders_create", "source": "reminders",
     "description": "Create a reminder on the phone (write; explicit "
                    "user confirmation required).",
     "inputSchema": {"type": "object",
                     "properties": {
                         "title": {"type": "string"},
                         "due": {"type": "string",
                                 "description": "ISO 8601, optional"},
                         "listName": {"type": "string"},
                         "notes": {"type": "string"},
                         "idempotencyKey": {"type": "string"}},
                     "required": ["title", "idempotencyKey"]}},
    {"name": "reminders_complete", "source": "reminders",
     "description": "Mark a reminder complete (write; idempotent).",
     "inputSchema": {"type": "object",
                     "properties": {
                         "reminderId": {"type": "string"},
                         "idempotencyKey": {"type": "string"}},
                     "required": ["reminderId", "idempotencyKey"]}},
    {"name": "contacts_search", "source": "contacts",
     "description": "Search the synced copy of the phone's local "
                    "address book by name, phone number or email. "
                    "This copy is the phone's whole unified address "
                    "book (merged across iCloud, on-device and other "
                    "accounts on the phone), not one cloud account's "
                    "contacts. To find someone from the phone's "
                    "address book use this tool; do not go looking in "
                    "account connectors. If the copy has never been "
                    "synced, the phone is searched live instead and "
                    "the result says so.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "query": {"type": "string"},
                         "limit": {"type": "integer"}},
                     "required": ["query"]}},
    {"name": "contacts_count", "source": "contacts",
     "description": "How many contacts are in the phone's local "
                    "address book, counted on its synced copy (the "
                    "unified book merged across the phone's "
                    "accounts). Use this for 'how many contacts do I "
                    "have'; do not page through contacts_list and "
                    "count by hand. The result carries the copy's "
                    "sync time.",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "contacts_stats", "source": "contacts",
     "description": "Whole-book picture of the phone's local address "
                    "book, computed on its synced copy: total, share "
                    "with a phone number, share with an email, "
                    "distribution by group, and how many duplicate "
                    "candidate groups exist (same name or same "
                    "number). Use this when the user asks to analyse "
                    "or summarise the address book; do not fetch the "
                    "whole book record by record. Carries the copy's "
                    "sync time.",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "contacts_list", "source": "contacts",
     "description": "Page through the synced copy of the phone's "
                    "local address book (unified across the phone's "
                    "accounts). Returns total_matches, returned and "
                    "has_more: never present the first page as the "
                    "whole book, and never use this to answer a total "
                    "question (use contacts_count). Minimal fields "
                    "only: id, display name, main phone, company.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "limit": {"type": "integer",
                                   "description": "default 50, max 100"},
                         "offset": {"type": "integer"}}}},
    {"name": "contacts_get", "source": "contacts",
     "description": "One contact's stored fields from the synced copy "
                    "of the phone's local address book, by id (from "
                    "contacts_list or contacts_search). The copy "
                    "stores name, phones, emails, company and groups "
                    "only; it has no notes, postal addresses or "
                    "birthdays.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "contactId": {"type": "string"}},
                     "required": ["contactId"]}},
    {"name": "photos_stats", "source": "photos",
     "description": "Photo library picture computed on the synced "
                    "index of the phone's photo library: total, by "
                    "media type, per-month counts, favourites and "
                    "screenshots. The index holds metadata for every "
                    "asset (time, type, size, album) but no image "
                    "data and no locations. Carries the copy's sync "
                    "time.",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "photos_recent", "source": "photos",
     "description": "Most recent assets from the synced index of the "
                    "phone's photo library (metadata only: time, "
                    "type, favourite, album). To fetch an actual "
                    "image, use the live path, not this index. "
                    "Carries the copy's sync time.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "limit": {"type": "integer",
                                   "description": "default 50, max 200"}}}},
    {"name": "motion_steps_summary", "source": "motion",
     "description": "Per-day step totals from the phone's own step "
                    "counter, synced as daily aggregates: date, "
                    "steps, distance, floors, plus the range total. "
                    "This source is the phone's step counter and is "
                    "not the health app's daily summary; do not mix "
                    "the two. Carries the copy's sync time.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "days": {"type": "integer",
                                  "description": "default 7, max 366"}}}},
    {"name": "health_daily_summary", "source": "health",
     "description": "Daily health aggregates computed on the phone "
                    "(steps, sleep hours, resting heart rate, exercise "
                    "minutes). Raw samples never leave the phone.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "days": {"type": "integer",
                                  "description": "default 7, max 31"}}}},
    {"name": "home_status", "source": "home",
     "description": "Current HomeKit status: homes, rooms, accessories "
                    "and their live states (read-only; no control).",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "clipboard_get", "source": "clipboard",
     "description": "Read the phone's clipboard, live on the phone. "
                    "Returns {readAt, type, text?, note?} where type "
                    "is text, url, image or empty; text is included "
                    "only for text/url content — for other types "
                    "only the type is reported, never invented "
                    "content. Reading another app's content makes "
                    "iOS show its paste notice; that is expected. "
                    "This source has no iOS system permission: it "
                    "is gated only by the app offering the tool.",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "clipboard_set", "source": "clipboard",
     "description": "Write text to the phone's clipboard (write; "
                    "the caller must have the user's explicit "
                    "confirmation first; an empty text clears the "
                    "clipboard). The app reads back and verifies "
                    "before reporting success. Returns {written, "
                    "verified, characters}. No iOS system permission "
                    "gates this source.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "text": {"type": "string"},
                         "idempotencyKey": {"type": "string"}},
                     "required": ["text", "idempotencyKey"]}},
    {"name": "files_list", "source": "files",
     "description": "List one level (no recursion) of the OneDay "
                    "app's own documents folder on the phone. "
                    "Returns {path, readAt, count, entries[{name, "
                    "path, isDirectory, sizeBytes?, modifiedAt}], "
                    "truncated?}; capped at 500 entries. Paths are "
                    "relative to the folder root. No iOS system "
                    "permission gates this source.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "path": {"type": "string",
                                  "description": "relative folder, "
                                                 "optional"}}}},
    {"name": "files_read", "source": "files",
     "description": "Read a UTF-8 text file from the OneDay app's "
                    "own documents folder on the phone. Returns "
                    "{path, readAt, bytes, content}. Files over "
                    "256 KB or not UTF-8 text are an honest error, "
                    "never a silent truncation.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "path": {"type": "string"}},
                     "required": ["path"]}},
    {"name": "files_write", "source": "files",
     "description": "Write a UTF-8 text file into the OneDay app's "
                    "own documents folder on the phone (write; "
                    "explicit user confirmation required; parent "
                    "folders are created; max 256 KB). The app "
                    "writes atomically and verifies by reading back "
                    "byte for byte. Returns {path, written, "
                    "verified, bytes}.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "path": {"type": "string"},
                         "content": {"type": "string"},
                         "idempotencyKey": {"type": "string"}},
                     "required": ["path", "content",
                                  "idempotencyKey"]}},
    {"name": "alarm_set", "source": "alarm",
     "description": "Set a real alarm on the phone via iOS AlarmKit "
                    "(write; explicit user confirmation required). "
                    "Give exactly one of at (an ISO 8601 fixed time; "
                    "a time already past is refused on the phone) "
                    "or afterSeconds (a countdown, 5 seconds to 24 "
                    "hours). The app schedules it, then reads the "
                    "system alarm list back and only reports success "
                    "when the alarm is really there. Returns the "
                    "read-back alarm {id, kind: fixed/countdown, "
                    "state, title?, fireAt} plus verified and "
                    "humanSummary (a sentence to repeat back to the "
                    "user). Gated by the phone's real AlarmKit "
                    "authorization, which the app reports as-is.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "title": {"type": "string"},
                         "at": {"type": "string",
                                "description": "ISO 8601 fixed time; "
                                               "mutually exclusive "
                                               "with afterSeconds"},
                         "afterSeconds": {"type": "number",
                                          "description": "countdown "
                                                         "seconds, 5 "
                                                         "to 86400"},
                         "idempotencyKey": {"type": "string"}},
                     "required": ["title", "idempotencyKey"]}},
    {"name": "alarm_list", "source": "alarm",
     "description": "List the alarms this app has set on the phone, "
                    "straight from the system alarm list. Returns "
                    "{count, alarms[{id, kind, state, title?, "
                    "fireAt}], readAt}. Existence and state come "
                    "from the system; a title is filled in from the "
                    "app's own registry and simply absent when the "
                    "registry has none — never invented.",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "alarm_cancel", "source": "alarm",
     "description": "Cancel one alarm previously set via alarm_set, "
                    "by its id (write; explicit user confirmation "
                    "required). A ringing alarm is stopped, any "
                    "other is cancelled; the app reads the system "
                    "list back and only reports success when the "
                    "alarm is gone. Returns {cancelled, wasPresent, "
                    "verified, humanSummary}; wasPresent is false "
                    "when the alarm was already gone, which still "
                    "counts as cancelled.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "alarmId": {"type": "string",
                                     "description": "UUID of the "
                                                    "alarm"},
                         "idempotencyKey": {"type": "string"}},
                     "required": ["alarmId", "idempotencyKey"]}},
    {"name": "notify_post", "source": "notifications",
     "description": "Post a local notification on the phone (write; "
                    "explicit user confirmation required). "
                    "delaySeconds is optional (default 0 = "
                    "immediately, max 7 days); at most 64 delayed "
                    "notifications may be pending — the app refuses "
                    "honestly when full. The app schedules it, then "
                    "reads the pending/delivered lists back and "
                    "only reports success when the notification is "
                    "really there. Returns {posted, verified, id, "
                    "title, humanSummary, deliverAt?}. Gated by "
                    "the phone's real notification authorization, "
                    "which the app reports as-is.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "title": {"type": "string"},
                         "body": {"type": "string"},
                         "delaySeconds": {"type": "number",
                                          "description": "default 0, "
                                                         "max 604800"},
                         "idempotencyKey": {"type": "string"}},
                     "required": ["title", "body",
                                  "idempotencyKey"]}},
    {"name": "open_target", "source": "opener",
     "description": "Open a whitelisted target on the phone: a "
                    "system Settings page or one of a few audited "
                    "apps (write; explicit user confirmation "
                    "required). target is a whitelist id from the "
                    "app's catalogue — arbitrary URLs are refused "
                    "on the phone before anything opens. Opening "
                    "takes the user out of the app, so the session "
                    "will drop; success is judged by the open "
                    "completion itself, and a retried call with the "
                    "same idempotencyKey replays this outcome "
                    "instead of opening again. Returns {opened, "
                    "target, name, humanSummary}. This source has "
                    "no iOS system permission: it is gated only by "
                    "the app offering the tool.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "target": {"type": "string",
                                    "description": "whitelist id, "
                                                   "e.g. app-settings"},
                         "idempotencyKey": {"type": "string"}},
                     "required": ["target", "idempotencyKey"]}},
    {"name": "camera_capture", "source": "camera",
     "description": "Ask the user to take a photo with the phone's "
                    "camera, in person (write; explicit user "
                    "confirmation required). The app opens the "
                    "camera and the user alone decides what to "
                    "photograph and when to press the shutter — "
                    "there are no other arguments. The JPEG is "
                    "saved into the OneDay folder's captures/ "
                    "subfolder, read back and verified byte for "
                    "byte; the reply carries the file read-back "
                    "object {name, path, isDirectory, modifiedAt, "
                    "sizeBytes} plus saved, verified, capturedAt "
                    "and humanSummary — never the image bytes "
                    "themselves (to see what it shows, run "
                    "vision_ocr on the saved path). A retried call "
                    "with the same idempotencyKey replays the "
                    "stored outcome and never reopens the camera. "
                    "Gated by the phone's real camera "
                    "authorization, which the app reports as-is.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "idempotencyKey": {"type": "string"}},
                     "required": ["idempotencyKey"]}},
    {"name": "vision_document_scan", "source": "camera",
     "description": "Ask the user to scan a paper document with "
                    "the phone's system document scanner, in "
                    "person (write; explicit user confirmation "
                    "required). The user scans as many pages as "
                    "they choose in the system UI; every page is "
                    "saved as a JPEG under captures/ with one "
                    "shared batch prefix and verified by "
                    "read-back. Returns {saved, verified, "
                    "pageCount, pages[read-back objects], "
                    "humanSummary}. A retried call with the same "
                    "idempotencyKey replays the stored outcome "
                    "and never reopens the scanner. Gated by the "
                    "phone's real camera authorization (the "
                    "scanner is a camera surface), which the app "
                    "reports as-is.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "idempotencyKey": {"type": "string"}},
                     "required": ["idempotencyKey"]}},
    {"name": "vision_ocr", "source": "vision",
     "description": "Recognise text in an image stored in the "
                    "OneDay app's documents folder, computed "
                    "entirely on the phone. path follows the same "
                    "folder rules as files_read. Returns {path, "
                    "readAt, text, lines, truncated?}; output is "
                    "capped at 300 lines / 20000 characters and "
                    "any truncation is flagged, never silent. "
                    "This source has no iOS system permission: "
                    "it is gated only by the app offering the "
                    "tool.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "path": {"type": "string"}},
                     "required": ["path"]}},
    {"name": "vision_scan_code", "source": "vision",
     "description": "Detect barcodes and QR codes in an image "
                    "stored in the OneDay app's documents folder, "
                    "computed entirely on the phone. Returns "
                    "{path, readAt, count, codes[{symbology, "
                    "payload}]}; codes whose payload cannot be "
                    "read as text are skipped, never invented, "
                    "and symbology names are plain-language "
                    "labels (less common symbologies are grouped "
                    "under one 'other' label). This source has "
                    "no iOS system permission: it is gated only "
                    "by the app offering the tool.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "path": {"type": "string"}},
                     "required": ["path"]}},
    {"name": "translate_text", "source": "translate",
     "description": "Translate text with the phone's on-device "
                    "translation (no network, no UI). source is "
                    "a BCP 47 language tag and is required — the "
                    "headless session needs an explicit source "
                    "language; target is optional and defaults by "
                    "source (Chinese to English, anything else to "
                    "Simplified Chinese). Text is capped at 4000 "
                    "characters. Returns {text, sourceLanguage, "
                    "targetLanguage, readAt, humanSummary} naming "
                    "the languages actually used. If the language "
                    "pair is not downloaded on the phone the call "
                    "fails honestly — the tool never pops a "
                    "download prompt. This source has no iOS "
                    "system permission: it is gated only by the "
                    "app offering the tool.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "text": {"type": "string"},
                         "source": {"type": "string",
                                    "description": "BCP 47 source "
                                                   "language tag"},
                         "target": {"type": "string",
                                    "description": "BCP 47 target "
                                                   "language tag, "
                                                   "optional"}},
                     "required": ["text", "source"]}},
    {"name": "ondevice_model_run", "source": "ondevice",
     "description": "Run one question through the phone's "
                    "on-device foundation model (Apple "
                    "Intelligence), entirely on the phone. Each "
                    "call is a fresh session and carries no "
                    "conversation context. prompt is capped at "
                    "3000 characters, optional instructions at "
                    "1000 (the model's total context is about "
                    "4096 tokens, instructions and answer "
                    "included). Returns {text, model: "
                    "\"on-device\", readAt}. The app only offers "
                    "this tool when the on-device model is "
                    "available (eligible hardware, Apple "
                    "Intelligence on, model ready), so its "
                    "presence in a session's tool list varies by "
                    "device — its absence is normal, not an "
                    "error. This source has no iOS system "
                    "permission: it is gated only by the app "
                    "offering the tool.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "prompt": {"type": "string"},
                         "instructions": {"type": "string"}},
                     "required": ["prompt"]}},
    {"name": "auth_biometric", "source": "biometric",
     "description": "Ask the user, in person on the phone, to "
                    "confirm it is really them with Face ID / "
                    "Touch ID (the system may offer the device "
                    "passcode as fallback). reason (max 120 "
                    "characters) is shown to the user as-is, so "
                    "write it as a plain sentence naming the "
                    "action being confirmed. Returns {confirmed, "
                    "outcome: confirmed/rejected/cancelled, "
                    "biometry, verifiedAt, humanSummary}: a "
                    "rejection or a cancellation is a normal "
                    "result (the answer to this confirmation), "
                    "not an error; the call only fails when "
                    "biometry cannot even be asked (not "
                    "enrolled, unavailable, no passcode set). "
                    "No biometric data reaches the bridge — the "
                    "check happens inside the system. This tool "
                    "is deliberately NOT idempotent: it takes no "
                    "idempotencyKey and every call asks live, "
                    "every time — a stored 'confirmed' is never "
                    "replayed. This source has no switchable iOS "
                    "system permission: it is gated only by the "
                    "app offering the tool.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "reason": {"type": "string"}},
                     "required": ["reason"]}},
    {"name": "location_current", "source": "location",
     "description": "Read the phone's current location once "
                    "(one-shot fix, roughly hundred-metre accuracy "
                    "tier, 20s cap on the phone side). Returns "
                    "{readAt, latitude, longitude, accuracyMeters, "
                    "locatedAt, placeName?, address?, "
                    "humanSummary}: the reverse-geocoded place is "
                    "best-effort — when it cannot be resolved the "
                    "fields are simply absent, never invented; "
                    "accuracyMeters is reported as measured "
                    "(a one-time temporary grant lands in the same "
                    "granted state, told apart only by the "
                    "accuracy reading). location is a REAL iOS "
                    "system permission (when-in-use only; this "
                    "tool never asks for always-on): the bridge "
                    "may answer permission_denied before waking "
                    "the phone.",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "location_search_places", "source": "location",
     "description": "Search for places near the phone's current "
                    "location (pharmacy, restaurant, ...). The "
                    "app first takes a fresh fix and searches "
                    "around it; if the fix fails the call fails "
                    "honestly — it never falls back to an "
                    "uncentred global search and calls it "
                    "'nearby'. limit is optional (default 10, "
                    "clamped 1..20). Returns {readAt, query, "
                    "count, places[{name, latitude, longitude, "
                    "distanceMeters, address?}], humanSummary}; "
                    "distanceMeters is the straight-line distance "
                    "from the current fix, computed live. Same "
                    "real permission as location_current.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "query": {"type": "string"},
                         "limit": {"type": "integer"}},
                     "required": ["query"]}},
    {"name": "location_geocode", "source": "location",
     "description": "Geocode in either direction: give address "
                    "to get coordinates, or latitude+longitude to "
                    "get the address/place — exactly one of the "
                    "two forms (the phone rejects a call that "
                    "gives both or neither, and validates the "
                    "coordinate ranges). Returns {readAt, mode: "
                    "forward/reverse, address?, latitude, "
                    "longitude, placeName?, humanSummary}. A "
                    "lookup that finds nothing fails honestly. "
                    "Same real permission as location_current.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "address": {"type": "string"},
                         "latitude": {"type": "number"},
                         "longitude": {"type": "number"}}}},
    {"name": "media_library_search", "source": "media",
     "description": "Search the phone's music media library "
                    "catalogue (songs, albums, artists, "
                    "playlists, podcasts). kind is optional "
                    "(song/album/artist/playlist/podcast/any, "
                    "default any); limit optional (default 20, "
                    "clamped 1..50). Only catalogue metadata "
                    "comes back — audio itself never leaves the "
                    "phone — and the call cannot see what other "
                    "apps are playing. Returns {readAt, query, "
                    "kind, count, truncated?, results[...], "
                    "humanSummary}. media is a REAL iOS system "
                    "permission: the bridge may answer "
                    "permission_denied before waking the phone.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "query": {"type": "string"},
                         "kind": {"type": "string"},
                         "limit": {"type": "integer"}},
                     "required": ["query"]}},
    {"name": "media_playlists", "source": "media",
     "description": "List all playlists in the phone's media "
                    "library (capped at 200, flagged truncated "
                    "when cut). Returns {readAt, count, "
                    "truncated?, playlists[{type, id, name, "
                    "itemCount}]}. Same real permission as "
                    "media_library_search.",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "media_playlist_create", "source": "media",
     "description": "Create an empty playlist in the phone's "
                    "media library (write; the caller must have "
                    "the user's explicit confirmation of the "
                    "name first). name is capped at 100 "
                    "characters. After creating, the phone "
                    "re-reads the playlist list by persistent id "
                    "and only then reports success. Returns the "
                    "playlist object {type, id, name, itemCount} "
                    "plus {created, verified, humanSummary}. A "
                    "repeated idempotencyKey returns the stored "
                    "outcome and re-reads the playlist as it now "
                    "is — it never creates a second one. Same "
                    "real permission as media_library_search.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "name": {"type": "string"},
                         "idempotencyKey": {"type": "string"}},
                     "required": ["name", "idempotencyKey"]}},
    {"name": "media_playback_control", "source": "media",
     "description": "Control the system music player (write). "
                    "action is one of play/pause/stop/next/"
                    "previous; query is only for play — the "
                    "phone finds that song by keyword first, "
                    "then plays it. After acting, the phone "
                    "polls the playback state for up to about "
                    "1.5s and only reports success when the "
                    "target state is actually reached (playing "
                    "for play, not-playing for pause, item "
                    "changed for next/previous); otherwise it "
                    "fails honestly with the real current state. "
                    "Returns {action, verified, state, "
                    "nowPlaying{title, artist?}?, humanSummary}. "
                    "A repeated idempotencyKey replays the "
                    "stored outcome WITHOUT re-sending the "
                    "action. Same real permission as "
                    "media_library_search.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "action": {"type": "string"},
                         "query": {"type": "string"},
                         "idempotencyKey": {"type": "string"}},
                     "required": ["action", "idempotencyKey"]}},
    {"name": "call_start", "source": "compose",
     "description": "Bring up the system dial prompt for a "
                    "phone number: opens the tel: address and "
                    "the SYSTEM shows its own call confirmation "
                    "— the user taps Call in person; this tool "
                    "never dials by itself. Returns {initiated, "
                    "number, note, humanSummary}: initiated only "
                    "says the prompt was opened. This tool is "
                    "deliberately NOT idempotent: it takes no "
                    "idempotencyKey and every call opens the "
                    "prompt live, every time — replaying a stored "
                    "'opened' would fake the user's presence "
                    "(DESIGN §115.5.3, same family as "
                    "auth_biometric). This source has no iOS "
                    "system permission: it is gated only by the "
                    "app offering the tool.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "number": {"type": "string"}},
                     "required": ["number"]}},
    {"name": "compose_sms", "source": "compose",
     "description": "Open the system SMS composer prefilled "
                    "(recipients at least one, each shape-"
                    "checked; body optional, capped at 2000 "
                    "characters). The user reviews and taps Send "
                    "in person on the system surface — this tool "
                    "brings them to the door, it never sends. "
                    "Returns {presented, outcome: sent/"
                    "cancelled, sent, note?, humanSummary} from "
                    "what actually happened on the surface: the "
                    "user cancelling is a normal outcome "
                    "reported as a result, not an error. "
                    "Deliberately NOT idempotent (no "
                    "idempotencyKey, never replayed — §115.5.3). "
                    "This source has no iOS system permission: "
                    "it is gated only by the app offering the "
                    "tool.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "recipients": {"type": "array",
                                        "items": {"type": "string"}},
                         "body": {"type": "string"}},
                     "required": ["recipients"]}},
    {"name": "compose_email", "source": "compose",
     "description": "Open the system mail composer prefilled "
                    "(to at least one address; subject optional, "
                    "capped at 200 characters; body optional, "
                    "capped at 5000). The user reviews and sends "
                    "in person — the tool never sends by itself. "
                    "Returns {presented, outcome: sent/"
                    "savedDraft/cancelled, sent, note?, "
                    "humanSummary}: a saved draft is its OWN "
                    "outcome (savedDraft, sent=false) and is "
                    "never reported as sent; cancelling is a "
                    "normal outcome, not an error. If no mail "
                    "account is configured the call fails "
                    "honestly before presenting anything. "
                    "Deliberately NOT idempotent (no "
                    "idempotencyKey, never replayed — §115.5.3). "
                    "This source has no iOS system permission: "
                    "it is gated only by the app offering the "
                    "tool.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "to": {"type": "array",
                                "items": {"type": "string"}},
                         "subject": {"type": "string"},
                         "body": {"type": "string"}},
                     "required": ["to"]}},
    {"name": "share_sheet", "source": "compose",
     "description": "Hand text and/or a file (a path inside "
                    "the app's own folder) to the system share "
                    "sheet — at least one of text (capped at "
                    "4000 characters) or path must be given. The "
                    "user picks the destination in person. "
                    "Returns {presented, shared, note?, "
                    "humanSummary}: shared is true only when "
                    "the user actually chose a destination; "
                    "dismissing the sheet returns shared=false "
                    "as a normal result, not an error. "
                    "Deliberately NOT idempotent (no "
                    "idempotencyKey, never replayed — §115.5.3). "
                    "This source has no iOS system permission: "
                    "it is gated only by the app offering the "
                    "tool.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "text": {"type": "string"},
                         "path": {"type": "string"}}}},
    {"name": "shortcut_run", "source": "shortcuts",
     "description": "Run one of the user's Shortcuts BY NAME "
                    "(name capped at 100 characters; input "
                    "optional text, capped at 2000). Shortcuts "
                    "cannot be enumerated — there is no list "
                    "tool, names come from the user. The run "
                    "goes through the x-callback URL form with a "
                    "one-shot nonce: success returns {ran, "
                    "callbackReceived: true, name, result?, "
                    "humanSummary}; a user cancellation returns "
                    "{ran: false, callbackReceived: true, "
                    "outcome: cancelled, note}; if NO callback "
                    "arrives within 100 seconds the call returns "
                    "{initiated: true, callbackReceived: false, "
                    "name, note} — 'started' is all that is "
                    "known then; it must never be upgraded to "
                    "'succeeded'. Deliberately NOT idempotent "
                    "(no idempotencyKey, never replayed — "
                    "§115.5.3): every call really runs the "
                    "shortcut once. This source has no iOS "
                    "system permission: it is gated only by the "
                    "app offering the tool.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "name": {"type": "string"},
                         "input": {"type": "string"}},
                     "required": ["name"]}},
    {"name": "device_info", "source": "deviceinfo",
     "description": "Read the device's own facts for triage "
                    "judgements (battery low => do not assign "
                    "heavy work; offline => do not go querying "
                    "the network): {readAt, model, "
                    "modelIdentifier (the raw identifier string, "
                    "e.g. iPhone17,2 — no marketing-name mapping "
                    "is maintained), systemName, systemVersion, "
                    "batteryState, batteryPercent? (absent with "
                    "batteryKnown: false when unreadable), "
                    "lowPowerMode, storageTotalBytes, "
                    "storageFreeBytes, network (one-shot "
                    "snapshot), humanSummary}. The user's name "
                    "for the phone and the Wi-Fi network name "
                    "are NOT included — both are gated behind a "
                    "paid developer entitlement and are honestly "
                    "absent. This source has no iOS system "
                    "permission: it is gated only by the app "
                    "offering the tool.",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "file_preview", "source": "files",
     "description": "Show one of the app's own files (path "
                    "inside the app's folder, same sandbox "
                    "rules as files_read) to the user in the "
                    "system QuickLook preview, so they can look "
                    "at what the agent produced, in person. The "
                    "call completes when the user dismisses the "
                    "preview. Returns {viewed, path, "
                    "humanSummary}. Deliberately NOT idempotent "
                    "(no idempotencyKey, never replayed — "
                    "§115.5.3): the user must actually be shown "
                    "the file this time. Permission and on/off "
                    "follow the files source, like the other "
                    "files_* tools.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "path": {"type": "string"}},
                     "required": ["path"]}},
    {"name": "file_print", "source": "files",
     "description": "Bring up the system print surface for one "
                    "of the app's own files (path inside the "
                    "app's folder, same sandbox rules as "
                    "files_read). Whether the file can be "
                    "printed is checked first — an unprintable "
                    "file fails honestly. The user drives the "
                    "print surface in person; the result "
                    "follows its completion callback. Returns "
                    "{presented, printed, path, note?, "
                    "humanSummary}: the user cancelling returns "
                    "printed=false as a normal result, not an "
                    "error. Deliberately NOT idempotent (no "
                    "idempotencyKey, never replayed — "
                    "§115.5.3). Permission and on/off follow the "
                    "files source, like the other files_* tools.",
     "inputSchema": {"type": "object",
                     "properties": {
                         "path": {"type": "string"}},
                     "required": ["path"]}},
]
TOOL_BY_NAME = {t["name"]: t for t in TOOLS}
WRITE_TOOLS = {"calendar_create_event", "calendar_update_event",
               "reminders_create", "reminders_complete",
               "clipboard_set", "files_write",
               "alarm_set", "alarm_cancel", "notify_post",
               "open_target",
               "camera_capture", "vision_document_scan",
               "media_playlist_create", "media_playback_control"}
# NEVER idempotency-replayed (DESIGN §114.5.3): auth_biometric's
# whole point is that the user is present at the phone NOW.
# Replaying a stored "confirmed" for a repeated call would
# silently drop that presence gate. The registry declaration
# here is the single line of defence (complexity audit
# 2026-11-11 item 2 removed the duplicate hard exclusion that
# used to sit inside the dispatch): the tool is not in
# WRITE_TOOLS and takes no idempotencyKey, so the replay path
# never opens for it. A bridge-side retry of a biometric call
# must forward to the phone and ask again, live, every time.
# §115.5.3 adds the batch-four presence tools on the same
# reasoning: call_start / compose_sms / compose_email /
# share_sheet / shortcut_run / file_preview / file_print change
# no state themselves — they hand a system surface to the user,
# whose being there THIS time is the entire premise. Replaying
# a stored "the composer was opened" would tell the agent this
# call reached the user when it did not. Same registry gate:
# none of them is in WRITE_TOOLS or takes an idempotencyKey.
# (file_preview / file_print ride the
# files source, but as presence tools they belong here, not in
# the files_write replay family.)
NEVER_REPLAY_TOOLS = {"auth_biometric",
                      "call_start", "compose_sms", "compose_email",
                      "share_sheet", "shortcut_run",
                      "file_preview", "file_print"}
# Sources with no iOS system permission at all (DESIGN §111.2, and
# §113.2 for opener): the app reports them "granted" by
# construction, and the bridge must never permission-gate them
# whatever a registration payload says — the session's tools list
# is their only gate (not offered => tool_unavailable, like every
# other tool). §114.2 adds four more of the same kind: vision and
# translate are pure on-device computation; biometric has no
# switchable permission at all (consent is given in the system
# prompt at each call); ondevice has a device-availability gate
# instead of a permission, expressed through the tools list (the
# app omits ondevice_model_run on ineligible devices, so its
# absence there is normal, never an anomaly). Real-permission
# sources (alarm, notifications, camera, ...) are NOT in this
# set: the app reports their true system state and the bridge
# may answer permission_denied before waking the phone.
# §115.2 adds three more of the no-permission kind: compose
# (dial/compose/share surfaces are guarded by the user acting
# on the system surface itself), shortcuts (guarded by name +
# callback), deviceinfo (permission-free facts read live).
# file_preview / file_print introduce no new key: they ride the
# existing files entry. The §115 real-permission sources —
# location and media — are NOT in this set, exactly like alarm,
# notifications and camera: the app reports their true state
# and the bridge may pre-intercept with permission_denied.
NO_PERMISSION_SOURCES = {"clipboard", "files", "opener",
                         "vision", "translate", "ondevice",
                         "biometric",
                         "compose", "shortcuts", "deviceinfo"}

# ---------------------------------------------------------------- state
device_sync.init(DATA_DIR)
_cond = threading.Condition()
_session: dict | None = None          # current device session (single)
_pending: dict[str, dict] = {}        # callId -> call record
_write_keys_path = DATA_DIR / "write-keys.json"
_audit_path = DATA_DIR / "audit.jsonl"


def _now() -> float:
    return time.time()


def _session_online_locked() -> bool:
    return (_session is not None
            and _now() - _session["lastSeen"] <= SESSION_TTL)


def _audit(entry: dict) -> None:
    try:
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        with open(_audit_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError as e:
        print(f"[device-bridge] audit write failed: {e}", flush=True)


def _load_write_keys() -> dict:
    try:
        return json.loads(_write_keys_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def _save_write_key(key: str, tool: str, object_id) -> None:
    keys = _load_write_keys()
    keys[key] = {"tool": tool, "objectId": object_id, "ts": _now()}
    try:
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        tmp = _write_keys_path.with_suffix(".tmp")
        tmp.write_text(json.dumps(keys, ensure_ascii=False),
                       encoding="utf-8")
        os.chmod(tmp, 0o600)
        tmp.replace(_write_keys_path)
    except OSError as e:
        print(f"[device-bridge] write-key save failed: {e}", flush=True)


# ---------------------------------------------------------------- engine
class CallError(Exception):
    def __init__(self, code: str, message: str, fields: dict | None = None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.call_id = None  # set when a call record was created
        # §244 P-1: structured payload for permission-class failures
        # ({source, state, blockerLayer, nextAction, resumeToken?}),
        # merged verbatim into the MCP error object. The message is
        # Chinese human copy produced here -- one source of truth, the
        # app and the model never re-word it.
        self.fields = fields or {}


# ------------------------------------------------- §244 permission flow
# Parked calls: a tool call blocked on authorization lives here under
# a single-use resume token until the user authorizes (in-chat ask,
# settings round-trip, or agent-call switch) and the app calls
# POST /device/resume. Arguments are kept because re-dispatch needs
# them (write calls keep their original idempotencyKey, so a resumed
# write is still one user confirmation = one execution). The file
# sits in the device data dir under the same 0600 discipline as the
# write-key ledger; entries expire after PARK_TTL and are pruned on
# every load. Audit lines never include arguments -- parks are
# operational state, not audit.
_parks_path = DATA_DIR / "permission-parks.json"
_parks_lock = threading.Lock()

_SOURCE_LABELS = {
    "calendar": "日历", "contacts": "通讯录", "reminders": "提醒事项",
    "photos": "照片", "motion": "步数", "alarm": "闹钟",
    "notifications": "通知", "camera": "相机", "location": "定位",
    "media": "媒体库", "health": "健康", "home": "家庭",
    "clipboard": "剪贴板", "files": "文件", "opener": "打开目标",
    "vision": "视觉识别", "translate": "翻译", "ondevice": "端上智能",
    "biometric": "本人确认", "compose": "撰写", "shortcuts": "快捷指令",
    "deviceinfo": "设备信息",
}
_STATE_LABELS = {
    "notDetermined": "还没授权过", "denied": "已被拒绝",
    "restricted": "被系统限制", "writeOnly": "只有写入权限",
    "granted": "已授权",
}


def _source_label(source: str) -> str:
    return _SOURCE_LABELS.get(source, source)


def _load_parks() -> dict:
    try:
        parks = json.loads(_parks_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    now = _now()
    return {t: p for t, p in parks.items()
            if isinstance(p, dict) and p.get("expiresAt", 0) > now}


def _save_parks(parks: dict) -> None:
    try:
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        tmp = _parks_path.with_suffix(".tmp")
        tmp.write_text(json.dumps(parks, ensure_ascii=False),
                       encoding="utf-8")
        os.chmod(tmp, 0o600)
        tmp.replace(_parks_path)
    except OSError as e:
        print(f"[device-bridge] park save failed: {e}", flush=True)


def _park_call(tool: str, arguments: dict, source: str,
               layer: str, kind: str = "live") -> str:
    token = "park-" + secrets.token_hex(8)
    with _parks_lock:
        parks = _load_parks()
        parks[token] = {"tool": tool, "arguments": arguments,
                        "source": source, "blockerLayer": layer,
                        "kind": kind, "createdAt": _now(),
                        "expiresAt": _now() + PARK_TTL,
                        # §261: how the in-chat ask round ended
                        # (unanswered / deferred / undeliverable);
                        # None until an ask round concludes.
                        "askOutcome": None}
        _save_parks(parks)
    return token


def _mark_park_ask_outcome(token: str, outcome: str) -> None:
    """Record how the ask round for a park ended (§261: the
    bridge states it explicitly instead of folding timeout
    and user-deferred into the same silent 'parked')."""
    with _parks_lock:
        parks = _load_parks()
        park = parks.get(token)
        if park is not None:
            park["askOutcome"] = outcome
            _save_parks(parks)


def _peek_park(token: str) -> dict | None:
    with _parks_lock:
        return _load_parks().get(token)


def _drop_park(token: str) -> None:
    with _parks_lock:
        parks = _load_parks()
        if token in parks:
            del parks[token]
            _save_parks(parks)


def _consume_park(token: str) -> dict | None:
    with _parks_lock:
        parks = _load_parks()
        park = parks.pop(token, None)
        if park is not None:
            _save_parks(parks)
        return park


def _permission_fields(source: str, state: str, layer: str,
                       next_action: str, token: str | None = None,
                       asked: bool = False) -> dict:
    fields = {"source": source, "state": state,
              "blockerLayer": layer, "nextAction": next_action}
    if token:
        fields["resumeToken"] = token
        park = _peek_park(token)
        if park is not None:
            # §261: the park's own stamps ride along so any
            # card built from these fields starts its 24h
            # clock at park time, same origin as this side.
            fields["parkedAt"] = park.get("createdAt")
            fields["expiresAt"] = park.get("expiresAt")
            # Surface the ask outcome explicitly when the
            # park recorded one (e.g. unanswered after a
            # timeout) instead of folding it into silence.
            if park.get("askOutcome"):
                fields["askOutcome"] = park["askOutcome"]
    if asked:
        fields["askedAndDenied"] = True
    return fields


def _ask_permission(source: str, tool_name: str, token: str) -> str:
    """Deliver a permission_ask pseudo-call over the poll channel and
    wait for the user's in-chat answer. Returns granted / denied /
    parked (the user deferred, or the ask could not be presented).
    The pseudo-call carries the pre-created resume token, so the card
    the app shows can resume the parked call whatever happens next."""
    call_id = "call-" + secrets.token_hex(6)
    # §261: the card's 24h clock starts at park time on this
    # side; carry both stamps so the app card adopts the same
    # origin instead of re-starting its own clock on receipt.
    park = _peek_park(token) or {}
    rec = {"callId": call_id, "tool": PERMISSION_ASK_TOOL,
           "kind": "permission_ask",
           "arguments": {"source": source, "tool": tool_name,
                         "resumeToken": token,
                         "parkedAt": park.get("createdAt"),
                         "expiresAt": park.get("expiresAt")},
           "createdAt": _now(), "delivered": False,
           "event": threading.Event(), "response": None,
           "sessionId": _session["sessionId"]}
    with _cond:
        _pending[call_id] = rec
        _cond.notify_all()
    if not rec["event"].wait(ASK_TIMEOUT):
        with _cond:
            _pending.pop(call_id, None)
        # §261: a timeout is not the user deferring -- say so
        # on the park so the app card can align explicitly.
        _mark_park_ask_outcome(token, "unanswered")
        return "parked"
    with _cond:
        _pending.pop(call_id, None)
    resp = rec["response"] or {}
    if resp.get("status") == "error":
        # Session replaced / device went away mid-ask: the park and
        # the card both survive; the user can still resume later.
        _mark_park_ask_outcome(token, "undeliverable")
        return "parked"
    decision = (resp.get("result") or {}).get("decision")
    if decision == "parked":
        _mark_park_ask_outcome(token, "deferred")
    return decision if decision in ("granted", "denied", "parked") \
        else "parked"


def _permission_gate(name: str, tool: dict, arguments: dict,
                     resume: bool = False) -> None:
    """§244 gate, run before a live call is queued. Raises CallError
    for every blocked layer, in the fixed order of spec §7.4:
    system permission -> agent-call switch -> wiring. Returns None
    when the call may proceed (the phone re-checks live state at
    execution time regardless -- this gate only decides whether the
    phone needs waking and what the user must be asked first).

    resume=True is the /device/resume path: the app initiates it
    after its own fresh on-device read, so the snapshot permission
    and switch checks are skipped on purpose (a settings round-trip
    makes the snapshot stale by construction); the wiring check and
    the phone's live re-check still apply."""
    source = tool["source"]
    with _cond:
        if not _session_online_locked():
            raise CallError(
                "device_offline",
                "the phone app is not online; no data was read and "
                "nothing was written")
        perms = _session["permissions"]
        agent_call = _session.get("agentCall") or {}
        caps = _session.get("capabilities") or set()
        offered = _session["tools"]
    if resume:
        if name not in offered:
            raise CallError(
                "tool_unavailable",
                f"the app did not offer tool {name} in this session",
                _permission_fields(source, "granted", "wiring", "none"))
        return
    if source not in NO_PERMISSION_SOURCES:
        state = perms.get(source, "notDetermined")
        if state != "granted":
            label = _source_label(source)
            if state == "notDetermined" \
                    and PERMISSION_ASK_CAPABILITY in caps:
                token = _park_call(name, arguments, source, "permission")
                decision = _ask_permission(source, name, token)
                if decision == "granted":
                    _drop_park(token)
                    return  # proceed; phone re-checks live anyway
                if decision == "denied":
                    raise CallError(
                        "permission_denied",
                        f"刚才在对话里问过一次，「{label}」的权限没有给。"
                        "卡片还留在对话里，去设置里打开后回来，"
                        "这件事会自动接着办。",
                        _permission_fields(
                            source, "denied", "permission",
                            "open_settings", token, asked=True))
                raise CallError(
                    "permission_required",
                    f"「{label}」还没授权过，我在对话里放了一张授权卡，"
                    "点一下就能当场给；给了之后这件事会自动接着办，"
                    "不用再说一遍。",
                    _permission_fields(
                        source, state, "permission", "ask_in_chat",
                        token))
            if state == "notDetermined":
                # App without ask support: pre-§244 behaviour, but
                # structured and in Chinese like every other message.
                raise CallError(
                    "permission_denied",
                    f"「{label}」还没授权过，手机这边没有弹窗问过，"
                    "这次先没办成。",
                    _permission_fields(
                        source, state, "permission", "none"))
            token = _park_call(name, arguments, source, "permission")
            raise CallError(
                "permission_required",
                f"「{label}」的权限现在是「{_STATE_LABELS.get(state, state)}」，"
                "系统不允许再弹窗问。我在对话里放了一张卡，"
                "去设置里打开后回到对话，这件事会自动接着办。",
                _permission_fields(
                    source, state, "permission", "open_settings",
                    token))
    if source in agent_call and not agent_call[source]:
        token = _park_call(name, arguments, source, "agentSwitch")
        raise CallError(
            "permission_required",
            f"「{_source_label(source)}」的权限已经开着，差的是这一件的"
            "智能体调用开关还没打开。我在对话里放了一张卡，"
            "点「打开并继续」就能接着办。",
            _permission_fields(
                source, "granted", "agentSwitch", "open_switch",
                token))
    if name not in offered:
        raise CallError(
            "tool_unavailable",
            f"the app did not offer tool {name} in this session",
            _permission_fields(source, "granted", "wiring", "none"))


# ------------------------------------------------------- sync dispatch
# Query tools served from the synced copy. Same-name tools with a live
# equivalent fall back to a live read when the copy is empty; the
# fallback result is stamped so freshness claims stay honest.
_SYNC_ONLY = {
    "contacts_count": lambda a: device_sync.contacts_count(),
    "contacts_stats": lambda a: device_sync.contacts_stats(),
    "contacts_list": lambda a: device_sync.contacts_list(
        a.get("limit", 50), a.get("offset", 0)),
    "contacts_get": lambda a: device_sync.contacts_get(
        a.get("contactId", "")),
    "calendar_search": lambda a: device_sync.calendar_search(
        a.get("query", "")),
    "calendar_count": lambda a: device_sync.calendar_count(
        device_sync._parse_ts(a.get("start")),
        device_sync._parse_ts(a.get("end"))),
    "reminders_count": lambda a: device_sync.reminders_count(),
    "reminders_search": lambda a: device_sync.reminders_search(
        a.get("query", "")),
    "photos_stats": lambda a: device_sync.photos_stats(),
    "photos_recent": lambda a: device_sync.photos_recent(
        a.get("limit", 50)),
    "motion_steps_summary": lambda a: device_sync.motion_summary(
        a.get("days", 7)),
}
_FALLBACK_NOTE = "这次是现查的，副本里还没有这份数据"


def _sync_call(name: str, arguments: dict):
    """Serve from the copy. Returns the result dict, or None when the
    copy is empty and the caller should try the live path."""
    try:
        return _SYNC_ONLY[name](arguments)
    except device_sync.CopyEmpty:
        return None
    except device_sync.SyncError as e:
        if e.code == "permission_revoked":
            # §244 P-5: the copy is stop-supplied because the
            # permission is off -- that is an authorization blocker,
            # not a data error. Park the query so it resumes once
            # the user re-grants and the app re-syncs.
            dataset = TOOL_BY_NAME[name]["source"]
            token = _park_call(name, arguments, dataset, "permission",
                               kind="sync")
            raise CallError(
                "permission_required",
                f"「{_source_label(dataset)}」的权限已经关了，"
                "同步副本暂停提供。我在对话里放了一张卡，"
                "去设置里打开、等它同步好，这条查询会自动接着办。",
                _permission_fields(
                    dataset, "denied", "permission", "open_settings",
                    token))
        raise CallError(e.code, e.message)


def _raise_copy_empty(name: str, arguments: dict):
    """An empty-copy sync query: decide whether the real blocker is
    authorization (§244 P-5) or simply a copy that was never made.
    Always raises."""
    dataset = TOOL_BY_NAME[name]["source"]
    with _cond:
        online = _session_online_locked()
        snap = _session["permissions"].get(dataset) \
            if online and _session else None
        caps = _session.get("capabilities") \
            if online and _session else set()
    label = _source_label(dataset)
    if online and snap == "notDetermined" \
            and PERMISSION_ASK_CAPABILITY in (caps or set()):
        token = _park_call(name, arguments, dataset, "permission",
                           kind="sync")
        decision = _ask_permission(dataset, name, token)
        if decision == "granted":
            # Permission is in hand; the copy lands when the app
            # runs its first sync, then the app resumes this query.
            raise CallError(
                "permission_required",
                f"「{label}」的权限已经给好了，手机正在把数据同步过来，"
                "同步完这条查询会自动接着办，不用再问一遍。",
                _permission_fields(
                    dataset, "granted", "permission", "ask_in_chat",
                    token))
        if decision == "denied":
            raise CallError(
                "permission_denied",
                f"刚才在对话里问过一次，「{label}」的权限没有给。"
                "卡片还留在对话里，去设置里打开后回来，"
                "这条查询会自动接着办。",
                _permission_fields(
                    dataset, "denied", "permission", "open_settings",
                    token, asked=True))
        raise CallError(
            "permission_required",
            f"「{label}」还没授权过，我在对话里放了一张授权卡，"
            "点一下就能当场给；给了之后这条查询会自动接着办。",
            _permission_fields(
                dataset, snap, "permission", "ask_in_chat", token))
    if online and snap in ("denied", "restricted", "writeOnly"):
        token = _park_call(name, arguments, dataset, "permission",
                           kind="sync")
        raise CallError(
            "permission_required",
            f"「{label}」的权限现在是「{_STATE_LABELS.get(snap, snap)}」，"
            "系统不允许再弹窗问。我在对话里放了一张卡，"
            "去设置里打开后回到对话，这条查询会自动接着办。",
            _permission_fields(
                dataset, snap, "permission", "open_settings", token))
    try:
        st = device_sync.dataset_state(dataset)
    except Exception:
        st = None
    if st is not None and st.get("permission_state") == "revoked":
        token = _park_call(name, arguments, dataset, "permission",
                           kind="sync")
        raise CallError(
            "permission_required",
            f"「{label}」的权限已经关了，同步副本暂停提供。"
            "我在对话里放了一张卡，去设置里打开、等它同步好，"
            "这条查询会自动接着办。",
            _permission_fields(
                dataset, "denied", "permission", "open_settings",
                token))
    raise CallError(
        "sync_copy_empty",
        f"「{label}」还没有同步到服务器，暂时答不了；"
        "打开 App 让它同步一次，就能查了。",
        _permission_fields(dataset, snap or "granted", "sync",
                           "none"))


def _calendar_list_events(arguments: dict):
    """Copy only when its coverage fully contains the window;
    otherwise one whole live call for the full window.

    Complexity audit 2026-11-11 item 2: the old hybrid stitched
    copy + live segments together (segment arithmetic plus an
    "uncovered" ledger). That whole calculus is gone -- a window
    the copy cannot vouch for end to end is re-asked whole, so a
    result is never a stitched mix of two sources."""
    start_ts = device_sync._parse_ts(arguments.get("start"))
    end_ts = device_sync._parse_ts(arguments.get("end"))
    if start_ts is None or end_ts is None or end_ts <= start_ts:
        raise CallError("bad_arguments",
                        "start/end must be ISO 8601 with end after start")
    copy_seen = False
    try:
        st = device_sync.dataset_state("calendar")
        if st is None or st["synced_at"] is None:
            raise device_sync.CopyEmpty("calendar")
        copy_seen = True
        cov_start, cov_end = device_sync.calendar_coverage_epochs(st)
        if cov_start is not None and cov_end is not None \
                and cov_start <= start_ts and end_ts <= cov_end:
            events, st = device_sync.calendar_copy_events(
                start_ts, end_ts)
            result = device_sync.envelope("calendar", st)
            result.update({"events": events,
                           "servedBy": "sync_copy"})
            return result, None, None
    except device_sync.CopyEmpty:
        pass  # no copy at all: fall through to the whole live call
    except device_sync.SyncError as e:
        raise CallError(e.code, e.message)
    result, object_id, call_id = _live_tool_call(
        "calendar_list_events", arguments)
    if isinstance(result, dict):
        result = dict(result)
        result["servedBy"] = "live_fallback"
        result["note"] = ("副本覆盖不到这个时间段，这次是整段现查的"
                          if copy_seen else _FALLBACK_NOTE)
    return result, object_id, call_id


def run_tool_call(name: str, arguments: dict):
    """Execute one tool call. Returns (result_obj, object_id, call_id).
    Raises CallError with a structured code on any honest failure."""
    tool = TOOL_BY_NAME.get(name)
    if tool is None:
        raise CallError("unknown_tool", f"no such tool: {name}")
    if name == "device_status":
        sync = device_sync.status_all()
        with _cond:
            if _session is None:
                return {"online": False, "sync": sync}, None, None
            return {"online": _session_online_locked(),
                    "deviceId": _session["deviceId"],
                    "appVersion": _session["appVersion"],
                    "lastSeen": _session["lastSeen"],
                    "permissions": _session["permissions"],
                    "tools": sorted(_session["tools"]),
                    "sync": sync}, None, None

    if name in _SYNC_ONLY:
        result = _sync_call(name, arguments)
        if result is None:
            _raise_copy_empty(name, arguments)
        return result, None, None
    if name == "calendar_list_events":
        return _calendar_list_events(arguments)
    if name in ("contacts_search", "reminders_list"):
        dataset = "contacts" if name == "contacts_search" \
            else "reminders"
        try:
            if name == "contacts_search":
                result = device_sync.contacts_search(
                    arguments.get("query", ""))
            else:
                result = device_sync.reminders_list(
                    arguments.get("listName"))
            return result, None, None
        except device_sync.CopyEmpty:
            pass  # fall through to the live path below
        except device_sync.SyncError as e:
            raise CallError(e.code, e.message)
        result, object_id, call_id = _live_tool_call(name, arguments)
        if isinstance(result, dict):
            result = dict(result)
            result["servedBy"] = "live_fallback"
            result["note"] = _FALLBACK_NOTE
        return result, object_id, call_id

    result, object_id, call_id = _live_tool_call(name, arguments)
    dataset = device_sync.WRITE_DATASET.get(name)
    if dataset and isinstance(result, dict) \
            and not result.get("idempotentReplay"):
        device_sync.mark_pending_write(dataset)
    return result, object_id, call_id


def _live_tool_call(name: str, arguments: dict, resume: bool = False):
    tool = TOOL_BY_NAME.get(name)
    # Replay eligibility is decided by the registry alone:
    # NEVER_REPLAY_TOOLS are simply absent from WRITE_TOOLS
    # (complexity audit item 2 removed the second hard exclusion
    # that used to sit here as a duplicate line of defence).
    idem = arguments.get("idempotencyKey") \
        if name in WRITE_TOOLS \
        else None
    if idem:
        stored = _load_write_keys().get(idem)
        if stored is not None:
            return {"idempotentReplay": True, "tool": name,
                    "objectId": stored.get("objectId")}, stored.get(
                        "objectId"), None

    # §244: authorization layers are decided by the gate (it may
    # wait on an in-chat permission_ask); the queueing below only
    # re-checks liveness, the phone re-checks everything live at
    # execution time.
    _permission_gate(name, tool, arguments, resume=resume)

    with _cond:
        if not _session_online_locked():
            raise CallError(
                "device_offline",
                "the phone app is not online; no data was read and "
                "nothing was written")
        call_id = "call-" + secrets.token_hex(6)
        rec = {"callId": call_id, "tool": name, "arguments": arguments,
               "createdAt": _now(), "delivered": False,
               "event": threading.Event(), "response": None,
               "sessionId": _session["sessionId"]}
        _pending[call_id] = rec
        _cond.notify_all()

    timeout = TOOL_TIMEOUTS.get(name, CALL_TIMEOUT)
    if not rec["event"].wait(timeout):
        with _cond:
            _pending.pop(call_id, None)
        err = CallError(
            "device_timeout",
            f"the phone did not answer within {timeout:.0f}s")
        err.call_id = call_id
        raise err
    with _cond:
        _pending.pop(call_id, None)
    resp = rec["response"] or {}
    if resp.get("status") == "error":
        err = resp.get("error") or {}
        cerr = CallError(err.get("code", "device_error"),
                         err.get("message", "device returned an error"))
        if err.get("code") == "permission_denied":
            # §244 P-1: the phone reports the live state it just
            # read; pass it through structured like every other
            # permission failure.
            cerr.fields = _permission_fields(
                tool["source"], err.get("state") or "denied",
                "permission", "none")
        cerr.call_id = call_id
        raise cerr
    result = resp.get("result") or {}
    object_id = result.get("objectId") if isinstance(result, dict) \
        else None
    if idem:
        _save_write_key(idem, name, object_id)
    return result, object_id, call_id


# ---------------------------------------------------------------- http
def _mcp_result_text(obj) -> list:
    return [{"type": "text",
             "text": json.dumps(obj, ensure_ascii=False)}]


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # access log: method/path/status
        print(f"[device-bridge] {self.command} {self.path} "
              f"-> {args[1] if len(args) > 1 else ''}", flush=True)

    # -- plumbing ------------------------------------------------------
    def _send(self, code: int, obj=None, raw: bytes | None = None):
        body = raw if raw is not None else (
            json.dumps(obj, ensure_ascii=False).encode("utf-8")
            if obj is not None else b"")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _body(self) -> dict:
        n = int(self.headers.get("Content-Length") or 0)
        if n > MAX_BODY:
            raise ValueError("body too large")
        raw = self.rfile.read(n) if n else b""
        return json.loads(raw.decode("utf-8")) if raw else {}

    def _authed(self) -> bool:
        if not API_KEY:
            return False  # fail closed
        got = self.headers.get("Authorization") or ""
        return hmac.compare_digest(got, f"Bearer {API_KEY}")

    # -- device channel --------------------------------------------------
    def _device_session(self):
        global _session
        body = self._body()
        sid = "sess-" + secrets.token_hex(6)
        with _cond:
            old = _session
            if old is not None:  # new registration replaces the old one
                for rec in _pending.values():
                    if rec["sessionId"] == old["sessionId"] \
                            and not rec["event"].is_set():
                        rec["response"] = {
                            "status": "error",
                            "error": {"code": "device_offline",
                                      "message": "session replaced"}}
                        rec["event"].set()
            _session = {"sessionId": sid,
                        "deviceId": body.get("deviceId", ""),
                        "appVersion": body.get("appVersion", ""),
                        "permissions": body.get("permissions") or {},
                        "agentCall": body.get("agentCall") or {},
                        "capabilities":
                            set(body.get("capabilities") or []),
                        "tools": set(body.get("tools") or []),
                        "connectedAt": _now(), "lastSeen": _now()}
            _cond.notify_all()
        self._send(201, {"sessionId": sid, "pollWaitSec": POLL_MAX_WAIT,
                         "callTimeoutSec": CALL_TIMEOUT,
                         "sessionTtlSec": SESSION_TTL})

    def _device_touch(self, body) -> bool:
        with _cond:
            if _session is None \
                    or body.get("sessionId") != _session["sessionId"]:
                return False
            _session["lastSeen"] = _now()
            return True

    def _device_poll(self, qs):
        sid = (qs.get("sessionId") or [""])[0]
        wait = min(float((qs.get("wait") or [POLL_MAX_WAIT])[0]),
                   POLL_MAX_WAIT)
        deadline = _now() + wait
        with _cond:
            while True:
                if _session is None or _session["sessionId"] != sid:
                    self._send(409, {"error": "unknown_session"})
                    return
                _session["lastSeen"] = _now()
                for rec in _pending.values():
                    if rec["sessionId"] == sid and not rec["delivered"]:
                        rec["delivered"] = True
                        self._send(200, {"call": {
                            "callId": rec["callId"], "tool": rec["tool"],
                            "kind": rec.get("kind", "tool"),
                            "arguments": rec["arguments"],
                            "createdAt": rec["createdAt"]}})
                        return
                remain = deadline - _now()
                if remain <= 0:
                    self._send(200, {"call": None})
                    return
                _cond.wait(timeout=remain)

    def _device_respond(self):
        body = self._body()
        with _cond:
            rec = _pending.get(body.get("callId") or "")
            if rec is None or _session is None \
                    or body.get("sessionId") != _session["sessionId"]:
                self._send(404, {"error": "unknown_call"})
                return
            _session["lastSeen"] = _now()
            if not rec["event"].is_set():
                rec["response"] = {
                    "status": body.get("status", "error"),
                    "result": body.get("result"),
                    "error": body.get("error")}
                rec["event"].set()
            _cond.notify_all()
        self._send(200, {"ok": True})

    def _device_resume(self):
        """§244 P-4: the app calls this after the user authorized
        (settings round-trip, switch flip, or first sync done). The
        parked call is re-dispatched once -- the token is consumed
        only when the dispatch actually happens -- and the tool
        result (or a structured error) returns in this response, so
        the card in the chat can show the outcome. The phone
        re-checks live state at execution; the bridge only waits
        briefly for the tool to be offered again (the app
        re-registers after a settings round-trip)."""
        body = self._body()
        token = body.get("resumeToken") or ""
        park = _peek_park(token)
        if park is None:
            self._send(404, {"ok": False,
                             "error": "unknown_or_expired_token"})
            return
        started = _now()
        entry = {"ts": started, "callId": None, "tool": park["tool"],
                 "source": "resume", "status": "", "durationMs": 0,
                 "errorCode": None}
        deadline = _now() + 5
        while True:
            with _cond:
                online = _session_online_locked()
                offered = bool(online) \
                    and park["tool"] in _session["tools"]
            if offered or _now() > deadline:
                break
            time.sleep(0.25)
        if not online:
            entry["status"] = "error"
            entry["errorCode"] = "device_offline"
            entry["durationMs"] = int((_now() - started) * 1000)
            _audit(entry)
            self._send(409, {"ok": False, "error": "device_offline",
                             "message": "手机现在不在线，等它回到前台再试"})
            return
        _consume_park(token)  # single use, from here on it is spent
        try:
            if park.get("kind") == "sync":
                result = _sync_call(park["tool"], park["arguments"])
                if result is None:
                    raise CallError(
                        "sync_copy_empty",
                        "副本还没同步好，再等同步完成试一次。",
                        _permission_fields(
                            park["source"], "granted", "sync", "none"))
            else:
                result, _oid, call_id = _live_tool_call(
                    park["tool"], park["arguments"], resume=True)
                entry["callId"] = call_id
            entry["status"] = "ok"
            self._send(200, {"ok": True, "result": result})
        except CallError as e:
            entry["status"] = "error"
            entry["errorCode"] = e.code
            entry["callId"] = e.call_id
            payload = {"ok": False, "error": e.code,
                       "message": e.message}
            payload.update(e.fields)
            self._send(200, payload)
        entry["durationMs"] = int((_now() - started) * 1000)
        _audit(entry)

    def _device_park_state(self):
        """§261: the bridge is the single source of truth for
        whether a parked call still exists. The app reconciles
        its local permission cards against this read face --
        gone means gone (expired/consumed/dropped), and the
        park's own expiresAt is the one 24h clock both sides
        read. Read-only: peeking never consumes the token.
        Arguments are never returned (they stay bridge-side
        operational state, as with the parks file itself)."""
        body = self._body()
        wanted = body.get("resumeToken") or ""
        park = _peek_park(wanted) if wanted else None
        if park is None:
            self._send(200, {"ok": True, "exists": False})
            return
        self._send(200, {"ok": True, "exists": True, "park": {
            "source": park.get("source"),
            "tool": park.get("tool"),
            "blockerLayer": park.get("blockerLayer"),
            "kind": park.get("kind"),
            "createdAt": park.get("createdAt"),
            "expiresAt": park.get("expiresAt"),
            "askOutcome": park.get("askOutcome"),
        }})

    def _device_disconnect(self):
        global _session
        body = self._body()
        with _cond:
            if _session is not None \
                    and body.get("sessionId") == _session["sessionId"]:
                for rec in _pending.values():
                    if rec["sessionId"] == _session["sessionId"] \
                            and not rec["event"].is_set():
                        rec["response"] = {
                            "status": "error",
                            "error": {"code": "device_offline",
                                      "message": "device disconnected"}}
                        rec["event"].set()
                _session = None
                _cond.notify_all()
        self._send(200, {"ok": True})

    # -- sync channel ----------------------------------------------------
    def _sync_batch(self):
        body = self._body()
        try:
            out = device_sync.stage_batch(
                body.get("dataset", ""), body.get("batchId", ""),
                body.get("records") or [], body.get("mode", "full"),
                body.get("meta"))
        except device_sync.SyncError as e:
            self._send(400, {"error": e.code, "message": e.message})
            return
        self._send(200, out)

    def _sync_complete(self):
        body = self._body()
        started = _now()
        try:
            out = device_sync.complete(
                body.get("dataset", ""), body.get("batchId", ""),
                body.get("expectedTotal", -1),
                body.get("deviceCompletedAt"), body.get("mode"),
                body.get("coverage"), body.get("aggregates"),
                body.get("removedIds"), body.get("authRange"),
                body.get("rangeNote"), body.get("permissionState"))
        except device_sync.SyncError as e:
            _audit({"ts": started, "callId": None,
                    "tool": f"sync:{body.get('dataset')}",
                    "source": "sync", "status": "error",
                    "durationMs": int((_now() - started) * 1000),
                    "errorCode": e.code})
            code = 409 if e.code == "sync_count_mismatch" else 400
            self._send(code, {"error": e.code, "message": e.message})
            return
        _audit({"ts": started, "callId": None,
                "tool": f"sync:{out['dataset']}", "source": "sync",
                "status": "ok",
                "durationMs": int((_now() - started) * 1000),
                "errorCode": None, "count": out["total_in_store"]})
        self._send(200, out)

    def _sync_manifest(self):
        body = self._body()
        try:
            out = device_sync.manifest_compare(
                body.get("dataset", ""), body.get("entries") or [])
        except device_sync.SyncError as e:
            self._send(400, {"error": e.code, "message": e.message})
            return
        self._send(200, out)

    def _sync_state(self):
        body = self._body()
        try:
            out = device_sync.report_state(
                body.get("dataset", ""), body.get("permissionState"),
                body.get("authRange"), body.get("rangeNote"))
        except device_sync.SyncError as e:
            self._send(400, {"error": e.code, "message": e.message})
            return
        self._send(200, out)

    def _sync_delete(self):
        body = self._body()
        dataset = body.get("dataset")
        targets = [dataset] if dataset else None
        if targets and targets[0] not in device_sync.DATASETS:
            self._send(400, {"error": "unknown_dataset"})
            return
        out = device_sync.delete_copies(targets)
        _audit({"ts": _now(), "callId": None, "tool": "sync:delete",
                "source": "sync", "status": "ok", "durationMs": 0,
                "errorCode": None,
                "count": len(out["deleted"])})
        self._send(200, out)

    def _sync_status(self):
        self._send(200, {"datasets": device_sync.status_all()})

    # -- MCP facade ------------------------------------------------------
    def _mcp(self):
        body = self._body()
        rid = body.get("id")
        method = body.get("method", "")
        if rid is None:  # notification
            self._send(202)
            return
        if method == "initialize":
            self._send(200, {"jsonrpc": "2.0", "id": rid, "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "device-bridge",
                               "version": "0.1.0"},
                "instructions": (
                    "When a device tool returns permission_required "
                    "or permission_denied, an authorization card is "
                    "already waiting in the user's chat: say the fact "
                    "in one short sentence and point to the card. "
                    "Never write settings tutorials and never guess "
                    "at causes. When a tool returns device_timeout, "
                    "say only that the phone did not answer this time "
                    "and offer to retry; do not list possible "
                    "reasons.")}})
            return
        if method == "ping":
            self._send(200, {"jsonrpc": "2.0", "id": rid, "result": {}})
            return
        if method == "tools/list":
            tools = [{"name": t["name"], "description": t["description"],
                      "inputSchema": t["inputSchema"]} for t in TOOLS]
            self._send(200, {"jsonrpc": "2.0", "id": rid,
                             "result": {"tools": tools}})
            return
        if method == "tools/call":
            params = body.get("params") or {}
            name = params.get("name", "")
            arguments = params.get("arguments") or {}
            started = _now()
            entry = {"ts": started, "callId": None, "tool": name,
                     "source": "mcp", "status": "", "durationMs": 0,
                     "errorCode": None}
            try:
                result, object_id, call_id = run_tool_call(name, arguments)
                entry["status"] = "ok"
                entry["callId"] = call_id
                if object_id:
                    entry["objectId"] = object_id
                payload = {"jsonrpc": "2.0", "id": rid, "result": {
                    "content": _mcp_result_text(result),
                    "isError": False}}
            except CallError as e:
                entry["status"] = "error"
                entry["errorCode"] = e.code
                entry["callId"] = e.call_id
                error_obj = {"error": e.code, "message": e.message}
                error_obj.update(e.fields)
                payload = {"jsonrpc": "2.0", "id": rid, "result": {
                    "content": _mcp_result_text(error_obj),
                    "isError": True}}
            entry["durationMs"] = int((_now() - started) * 1000)
            _audit(entry)
            self._send(200, payload)
            return
        self._send(200, {"jsonrpc": "2.0", "id": rid, "error": {
            "code": -32601, "message": f"method not found: {method}"}})

    # -- routing ---------------------------------------------------------
    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/health":
            with _cond:
                online = _session_online_locked()
            self._send(200, {"ok": True, "service": "device-bridge",
                             "sessionOnline": online})
            return
        if not self._authed():
            self._send(401, {"error": "unauthorized"})
            return
        if u.path == "/device/poll":
            self._device_poll(parse_qs(u.query))
            return
        if u.path == "/device/sync/status":
            self._sync_status()
            return
        self._send(404, {"error": "not_found"})

    def do_POST(self):
        u = urlparse(self.path)
        if not self._authed():
            self._send(401, {"error": "unauthorized"})
            return
        try:
            if u.path == "/device/session":
                self._device_session()
            elif u.path == "/device/heartbeat":
                ok = self._device_touch(self._body())
                self._send(200 if ok else 404,
                           {"ok": ok} if ok else
                           {"error": "unknown_session"})
            elif u.path == "/device/respond":
                self._device_respond()
            elif u.path == "/device/resume":
                self._device_resume()
            elif u.path == "/device/park-state":
                self._device_park_state()
            elif u.path == "/device/disconnect":
                self._device_disconnect()
            elif u.path == "/device/sync/batch":
                self._sync_batch()
            elif u.path == "/device/sync/complete":
                self._sync_complete()
            elif u.path == "/device/sync/manifest":
                self._sync_manifest()
            elif u.path == "/device/sync/state":
                self._sync_state()
            elif u.path == "/device/sync/delete":
                self._sync_delete()
            elif u.path == "/mcp":
                self._mcp()
            else:
                self._send(404, {"error": "not_found"})
        except (ValueError, json.JSONDecodeError) as e:
            self._send(400, {"error": f"bad_request: {e}"})


# ------------------------------------------------------- gateway transport
# Batch 5 transport adapter: api_server's aiohttp face collects
# (method, path, headers, body) and calls dispatch_sync on a worker
# thread; the bridge Handler above runs verbatim against the
# in-memory shim, and the single _send() every route ends in lands
# in the capture buffer. The standalone HTTP server is gone -- the
# gateway process is the only host now.

class _GatewayHandler(Handler):
    """The bridge Handler running against an in-memory request."""

    def __init__(self, method: str, path: str, headers: dict,
                 body: bytes):
        self.command = method
        self.path = path
        self.headers = headers
        self.rfile = io.BytesIO(body)
        self.wfile = io.BytesIO()
        self._status = 200

    def send_response(self, code, message=None):
        self._status = code

    def send_header(self, key, value):
        pass

    def end_headers(self):
        pass

    def log_message(self, fmt, *args):
        pass


def dispatch_sync(method: str, path: str, headers: dict,
                  body: bytes):
    """Run one request through the bridge engine. Returns
    (status, raw_body). Blocking by design (poll waits, call
    timeouts) -- callers run it on a worker thread."""
    handler = _GatewayHandler(method, path, headers, body)
    if method == "GET":
        handler.do_GET()
    elif method == "POST":
        handler.do_POST()
    else:
        return 405, b'{"error": "method_not_allowed"}'
    return handler._status, handler.wfile.getvalue()


def start() -> None:
    """Gateway start hook (the bridge main()'s setup half): the
    data-dir discipline, plus a loud line when the single key is
    missing (authed routes then fail closed, as on the bridge)."""
    if not API_KEY:
        print("[device-gateway] API_SERVER_KEY unset; all authed "
              "routes will fail closed", flush=True)
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    device_sync.init(DATA_DIR)
    _audit_path.touch(exist_ok=True)
    os.chmod(_audit_path, 0o600)  # device data dir discipline: 0600
    print(f"[device-gateway] ready, data dir {DATA_DIR}", flush=True)


start()
