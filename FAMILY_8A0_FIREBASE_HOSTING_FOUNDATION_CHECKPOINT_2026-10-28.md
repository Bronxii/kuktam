# Family 8A0 — Firebase Hosting foundation

Date: 2026-10-28. Result: PASS.

## Authorized production configuration evidence

Initial Hosting LIST returned exactly one site:

- name: `projects/kuktam-67768/sites/kuktam-67768`
- defaultUrl: `https://kuktam-67768.web.app`
- type: `DEFAULT_SITE`

The subsequent GET for site `kuktam-67768`, explicitly scoped to project `kuktam-67768`, independently returned the same three metadata fields. The HTTPS origin and project association are from authenticated Firebase metadata, not DNS guessing or reconstruction from project name.

The site already existed. No site was created, replaced, deleted or disabled. No alternate site ID was attempted. No collision occurred. Firebase did not return a firebaseapp.com domain in either response; none is claimed as separately verified. No public website request or content inspection was needed; deployed-content status is outside this configuration-only check.

## Exact Firebase commands executed

Executed from `C:/Users/gabor/kuktam` using the project-local CLI:

```powershell
node .\functions\node_modules\firebase-tools\lib\bin\firebase.js hosting:sites:list --project kuktam-67768 --json
node .\functions\node_modules\firebase-tools\lib\bin\firebase.js hosting:sites:get kuktam-67768 --project kuktam-67768 --json
```

Both exited 0 with status success. No credentials or tokens are included here. No CREATE, init, deploy, channel deploy, custom-domain or other remote mutation command ran.

## Local configuration

`firebase.json` adds only:

```json
"hosting": {
  "site": "kuktam-67768",
  "public": "hosting",
  "ignore": ["firebase.json", "**/.*", "**/node_modules/**"]
}
```

The project-local Firebase CLI schema supports the explicit `site` and `public` properties. Existing flutter, functions and firestore configuration values were compared before/after and are identical. Both emulator configuration files and firestore.rules have unchanged SHA256 content checksums across the edit. JSON parses successfully. `.firebaserc` did not exist before and was not created.

`hosting/.gitkeep` is the sole local Hosting source file, an empty directory-preservation placeholder excluded by the dotfile ignore pattern. No web page, routing, redirect, assetlinks.json, Apple association file or generated Flutter build output was added. This is a source-directory reservation, not a deployed or functioning invite landing page.

## Boundaries and handoff

Verified origin for subsequent separately authorized 8A work: **https://kuktam-67768.web.app**.

No canonical invite path/query format is chosen here. Invite response fields, token/JOIN behavior, Flutter UI, authentication, Family production gates and rules remain unchanged. No Hosting content, Functions, rules or data were deployed or mutated. Production activity consisted exclusively of Hosting LIST and GET. No production account/data tests, git baseline/status/log checks, commit or push ran. Flutter tests and Functions build were unnecessary because application source was unchanged.

Authored local files:
- firebase.json
- hosting/.gitkeep
- FAMILY_8A0_FIREBASE_HOSTING_FOUNDATION_CHECKPOINT_2026-10-28.md

Final gates: Family core COMPLETE (input); 8A0 PASS; 8A host prerequisite resolved, implementation NOT STARTED. 8B, 8C, final Family QA and production Family rollout NOT STARTED. Blockers: NONE. STOP; do not start 8A automatically.
