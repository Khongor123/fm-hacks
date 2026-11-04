import assert from "node:assert/strict";
import { test } from "node:test";
import { eventPhase, formatDeadlineRemaining, nextBoundaryDelay } from "../src/lib/event.ts";
import { registrationOpen, teamChangesOpen } from "../src/lib/config.ts";

test("registration and team changes close after November 5 Eastern", () => {
  const cutoff = Date.parse("2026-11-06T00:00:00-05:00");
  assert.equal(registrationOpen(Date.parse("2026-11-04T00:00:00-05:00")), true);
  assert.equal(registrationOpen(cutoff - 1), true);
  assert.equal(registrationOpen(cutoff), false);
  assert.equal(teamChangesOpen(cutoff - 1), true);
  assert.equal(teamChangesOpen(cutoff), false);
});

test("event-day and submission boundaries use fixed Eastern instants", () => {
  const kickoff = Date.parse("2026-11-07T09:00:00-05:00");
  const open = Date.parse("2026-11-07T10:00:00-05:00");
  const close = Date.parse("2026-11-08T10:00:00-05:00");
  assert.equal(eventPhase(kickoff - 1), "before");
  assert.equal(eventPhase(kickoff), "event");
  assert.equal(eventPhase(open - 1), "event");
  assert.equal(eventPhase(open), "submissions");
  assert.equal(eventPhase(close - 1), "submissions");
  assert.equal(eventPhase(close), "closed");
});

test("distant boundaries fit in a browser timer and closed events have no timer", () => {
  assert.equal(nextBoundaryDelay(Date.parse("2026-10-11T00:00:00-04:00"), "before"), 2_147_000_000);
  assert.equal(nextBoundaryDelay(Date.parse("2026-11-07T08:59:00-05:00"), "before"), 60_100);
  assert.equal(nextBoundaryDelay(Date.parse("2026-11-08T10:00:00-05:00"), "closed"), null);
});

test("deadline display keeps seconds visible until the cutoff", () => {
  assert.equal(formatDeadlineRemaining(60_000), "0h 01m 00s");
  assert.equal(formatDeadlineRemaining(59_000), "0h 00m 59s");
  assert.equal(formatDeadlineRemaining(1), "0h 00m 01s");
  assert.equal(formatDeadlineRemaining(0), "Deadline passed");
});
