import { HttpsError } from 'firebase-functions/v2/https';
import { FamilyCreateStore } from './family-create';

export function createFamilyHandler(store:()=>FamilyCreateStore) {
  return async (request:{auth?:{uid:string}|null;data:unknown}) => {
    if(!request.auth)throw new HttpsError('unauthenticated','Authentication required');
    if(!request.data||typeof request.data!=='object'||Array.isArray(request.data)||Object.keys(request.data).length)throw new HttpsError('invalid-argument','Empty request required');
    try {
      const service=store(), operationId=await service.reserve({uid:request.auth.uid});
      const outcome=await service.resume(operationId);
      return {schemaVersion:1,operationId,outcome};
    } catch(error) {
      const known=['featureDisabled','proRequired','accountUnavailable','alreadyFamily','invalidPrivateState','initializationRequired'];
      const reason=error instanceof Error&&known.includes(error.message)?error.message:'retryableUnavailable';
      throw new HttpsError('failed-precondition',reason);
    }
  };
}
