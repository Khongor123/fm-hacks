"use client";
import { formatDeadlineRemaining } from "@/lib/event";
import { useDeadlineRemaining } from "@/components/use-deadline-remaining";

export function DeadlineCountdown({ serverNow }: { serverNow: number }) {
  const remaining = useDeadlineRemaining(serverNow);
  return <div className="deadline-clock"><span className="card-label">PROJECT DEADLINE</span><strong>{formatDeadlineRemaining(remaining)}</strong><p>Sunday, November 8 · 10:00 a.m. ET</p></div>;
}
