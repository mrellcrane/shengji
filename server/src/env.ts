// The Worker's environment: bindings and vars from wrangler.toml (the generated `Env` in
// worker-configuration.d.ts, made by `wrangler types`) plus the optional secrets.

export interface WorkerEnv extends Env {
  /** Enables POST /v1/auth/dev (set to a fresh random value by each deploy, for its smoke test). */
  DEV_AUTH_SECRET?: string;
  /** APNs auth key (.p8 PEM). Push is enabled when this, APNS_KEY_ID and APPLE_TEAM_ID are set. */
  APNS_KEY_P8?: string;
  APNS_KEY_ID?: string;
  APPLE_TEAM_ID?: string;
}
