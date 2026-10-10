// The Sql interface on node:sqlite (in memory), so the Hub and GameRoom SQL runs in tests exactly
// as it does on a Durable Object's SQLite storage.

import { DatabaseSync } from "node:sqlite";
import type { Row, Sql, SqlValue } from "../src/storage/sql.ts";

export function memorySql(): Sql {
  const db = new DatabaseSync(":memory:");
  let inTransaction = false;
  return {
    exec(query: string, ...params: SqlValue[]): Row[] {
      return db.prepare(query).all(...params) as Row[];
    },
    transaction<T>(fn: () => T): T {
      // Durable Objects' transactionSync is used unnested here; fail loudly if that changes.
      if (inTransaction) throw new Error("nested transaction");
      inTransaction = true;
      db.exec("BEGIN");
      try {
        const result = fn();
        db.exec("COMMIT");
        return result;
      } catch (error) {
        db.exec("ROLLBACK");
        throw error;
      } finally {
        inTransaction = false;
      }
    },
  };
}
