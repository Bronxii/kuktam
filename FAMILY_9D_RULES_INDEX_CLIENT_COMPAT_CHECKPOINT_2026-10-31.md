# Family 9D • Rules, indexes and old clients • 2026-10-31

**FAIL — old-client cutoff implementation/operational control missing.** Local S1C passes. Family remains OFF. An old installation can lose its ability to save shopping edits for an already migrated account even with every Family admission switch OFF. There is no evidenced enforced upgrade path. A rollout percentage cannot protect a second device or a returning offline installation.

## Production evidence

Read-only Firebase Rules API release lookup for exactly projects/kuktam-67768/releases/cloud.firestore returned ruleset 1c10f3f0-d2ea-4524-8c5f-b02e5d72f291, release update 2026-10-17T05:05:52.459814Z. Read its firestore.rules source. Project-local CLI firestore:indexes --project kuktam-67768 --json returned {"indexes":[],"fieldOverrides":[]} on (default). No custom index READY, building or errored in that inventory. Automatic indexes still apply. No document reads were needed for this reconciliation.

## Local rules and complete behavioral delta

All permissions below concern client SDKs. “None” denies everyone, including Family owners. Admin workers use IAM.

| Document | Read | Create | Update | Delete | Server only |
|---|---|---|---|---|---|
| users/{uid} | own GET only | none | none | own if activeHouseholdId absent or lifecycle exists and state differs from ACTIVE | no |
| users/{uid}/shopping/{item} | own | own editable account before activeHouseholdId field exists | same | own, even during/after migration | no |
| users/{uid}/shoppingMutations/{id} | own | own validated request | none | none | no |
| households/{hid} and members/{member} beneath it | authenticated caller has member doc in this hid | none | none | none | no |
| households/{hid}/shoppingItems/{item} | ACTIVE account, member doc, migrationVersion 1, current authoritative private/Family context | none | none | none | no |
| familyMemberships, familyInvites, familyJoinCapacity, familyInviteSlots, familyOperations and descendants, familyRuntime, shoppingRuntime, shoppingMutationWork | none | none | none | none | yes |
| Family create/generation, dissolution, receipts, audit and maintenance records outside explicit matches, familyProLoss, familyMemberDeletions, familyOwnerDeletions, familyLifecycleMaintenance, accountLifecycle, accountDeletions and billingMaintenance | none | none | none | none | yes |

Editable = absent lifecycle marker or ACTIVE. Private context requires owned active private route (also supported legacy v1 private root), owner member and no active Family binding. A reserved JOIN allows only the proven READY private-source phases RESERVED / READY_FOR_TRANSFER. Family reads require ACTIVE v2 Family, operationId null, matching active binding and role, and valid distinct owned active fallback. A stale member document alone permits household metadata reads but cannot authorize list reads. Mutation CREATE additionally requires shoppingRuntime enabled, exact envelope fields, actor/path/id match, valid unexpired current epoch, allowed command kind, bounded payload and server timestamp. Processor validates business payload/receipts.

* A/D — live permits editing only activeHouseholdId to an existing membership for an editable migrated user. Local removes this client pointer update.
* A/B/D — live household list reads require only member existence. Live list C/U/D require membership, ACTIVE account and migrationVersion 1. Local narrows reads to current context and denies every direct C/U/D.
* B — live catch-all denies shoppingMutation requests and receipt reads. Local grants only the owner permissions above. This makes an early mutation-only client incompatible with existing live rules.
* A/B — explicit denials on Family stores, shopping work and runtime are equivalent to live catch-all. The authenticated household/member metadata read, legacy shopping, own recipes, billing, recipes deletion, entitlement and ingredient rules have no other behavioral delta. No unrelated pending permission change identified.

## Client compatibility

Historical shopping repository at c4225d2^ writes users/{uid}/shopping. At 8b6255c^ it writes households/{hid}/shoppingItems directly. Commit 8b6255c introduces production mutation cutover. Current ShoppingRepository submits ADD/EDIT/SET_CHECKED/DELETE and BULK through ShoppingCoordinator and shopping_mutation_transport; recipe scaling, recipe details and text import use addOrMergeItems. Same transport uses authoritative active context for private and shared shopping. ensureShoppingContext supplies epoch. No direct current structural list write found.

HouseholdGate after usable authentication initiates household resolution. The authoritative ensurePrivateHousehold path calls HouseholdStore.ensure, up to ten transactions of at most 50 legacy docs each. It sets the active pointer from the first page, copies each row and deletes its source atomically, and marks migration version 1 on an empty page. Cached routing does not undo the server barrier. No automatic reverse migration.

| Installed client | Before migration | After migration / after JOIN under local S1C |
|---|---|---|
| Legacy user shopping | Own create/update/read/delete subject to lifecycle above | Own legacy reads can return empty after the move, create/update denied. Own deletes remain permitted on remaining legacy docs, including not-yet-copied rows in a multipage migration. Cannot read/write shared items via that path. |
| Household direct writer | Can initiate household setup | Authorized current list may be read. Direct writes always denied. Hidden private shopping cannot be used as a fallback. Previously queued local writes can roll back on server rejection. Live rules still permit direct writes and client route selection, so Family cannot be enabled under them. |
| Current mutation writer | Needs household provisioning and compatible rules/worker | Submits immutable commands using current context, server owns canonical writes. |

No proof of silent corruption of migrated canonical rows by local S1C. Denied/unsaved edits, misleading empty lists and the live legacy-delete exception during migration are material. No proof that any given released build reliably surfaces all rejected writes. No Play Console release/track-to-source provenance available here. Local version 1.0.0+1 is also present before cutover. Minimum released compatible build UNKNOWN. No trusted per-install app build admission in Family callables, routing or rules. Display/export version strings, UID and App Check app identity cannot establish this. Obtain signed Play artifact/versionCode/track and map it to tested shopping and Family contracts. Require a proven mechanism to retire/block incompatible installations across devices before cutoff or a separately designed compatible transition. Merely waiting for adoption or refusing new JOIN cannot protect private shopping.

## Query/index matrix

Collection scope unless explicitly marked group. Exact caller/source clauses and limits follow in appendix. Direct document reads of invite tokens/slots, capacity, operation IDs, bindings and cursors use document keys.
* **Missing** familyInvites equality householdId, status plus range expiresAt > now, implicit expiresAt ASC, limit 1 or 9. Used by historical audit, owner deletion and dissolution finalization. Local manifest contains this one collection-scope composite, all three fields ASC, fieldOverrides empty.
* **No added composite** for householdId/status RESERVED equality, shoppingItems name/unit equality, owner/kind/state equality, and other equality intersections with default key ordering. Current indexes support merging simple equalities. IN is equality disjunction; actor/owner/household + status IN and owner/kind + state IN rely on equality branches and default key ordering. Validate shapes on a production-equivalent disposable database before release if planner evidence is required. No production document queries were run.
* **9C historical audit sweep** familyOwnerDeletions phase IN WAITING_HISTORICAL_AUDIT / DETACHING_HISTORICAL_AUDIT / HISTORICAL_AUDIT_READY, order __name__ ASC, limit 20, startAfter saved ID. Single-field phase index includes the document key as its final sort component. No separate composite for this query.
* **No added composite** for reads ordered only by document key, revision DESC, single nextAt range/order, single equality, unfiltered count, count by auditOwnerUid or unrestricted subcollection pages. Rotating membership scan 20 precedes Pro-loss due work (20). Member/owner deletion due scans each limit 20. Shopping and shared Family due scans each limit 5. Audit invite/operation traversal filters householdId, then traverses by document ID in pages of 10. Single-field indexes have implicit key ordering. Two dispatcher collection-group scans use only document name, no application field.
* Before this phase no manifest or firebase.json index mapping existed. Local manifest now describes the known missing index. Re-list immediately before any later operation to preserve drift. Installed CLI firestore/api.js computes remote-only deletions, prompts default false interactively and can delete under --force. Index deploy is reconciliation, not inherently additive. Only after separate GO: node .\functions\node_modules\firebase-tools\lib\bin\firebase.js deploy --only firestore:indexes --non-interactive --project kuktam-67768 (never --force). Wait for READY. Official index model: https://firebase.google.com/docs/firestore/query-data/index-overview

## Rules proof

Two affected emulator files: shopping-rules and household-rules, 59/59 passed. Strengthened real-client proof seeds legacy via authenticated SDK, migrates with HouseholdStore, rejects stale legacy create, rejects direct household edit and accepts SET_CHECKED through actual Admin processor. Additional DISSOLVED fixture retaining otherwise credible routing/member evidence: 1/1 passed. Existing tests cover stale epoch, wrong home/UID, membership, active routing, hidden fallback, immutable commands and attempted structural forgeries. Local manifest checked by parsing firebase.json and asserting collection scope, field order/direction and empty overrides. No Functions source/build or Flutter change.

## Five-minute maintenance

Local composition injects default 50-doc page and 60-second run budget. Dispatcher reads/leases billingRuntime/maintenance, rotates category start, reads again on checkpoint and saves per-category cursors. Within budget all categories may execute in one invocation. Busy lease can skip them. Numeric estimates below concern initial returned documents, excluding index-entry charges, visitor reads, transactions/retries, work receipts and external services.

| Category | Periodic query or read | Maximum returned per visit |
|---|---|---|
| expiredInbox / retryInbox / unresolvedInbox / tokens | Four independently cursor-paged rtdnInbox scans ordered by document ID. Status/lease/due or minimization evaluated after reading. | 4 × 50 |
| active / deletion | billingPurchases / accountDeletions, document ID, classify terminal and due after reading | 2 × 50 |
| ack / grants | acknowledgment / entitlementGrants collection groups, document ID, per-category cursor | 2 × 50 |
| family / shopping | familyOperations / shoppingMutationWork nextAt <= now ASC | 2 × 5 |
| voided | Firestore work record claim, bounded Play feed only when due | separate point/worker reads |

At 288 invocations/day, four full inbox pages alone can return 57,600 docs/day. Eight full broad pages plus both due pages can return 118,080/day before visitor costs. Empty queries have a minimum charge, but empty pages alone are far below the observed volume. Even with nothing actionable, historical records can fill pages, and token minimization/claims can read records again. Cursors wrap after a short page; 60-second budget may reduce actual visits. The reported 40k–70k corresponds to roughly 139–243 reads/run. Repeated inbox scanning is a strong candidate, **production attribution not proven**. No production content or deployed binary source was sampled. First correlate branch/page counts and revision with existing monitoring; then consider a bounded common inbox traversal or indexed due queues only with equivalent recovery, minimization, fairness and backfill evidence. No scheduling, billing code or retention change.

## Deployment order and decision

1. Obtain released artifact provenance and workable cross-install cutoff. Verify deployed versions, runtime identities, supported shared shopping gate/worker and recovery. Keep Family growth OFF.
2. Stage reviewed indexes first, verify READY before scheduling dependent workers. Backend-before-rules is NOT SAFE as a blanket rollout. Admin bypasses rules, so a separately reviewed dormant or backward-compatible worker subset can precede cutover. Provisioning can migrate, and scheduled workers begin independently of Family admission.
3. Coordinate release and rules so the processor is available before commands are accepted and old clients cannot still write when cutoff happens. Current live rules deny command creation; simply shipping a mutation-only build ahead of compatible rules is also unsafe. No proven bridge exists for a mixed fleet in this review. Resolve this as separate implementation/release work; preserve S1C.
4. Before smoke require compatible installed artifacts, tested rules and ready indexes, deployed and healthy mutation/lifecycle/recovery, separate scoped smoke authorization and controls. Before Family ON additionally require Play-signed App Links proof, completed smoke, staged monitoring/rollback and explicit GO. Family gates cannot supply a minimum-version policy.
5. 9A/9B0/9C PASS, 9B delta conditional, 9D FAIL. Production rollout OFF. No deploy, production data mutation, scheduler/config change, commit or push.

## Source query ledger

The following source expressions pin dynamic limits, cursor implementation and callers to this checkpoint. Each key-only page and single-field query uses built-in indexes. The missing composite and dispatcher group queries are identified above.

~~~typescript
functions/src/jobs/maintenance.ts:64:          const page=await this.db.collection('shoppingMutationWork').where('nextAt','<=',input.now).orderBy('nextAt').limit(Math.min(5,this.policy.pageSize)).get();
functions/src/jobs/maintenance.ts:82:          const page=await this.db.collection('familyOperations').where('nextAt','<=',input.now).orderBy('nextAt').limit(Math.min(5,this.policy.pageSize)).get();
functions/src/jobs/maintenance.ts:95:      const base: Query = category === 'deletion' ? this.db.collection('accountDeletions') : category === 'active' ? this.db.collection('billingPurchases') : category === 'ack' ? this.db.collectionGroup('acknowledgment') :
functions/src/jobs/maintenance.ts:96:        category === 'grants' ? this.db.collectionGroup('entitlementGrants') : this.db.collection('rtdnInbox');
functions/src/jobs/maintenance.ts:97:      let query = base.orderBy(FieldPath.documentId()).limit(this.policy.pageSize);
functions/src/billing/lifecycle-store.ts:247:      const docs = await tx.get(this.db.collection(`users/${uid}/entitlementGrants`).limit(501));
functions/src/billing/lifecycle-store.ts:422:      const recipes=await tx.get(this.db.collection(`users/${uid}/recipes`).limit(1));
functions/src/billing/lifecycle-store.ts:423:      const shopping=await tx.get(this.db.collection(`users/${uid}/shopping`).limit(1));
functions/src/billing/lifecycle-store.ts:424:      const mutations=await tx.get(this.db.collection(`users/${uid}/shoppingMutations`).limit(1));
functions/src/billing/lifecycle-store.ts:425:      const mutationWork=await tx.get(this.db.collection('shoppingMutationWork').where('uid','==',uid).limit(1));
functions/src/billing/lifecycle-store.ts:426:      const homes=await tx.get(this.db.collection('households').where('ownerUid','==',uid).limit(1));
functions/src/billing/lifecycle-store.ts:454:        content.push(...(await tx.get(rootRef.collection(name).limit(limit-content.length))).docs);
functions/src/billing/lifecycle-store.ts:456:      if(content.length<limit)content.push(...(await tx.get(this.db.collection('shoppingMutationWork').where('uid','==',uid).limit(limit-content.length))).docs);
functions/src/billing/lifecycle-store.ts:465:        const page=await tx.get(this.db.collection('billingAccountBindings').where('uid','==',uid).where('state','==','ACTIVE').limit(limit));
functions/src/billing/lifecycle-store.ts:471:        const page=await tx.get(this.db.collection(`users/${uid}/entitlementGrants`).limit(limit));
functions/src/billing/lifecycle-store.ts:477:        const page=await tx.get(this.db.collection('billingPurchases').where('boundUid','==',uid).limit(1));
functions/src/billing/lifecycle-store.ts:481:        const inbox=await tx.get(this.db.collection('rtdnInbox').where('tokenHash','==',doc.id).limit(limit));
functions/src/billing/lifecycle-store.ts:498:        const page=await tx.get(this.db.collection('billingAccountBindings').where('uid','==',uid).limit(limit));
functions/src/billing/lifecycle-store.ts:505:      const remainingGrants=await tx.get(this.db.collection(`users/${uid}/entitlementGrants`).limit(1));
functions/src/billing/lifecycle-store.ts:507:      const entitlements=await tx.get(this.db.collection(`users/${uid}/entitlements`).limit(limit));
functions/src/shopping\mutation-store.ts:58:      const max=await tx.get(home.ref.collection('shoppingItems').orderBy('revision','desc').limit(1));
functions/src/shopping\mutation-store.ts:150:      const matches=await tx.get(items.where('name','==',c.name).where('unit','==',c.unit).limit(3));
functions/src/shopping\mutation-store.ts:202:    const matches=c.type==='ADD'||c.type==='EDIT'?await tx.get(items.where('name','==',c.name).where('unit','==',c.unit).limit(3)):null;
functions/src/households\dissolution-member-release.ts:40:    const participants=o.participants.filter(p=>p.role==='member'),stored=await tx.get(state),records=await tx.get(journal.limit(8));
functions/src/households\dissolution-member-release.ts:57:    if(merge.stage!=='COMPLETE'||merge.count!==snapshot.count||merge.pageIndex!==snapshot.pages||merge.sourceHash!==snapshot.hash||merge.receiptHash!==merge.finalReceiptHash||snapshot.count&&revision(homes.target.get('shoppingRevision'))!==merge.sequence||clean.stage!=='COMPLETE'||clean.pageIndex!==snapshot.pages||clean.count!==snapshot.count||clean.sourceHash!==snapshot.hash||clean.mergeHash!==merge.receiptHash||clean.cleanupHash!==clean.finalCleanupHash||(await tx.get(homes.source.ref.collection('shoppingItems').limit(1))).size)invalid();
functions/src/households\dissolution-finalization.ts:50:    const live=await tx.get(this.db.collection('familyInvites').where('householdId','==',householdId).where('status','==','PENDING').where('expiresAt','>',now).limit(9));
functions/src/households\dissolution-finalization.ts:51:    const reserved=await tx.get(this.db.collection('familyInvites').where('householdId','==',householdId).where('status','==','RESERVED').limit(9));
functions/src/households\dissolution-preparation.ts:87:      const reverses=await tx.get(this.db.collection('familyMemberships').where('householdId','==',householdId).limit(9));
functions/src/households\dissolution-merge.ts:47:     if(o.phase!=='PRESERVATION_COMMITTED'||(await tx.get(journals.limit(1))).size)fail();
functions/src/households\dissolution-merge.ts:48:     const max=await tx.get(homes.target.ref.collection('shoppingItems').orderBy('revision','desc').limit(1));
functions/src/households\dissolution-merge.ts:62:     if(p.offset!==0||p.count!==snapshot.count||p.sourceHash!==snapshot.hash||(await tx.get(journals.count())).data().count!==snapshot.pages||(await tx.get(ref.collection('shoppingPreservation').count())).data().count!==snapshot.pages)fail();
functions/src/households\dissolution-merge.ts:66:     if(p.receiptHash!==p.finalReceiptHash||(await tx.get(homes.source.ref.collection('shoppingItems').count())).data().count!==snapshot.count)fail();
functions/src/households\family-create.ts:47:  const members=await tx.get(home!.ref.collection('members').limit(1));
functions/src/households\family-create.ts:48:  const reverse=await tx.get(db.collection('familyMemberships').where('householdId','==',o.householdId).limit(1));
functions/src/households\family-create.ts:71:  const grants = await tx.get(db.collection(`users/${uid}/entitlementGrants`).limit(501));
functions/src/households\family-create.ts:118:      const owned=await tx.get(this.db.collection('households').where('ownerUid','==',uid).where('kind','==','family').where('state','in',['ACTIVE','PREPARING','DISSOLVING']).limit(1));
functions/src/households\family-create.ts:131:      const orphanItems=await tx.get(destinationRef.collection('shoppingItems').limit(1));
functions/src/households\family-create.ts:195:        let query=sourceRef.collection('shoppingItems').orderBy(FieldPath.documentId()).limit(this.pageSize);
functions/src/households\family-create.ts:222:        const page=await tx.get(sourceRef.collection('shoppingItems').limit(this.pageSize));
functions/src/households\family-create.ts:232:      const page=await tx.get(homeRef.collection('shoppingItems').limit(this.pageSize));
functions/src/households\family-create.ts:233:      const members=await tx.get(homeRef.collection('members').limit(this.pageSize));
functions/src/households\dissolution-source-disposition.ts:50:     if(o.phase!=='PRESERVATION_MERGE_COMPLETE'||(await tx.get(cleanup.limit(1))).size)invalid();
functions/src/households\dissolution-source-disposition.ts:52:      if(snapshot.hash!==start.sourceHash||m.receiptHash!==start.mergeHash||(await tx.get(ref.collection('shoppingPreservation').limit(1))).size||(await tx.get(ref.collection('preservationMergeJournal').limit(1))).size||(await tx.get(homes.source.ref.collection('shoppingItems').limit(1))).size)invalid();
functions/src/households\dissolution-source-disposition.ts:60:     if(p.stage!=='COMPLETE'||n!==snapshot.pages||p.count!==snapshot.count||p.sourceHash!==snapshot.hash||p.mergeHash!==m.receiptHash||p.cleanupHash!==p.finalCleanupHash||(await tx.get(homes.source.ref.collection('shoppingItems').limit(1))).size)invalid();return o.phase;
functions/src/households\dissolution-source-disposition.ts:64:     if(p.sourceHash!==snapshot.hash||p.mergeHash!==m.receiptHash||(await tx.get(ref.collection('shoppingPreservation').count())).data().count!==snapshot.pages||(await tx.get(ref.collection('preservationMergeJournal').count())).data().count!==snapshot.pages)invalid();
functions/src/households\dissolution-source-disposition.ts:66:      if((await tx.get(cleanup.limit(1))).size||(await tx.get(homes.source.ref.collection('shoppingItems').count())).data().count!==snapshot.count)invalid();
functions/src/households\dissolution-source-disposition.ts:69:     if((await tx.get(cleanup.count())).data().count!==snapshot.pages)invalid();
functions/src/households\dissolution-source-disposition.ts:71:     if(p.cleanupHash!==p.finalCleanupHash||(await tx.get(homes.source.ref.collection('shoppingItems').limit(1))).size)invalid();
functions/src/households\dissolution-preservation.ts:74:  const members=await tx.get(source.ref.collection('members').limit(9)),indexes=await tx.get(this.db.collection('familyMemberships').where('householdId','==',o.householdId).limit(9));
functions/src/households\dissolution-preservation.ts:116:     if((await tx.get(ref.collection('shoppingPreservation').limit(1))).size)invalid();
functions/src/households\dissolution-preservation.ts:127:    let q=c.source.ref.collection('shoppingItems').orderBy(FieldPath.documentId()).limit(10);if(cursor.lastId!==null)q=q.startAfter(cursor.lastId);
functions/src/households\dissolution-preservation.ts:139:     if(!docs.empty||page.exists||cursor.count!==snapshot.count||cursor.hash!==snapshot.hash||(await tx.get(pages.count())).data().count!==snapshot.pages)invalid();
functions/src/households\family-join.ts:127:      const count=await tx.get(this.db.collection(`households/${p}/shoppingItems`).count());
functions/src/households\historical-family-audit.ts:41:  const ownedWork=await tx.get(this.db.collection('familyOperations').where('ownerUid','==',uid).where('status','in',['READY','OPERATOR']).limit(1));
functions/src/households\historical-family-audit.ts:42:  const actorWork=await tx.get(this.db.collection('familyOperations').where('actorUid','==',uid).where('status','in',['READY','OPERATOR']).limit(1));
functions/src/households\historical-family-audit.ts:43:  const live=await tx.get(this.db.collection('households').where('ownerUid','==',uid).where('kind','==','family').where('state','in',['ACTIVE','PREPARING','DISSOLVING']).limit(1));
functions/src/households\historical-family-audit.ts:53:   const a=await this.privateAccount(tx,uid),homes=await tx.get(this.db.collection('households').where('ownerUid','==',uid).where('kind','==','family').orderBy(FieldPath.documentId()).limit(1));
functions/src/households\historical-family-audit.ts:67:  const members=await tx.get(home.ref.collection('members').limit(1)),indexes=await tx.get(this.db.collection('familyMemberships').where('householdId','==',home.id).limit(1)),items=await tx.get(home.ref.collection('shoppingItems').limit(1));
functions/src/households\historical-family-audit.ts:68:  const reservations=await tx.get(this.db.collection('familyInvites').where('householdId','==',home.id).where('status','==','RESERVED').limit(1));
functions/src/households\historical-family-audit.ts:69:  const usable=await tx.get(this.db.collection('familyInvites').where('householdId','==',home.id).where('status','==','PENDING').where('expiresAt','>',this.clock()).limit(1));
functions/src/households\historical-family-audit.ts:70:  const work=await tx.get(this.db.collection('familyOperations').where('householdId','==',home.id).where('status','in',['READY','OPERATOR']).limit(1));
functions/src/households\historical-family-audit.ts:73:  const released=await tx.get(op.ref.collection('participantRelease').doc('state')),journal=await tx.get(op.ref.collection('participantReleaseJournal').limit(8));
functions/src/households\historical-family-audit.ts:90:   let query=receipts.orderBy(FieldPath.documentId()).limit(10);if(after)query=query.startAfter(after);
functions/src/households\historical-family-audit.ts:102:  const roots=await tx.get(this.db.collection('households').where('auditOwnerUid','==',uid).count());
functions/src/households\historical-family-audit.ts:127:    if(i.phase!=='WAITING_HISTORICAL_AUDIT'||!(await tx.get(receipts.limit(1))).empty)invalid();
functions/src/households\historical-family-audit.ts:139:     const page=await tx.get(this.db.collection('households').where('ownerUid','==',uid).where('kind','==','family').orderBy(FieldPath.documentId()).limit(1));
functions/src/households\historical-family-audit.ts:148:     let q=this.db.collection(c.stage==='INVITES'?'familyInvites':'familyOperations').where('householdId','==',home.id).orderBy(FieldPath.documentId()).limit(10);if(c.after)q=q.startAfter(c.after);
functions/src/households\historical-family-audit.ts:158:   let q=receipts.orderBy(FieldPath.documentId()).limit(1);if(p.after)q=q.startAfter(p.after);const page=await tx.get(q);
functions/src/households\historical-family-audit.ts:166:   if(p.count<1||p.count!==p.verified||p.hash!==p.verifyHash||(await tx.get(receipts.count())).data().count!==p.count)invalid();
functions/src/households\family-invites.ts:85:    const docs=await tx.get(this.db.collection(`households/${family.householdId}/members`).limit(MAX_FAMILY_MEMBERS+1));
functions/src/households\family-invites.ts:178:        const count=await tx.get(this.db.collection(`households/${p}/shoppingItems`).count());
functions/src/households\household-store.ts:73:      const legacy = await tx.get(rootRef.collection('shopping').limit(limit));
functions/src/households\household-store.ts:104:  const owned = await tx.get(db.collection('households').where('ownerUid','==',uid).limit(1));
functions/src/households\household-store.ts:109:  const members = await tx.get(home.ref.collection('members').limit(2));
functions/src/households\household-store.ts:111:  const items = await tx.get(home.ref.collection('shoppingItems').limit(limit));
functions/src/households\join-activation.ts:25:  if(chain!==o.snapshot!.hash||(await tx.get(db.collection(`households/${o.sourceHouseholdId}/shoppingItems`).limit(1))).size)invalid();
functions/src/households\join-capacity.ts:39:  const homes=await tx.get(db.collection('households').where('ownerUid','==',uid).where('kind','==','family').limit(1));
functions/src/households\join-capacity.ts:40:  const ownedWork=await tx.get(db.collection('familyOperations').where('ownerUid','==',uid).where('status','in',['READY','OPERATOR']).limit(1));
functions/src/households\join-capacity.ts:41:  const actorWork=await tx.get(db.collection('familyOperations').where('actorUid','==',uid).where('status','in',['READY','OPERATOR']).limit(1));
functions/src/households\join-source-disposition.ts:44:    if((pages===0?transferSeed(id,o):prior.chainHash)!==snapshot.hash||(await tx.get(source.limit(1))).size!==0)invalid();
functions/src/households\join-transfer-execution.ts:45:    if(o.cursor!==null||o.snapshot!.hash!==transferSeed(id,o)||(await tx.get(db.collection(`households/${o.sourceHouseholdId}/shoppingItems`).limit(1))).size)invariant();
functions/src/households\join-transfer-execution.ts:72:  if(lastPage&&(await tx.get(db.collection(`households/${o.sourceHouseholdId}/shoppingItems`).count())).data().count!==o.snapshot!.count)invariant();
functions/src/households\join-transfer-execution.ts:83:      const max=await tx.get(home.ref.collection('shoppingItems').orderBy('revision','desc').limit(1));
functions/src/households\owner-pro-loss.ts:102:  let query=this.db.collection('familyMemberships').orderBy(FieldPath.documentId()).limit(20);
functions/src/households\owner-pro-loss.ts:108:  const due=await this.db.collection('familyProLoss').where('nextAt','<=',this.clock()).orderBy('nextAt').limit(20).get();
functions/src/households\owner-account-deletion.ts:74:   const members=await tx.get(source.ref.collection('members').limit(1)),indexes=await tx.get(this.db.collection('familyMemberships').where('householdId','==',i.householdId).limit(1)),ownerIndex=await tx.get(this.db.doc(`familyMemberships/${uid}`)),items=await tx.get(source.ref.collection('shoppingItems').limit(1));
functions/src/households\owner-account-deletion.ts:75:   const reserved=await tx.get(this.db.collection('familyInvites').where('householdId','==',i.householdId).where('status','==','RESERVED').limit(1));
functions/src/households\owner-account-deletion.ts:76:   const usable=await tx.get(this.db.collection('familyInvites').where('householdId','==',i.householdId).where('status','==','PENDING').where('expiresAt','>',this.clock()).limit(1));
functions/src/households\owner-account-deletion.ts:112:  const due=await this.db.collection('familyOwnerDeletions').where('nextAt','<=',this.clock()).orderBy('nextAt').limit(20).get();let failed=false;
functions/src/households\owner-account-deletion.ts:120:  let query=this.db.collection('familyOwnerDeletions').where('phase','in',
functions/src/households\owner-account-deletion.ts:122:    .orderBy(FieldPath.documentId()).limit(20);
functions/src/households\member-account-deletion.ts:35:   const historical=await tx.get(this.db.collection('households').where('ownerUid','==',uid).where('kind','==','family').where('state','==','DISSOLVED').limit(1));
functions/src/households\member-account-deletion.ts:56:  const stored=await tx.get(ref.collection('participantRelease').doc('state')),records=await tx.get(ref.collection('participantReleaseJournal').limit(8));
functions/src/households\member-account-deletion.ts:118:  const due=await this.db.collection('familyMemberDeletions').where('nextAt','<=',this.clock()).orderBy('nextAt').limit(20).get();let failed=false;
functions/src/households\join-transfer.ts:195:    let q=c.source.ref.collection('shoppingItems').orderBy(FieldPath.documentId()).limit(10);
~~~
