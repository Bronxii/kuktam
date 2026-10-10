export type VerificationErrorCode =
  | 'unauthenticated' | 'invalidInput' | 'invalidToken'
  | 'wrongPackage' | 'wrongProduct' | 'purchaseNotOwned'
  | 'accountBindingMismatch' | 'tokenAlreadyBound'
  | 'playConfigurationError' | 'playUnavailable' | 'malformedPlayResponse' | 'internalConflict';

/** Safe codes only: no underlying exception, token, UID or Play payload. */
export class VerificationError extends Error {
  constructor(readonly code: VerificationErrorCode) {
    super(code);
    this.name = 'VerificationError';
  }
}
