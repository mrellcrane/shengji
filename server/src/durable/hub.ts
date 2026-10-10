// The Hub Durable Object (a single instance named "hub"): a thin RPC adapter over HubHost.

import { DurableObject } from "cloudflare:workers";
import type { Notification } from "../game/online.ts";
import type { GameSnapshot } from "../game/summary.ts";
import { HubHost } from "../hub/host.ts";
import type { HubApi } from "../hub/host.ts";
import { HubService } from "../hub/service.ts";
import type { Device, GameRequest, Identity } from "../hub/service.ts";
import { apnsCredentials, createApnsClient } from "../push/apns.ts";
import type { WorkerEnv } from "../env.ts";
import { durableSql } from "./sql.ts";

export class Hub extends DurableObject<WorkerEnv> implements HubApi {
  private readonly host: HubHost;

  constructor(ctx: DurableObjectState, env: WorkerEnv) {
    super(ctx, env);
    const credentials = apnsCredentials(env);
    this.host = new HubHost(
      new HubService(durableSql(ctx.storage), { now: () => new Date() }),
      credentials === null ? null : createApnsClient(credentials),
      (message) => console.error(message),
    );
  }

  signIn(identity: Identity, displayName: string | null) {
    return this.host.signIn(identity, displayName);
  }

  authenticate(tokenHash: string) {
    return this.host.authenticate(tokenHash);
  }

  me(userId: string) {
    return this.host.me(userId);
  }

  rename(userId: string, displayName: string) {
    return this.host.rename(userId, displayName);
  }

  registerDevice(userId: string, device: Device) {
    return this.host.registerDevice(userId, device);
  }

  removeDevice(userId: string, token: string) {
    return this.host.removeDevice(userId, token);
  }

  createClub(userId: string, name: string) {
    return this.host.createClub(userId, name);
  }

  joinClub(userId: string, inviteCode: string) {
    return this.host.joinClub(userId, inviteCode);
  }

  club(userId: string, clubId: string) {
    return this.host.club(userId, clubId);
  }

  leaveClub(userId: string, clubId: string) {
    return this.host.leaveClub(userId, clubId);
  }

  prepareGame(userId: string, request: GameRequest) {
    return this.host.prepareGame(userId, request);
  }

  gameChanged(snapshot: GameSnapshot) {
    return this.host.gameChanged(snapshot);
  }

  gameDeleted(gameId: string) {
    return this.host.gameDeleted(gameId);
  }

  listGames(userId: string) {
    return this.host.listGames(userId);
  }

  notify(notifications: Notification[]) {
    return this.host.notify(notifications);
  }
}
