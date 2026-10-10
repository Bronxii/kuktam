export function requireLocalEmulator(env: NodeJS.ProcessEnv): void {
  if (env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8088' ||
    env.GCLOUD_PROJECT !== 'demo-kuktam-local' ||
    env.GOOGLE_CLOUD_PROJECT !== 'demo-kuktam-local' ||
    env.METADATA_SERVER_DETECTION !== 'none') {
    throw new Error('Refusing non-local or non-demo Firestore test target');
  }
}
