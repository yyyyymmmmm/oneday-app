"""53-tool catalog and permission/replay declarations extracted from device_gateway.py (#44).

Preserves the exact tool names, descriptions, inputSchemas, WRITE_TOOLS,
NEVER_REPLAY_TOOLS, and NO_PERMISSION_SOURCES sets verbatim.
"""

from __future__ import annotations

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

