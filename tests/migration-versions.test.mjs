import { readdirSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

test("Supabase migration versions are unique", () => {
  const files = readdirSync(new URL("../supabase/migrations/", import.meta.url))
    .filter((file) => file.endsWith(".sql"));
  const versions = files.map((file) => file.split("_")[0]);
  assert.equal(new Set(versions).size, versions.length, `Duplicate migration version in ${files.join(", ")}`);
});
