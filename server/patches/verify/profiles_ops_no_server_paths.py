"""dp-243: verify profiles/ops success responses don't expose server paths."""
import sys
import re
sys.path.insert(0, "..")

# Verify that success responses no longer contain server-side paths
# Check web_routers_profiles.py for removed path/archive fields
profiles_path = "../web_routers_profiles.py"
with open(profiles_path, "r", encoding="utf-8") as f:
    profiles_content = f.read()

# 1. _profile_to_dict should not have "path" field
profile_dict_match = re.search(r'def _profile_to_dict\(info\).*?return \{(.*?)\}', profiles_content, re.DOTALL)
assert profile_dict_match, "_profile_to_dict function not found"
profile_dict_body = profile_dict_match.group(1)
assert '"path":' not in profile_dict_body and "'path':" not in profile_dict_body, \
    "_profile_to_dict still contains 'path' field"

# 2. Create profile response should not have "path"
create_response = re.search(r'hub_installs: list.*?return \{(.*?)\}', profiles_content, re.DOTALL)
assert create_response, "Create profile response not found"
create_body = create_response.group(1)
assert '"path":' not in create_body, "Create profile response still contains 'path'"

# 3. Rename profile response should not have "path"
rename_matches = re.findall(r'is_default:.*?return \{.*?"ok": True.*?\}', profiles_content, re.DOTALL)
assert len(rename_matches) >= 1, "Rename profile responses not found"
for match in rename_matches:
    assert '"path":' not in match, "Rename profile response still contains 'path'"

# 4. Delete profile responses should not have "path" or "retry_command"
delete_section = re.search(r'except ProfileIdentitySettlementPending.*?return \{"ok": True\}', profiles_content, re.DOTALL)
assert delete_section, "Delete profile responses not found"
delete_body = delete_section.group(0)
assert '"path":' not in delete_body, "Delete profile response still contains 'path'"
assert '"retry_command":' not in delete_body, "Delete profile settlement response still contains 'retry_command'"

# 5. Export profile response should not have "archive"
export_response = re.search(r'profiles_mod\.export_profile.*?return \{(.*?)\}', profiles_content, re.DOTALL)
assert export_response, "Export profile response not found"
export_body = export_response.group(1)
assert '"archive":' not in export_body, "Export profile response still contains 'archive'"

# 6. Import profile response should not have "path"
import_response = re.search(r'return \{"ok": True, "name": imported,.*?\}', profiles_content)
assert import_response, "Import profile response not found"
import_body = import_response.group(0)
assert '"path":' not in import_body, "Import profile response still contains 'path'"

# Check web_routers_ops.py for removed archive fields
ops_path = "../web_routers_ops.py"
with open(ops_path, "r", encoding="utf-8") as f:
    ops_content = f.read()

# 7. Backup response should not add "archive" field
backup_section = re.search(r'_spawn_action\(\["backup".*?return response', ops_content, re.DOTALL)
assert backup_section, "Backup response section not found"
backup_body = backup_section.group(0)
# Should not have conditional archive assignment
assert 'response["archive"]' not in backup_body, "Backup response still adds 'archive' field"

# 8. Import upload response should not have "archive"
import_upload = re.search(r'return \{.*?_spawn_import.*?uploaded_bytes.*?\}', ops_content, re.DOTALL)
assert import_upload, "Import upload response not found"
import_upload_body = import_upload.group(0)
assert '"archive":' not in import_upload_body and "'archive':" not in import_upload_body, \
    "Import upload response still contains 'archive'"

print("✓ dp-243: profiles/ops success responses don't expose server paths")
