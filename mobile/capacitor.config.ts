import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'xyz.radiokoleka.app',
  appName: 'Radiokoleka',
  webDir: 'www',
  backgroundColor: '#07051f',
  ios: { contentInset: 'automatic' },
  android: { backgroundColor: '#07051f' },
};

export default config;
