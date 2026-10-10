// The Sql interface on a SQLite-backed Durable Object's storage.

import type { Row, Sql } from "../storage/sql.ts";

export function durableSql(storage: DurableObjectStorage): Sql {
  return {
    exec: (query, ...params) => storage.sql.exec(query, ...params).toArray() as Row[],
    transaction: (fn) => storage.transactionSync(fn),
  };
}
