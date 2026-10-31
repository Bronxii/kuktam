/** Infrastructure is injected into stores. Environment is never membership authority.
 * Only NEW growth consumes admission; existing operation recovery and required
 * exits/lifecycle enforcement retain their own transactional authorization proofs. */
export type FamilyAdmission = 'creationEnabled'|'inviteCreationEnabled'|'joinReservationEnabled';
export function familyAdmissionEnabled(config:unknown,field:FamilyAdmission):boolean {
  return !!config&&typeof config==='object'&&!Array.isArray(config)&&
    (config as Record<string,unknown>)[field]===true;
}

/** Legacy phase-stepping transports are QA-only, NOT production orchestration.
 * Production start/maintenance calls the same stores/driver internally. */
export function internalFamilyPhaseCallsAllowed(env:NodeJS.ProcessEnv=process.env):boolean {
  return !env.K_SERVICE&&!env.FUNCTION_NAME&&env.GCLOUD_PROJECT==='demo-kuktam-local'&&
    /^(127\.0\.0\.1|localhost):[0-9]{1,5}$/.test(env.FIRESTORE_EMULATOR_HOST??'');
}
