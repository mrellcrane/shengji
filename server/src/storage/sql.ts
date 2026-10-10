// The one storage interface the Hub and GameRoom logic needs: synchronous SQLite. In a Durable
// Object it is `ctx.storage.sql` (see durableSql in src/durable/); in Node tests it is node:sqlite
// (test/support/sqlite.ts), so the same SQL runs in both.

export type SqlValue = string | number | null;
export type Row = Record<string, SqlValue>;

export interface Sql {
  /** Runs one statement with `?` parameters and returns its rows (empty for writes). */
  exec(query: string, ...params: SqlValue[]): Row[];
  /** Runs `fn` atomically: all of its writes are applied, or none (if it throws). Not nestable. */
  transaction<T>(fn: () => T): T;
}

/** The first row, or null. */
export function one(sql: Sql, query: string, ...params: SqlValue[]): Row | null {
  const rows = sql.exec(query, ...params);
  return rows.length > 0 ? rows[0] : null;
}

/** Reads a TEXT column. */
export function text(row: Row, column: string): string {
  const value = row[column];
  if (typeof value !== "string") throw new TypeError(`column ${column} is not text`);
  return value;
}

/** Reads a nullable TEXT column. */
export function textOrNull(row: Row, column: string): string | null {
  const value = row[column];
  if (value === null || value === undefined) return null;
  if (typeof value !== "string") throw new TypeError(`column ${column} is not text`);
  return value;
}

/** Reads an INTEGER column. */
export function int(row: Row, column: string): number {
  const value = row[column];
  if (typeof value === "bigint") return Number(value);
  if (typeof value !== "number") throw new TypeError(`column ${column} is not a number`);
  return value;
}
