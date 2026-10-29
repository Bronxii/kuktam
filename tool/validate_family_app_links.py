"""Local-only 8B configuration checks; never deploys or accesses the network."""
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
manifest = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "android/app/src/main/AndroidManifest.xml"
a = "{http://schemas.android.com/apk/res/android}"
xml = ET.parse(manifest).getroot()
filters = [f for f in xml.findall(".//intent-filter") if f.get(a + "autoVerify") == "true"]
assert len(filters) == 1
f = filters[0]
assert {x.get(a + "name") for x in f.findall("action")} == {"android.intent.action.VIEW"}
assert {x.get(a + "name") for x in f.findall("category")} == {"android.intent.category.DEFAULT", "android.intent.category.BROWSABLE"}
assert [x.attrib for x in f.findall("data")] == [{a + "scheme": "https", a + "host": "kuktam-67768.web.app", a + "path": "/family/invite"}]
assert any(x.get(a + "name") == "flutter_deeplinking_enabled" and x.get(a + "value") == "false" for x in xml.findall(".//meta-data"))
package = "com.bronxii.kuktam"
if len(sys.argv) > 1:
    assert xml.get("package") == package
assert 'applicationId = "' + package + '"' in (root / "android/app/build.gradle.kts").read_text(encoding="utf-8")
asset = json.loads((root / "hosting/.well-known/assetlinks.json").read_text())
fingerprint = "AF:21:94:5C:B6:95:4A:D8:F1:8A:00:D4:85:78:FF:B0:AD:60:58:77:A5:9E:3A:D0:96:6E:91:6D:23:A2:E5:CD"
assert re.fullmatch(r"(?:[0-9A-F]{2}:){31}[0-9A-F]{2}", fingerprint)
assert asset == [{"relation": ["delegate_permission/common.handle_all_urls"], "target": {"namespace": "android_app", "package_name": package, "sha256_cert_fingerprints": [fingerprint]}}]
c = json.loads((root / "firebase.json").read_text())
assert c["hosting"]["site"] == "kuktam-67768" and c["hosting"]["public"] == "hosting"
assert not (root / ".firebaserc").exists()
assert not list((root / "hosting").rglob("apple-app-site-association"))
print("PASS: canonical intent filter, package, disabled default delivery, DAL JSON, exact 32-byte Play certificate, Hosting site; no deployment.")
