/** Infrastructure is injected into stores. Environment is never membership authority.
 * Only NEW growth consumes admission; existing operation recovery and required
 * exits/lifecycle enforcement retain their own transactional authorization proofs. */
export type FamilyAdmission = 'creationEnabled'|'inviteCreationEnabled'|'joinReservationEnabled';
export function familyAdmissionEnabled(config:unknown,field:FamilyAdmission,uid:string):boolean {
  if (!config || typeof config !== 'object' || Array.isArray(config)) return false;
  const policy = config as Record<string, unknown>;
  if (policy[field] === true) return true;
  if (policy[field] !== false || policy.smokeAdmissionEnabled !== true) return false;

  const cohort = policy.smokeAllowedUids;
  if (!cohort || typeof cohort !== 'object' || Array.isArray(cohort)) return false;
  const {owner, member} = cohort as Record<string, unknown>;
  const validUid = (id:unknown): id is string =>
    typeof id === 'string' && id.length > 0 && id.length <= 128 &&
    id.trim() === id && !id.includes('/');
  if (Object.keys(cohort).length !== 2 || !validUid(owner) || !validUid(member) || owner === member) return false;
  return uid === (field === 'joinReservationEnabled' ? member : owner);
}

/** Legacy phase-stepping transports are QA-only, NOT production orchestration.
 * Production start/maintenance calls the same stores/driver internally. */
export function internalFamilyPhaseCallsAllowed(env:NodeJS.ProcessEnv=process.env):boolean {
  return !env.K_SERVICE&&!env.FUNCTION_NAME&&env.GCLOUD_PROJECT==='demo-kuktam-local'&&
    /^(127\.0\.0\.1|localhost):[0-9]{1,5}$/.test(env.FIRESTORE_EMULATOR_HOST??'');
}
