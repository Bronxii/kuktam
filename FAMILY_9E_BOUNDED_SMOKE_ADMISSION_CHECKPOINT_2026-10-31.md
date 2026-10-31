# Family 9E • Bounded production smoke admission • 2026-10-31

**PASS.** The rollout runbook's two-account T6 blocker is closed in source. Production remains OFF. No production access, deployment, real account deletion, commit or push.

## Admission contract

Previously familyAdmissionEnabled(config, field) accepted only a literal true flag. FamilyCreateStore.reserve, FamilyInviteStore.create and FamilyJoinStore.reserve each read familyRuntime/config in their existing Firestore transaction. The CREATE and JOIN checks follow resolution of an existing logical operation. The new helper also receives uid from authenticatedUid(context) in those same three stores. No callable payload, Flutter, rules, index, shopping, billing or App Check change. The existing rules deny client access to familyRuntime and the state API does not serialize these fields. No new logs or metrics containing identities.

Exact desired Firestore fields for T6, placeholders only:
~~~json
{
  "creationEnabled": false,
  "inviteCreationEnabled": false,
  "joinReservationEnabled": false,
  "smokeAdmissionEnabled": true,
  "smokeAllowedUids": {
    "owner": "<actual UID of approved Pro account A>",
    "member": "<actual UID of approved account B>"
  }
}
~~~

Precedence is per NEW operation. Literal global true admits normally regardless of smoke configuration. Only an explicitly false operation flag can fall back to scoped admission. A missing flag, wrong type, missing document, failed read, disabled smoke mode or malformed cohort grants no scoped permission. All three flags must be false operationally for a bounded T6. The map must contain exactly two role slots, valid distinct UIDs, 1–128 characters without slash or surrounding whitespace. One owner for CREATE/invite; one joining member for NEW JOIN. No extra role, third UID, list, wildcard or email-based lookup. Private account state, role, Pro where required, capacity, membership binding, invite and lifecycle validations still apply.

Outsider C can get the usual VALID preview for A's valid token if otherwise eligible. NEW JOIN receives existing FEATURE_DISABLED; the invite remains PENDING and B can use it. CREATE/invite retain existing disabled errors. No cohort detail is returned. This policy controls only the authenticated starter; existing invite validation and single-use consumption still govern the credential.

## Later operator procedure (requires separate GO)
1. Before GO-6 verify deployed 9E revisions of createFamilyShare, createFamilyInvite and acceptFamilyInvite, T5 proofs, existing accounts and actual Firebase Auth identities through an authorized channel. Confirm A's eligibility and B's private state. Verify all three growth flags false, smoke disabled, approved config writer and rollback owner available.
2. Under scoped GO-6, atomically update the specified top-level fields on familyRuntime/config, replacing the entire smokeAllowedUids map and preserving unrelated fields. Do not log UID lists or tokens. Read back the exact shape privately. Stop on mismatch. No approved CLI writer is assumed.
3. Run the scoped runbook; verify outsider denial with separately authorized test identity where permitted. Closing the cohort means an atomic update retaining all three flags false, setting smokeAdmissionEnabled=false and removing the smokeAllowedUids field. Verify readback. No audit or Family data deletion.
4. Emergency OFF uses the same four false switches, including smokeAdmissionEnabled. An already-admitted JOIN retry, DELETE consent, committed transfer, exits, dissolution, Pro-loss and deletion handoff use their existing authority. Keep workers running. Later GO-7 alone may enable general gates; keep smoke disabled and remove the UID map.

## Local validation
Functions build passed. Production-like Cloud Functions environment with pinned demo Firestore emulator and simulated Auth deletion. family-runtime-policy.test.js: **12/12 passed, zero failures/skips** (9 affected 9C cases, 3 new 9E cases). New tests cover role/field precedence, invalid maps and flags, both actual JOIN modes with A/B/C, unconsumed outsider invite, same operation after shutdown, member leave and owner dissolution. Existing cases include unreadable/absent config, normal users without cohort, Pro-loss, member/owner deletion and maintained forward completion. DELETE includes explicit source snapshot consent after scoped admission closes.

Handoff: human review, then GO-2 for the index prerequisite only. GO-1 needs READY index, verified IAM/secret access, baseline/drift and exact deploy groups. GO-6 needs final rules, compatible signed client, healthy backend and bounded config procedure. GO-7 needs completed smoke/cleanup, verified Play-signed link, monitoring and separate activation GO. No execution authorization follows from this checkpoint.
