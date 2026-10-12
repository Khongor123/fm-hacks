"use client";
import { useEffect, useState } from "react";
import { SUBMISSIONS_CLOSE } from "@/lib/event";

export function DeadlineCountdown({ serverNow }: { serverNow: number }) {
  const [remaining, setRemaining] = useState(Math.max(0, Date.parse(SUBMISSIONS_CLOSE) - serverNow));
  useEffect(() => {
    const start = performance.now();
    const timer = window.setInterval(() => setRemaining(Math.max(0, Date.parse(SUBMISSIONS_CLOSE) - serverNow - (performance.now() - start))), 1000);
    return () => window.clearInterval(timer);
  }, [serverNow]);
  const seconds = Math.floor(remaining / 1000);
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  return <div className="deadline-clock"><span className="card-label">PROJECT DEADLINE</span><strong>{remaining ? `${hours}h ${String(minutes).padStart(2, "0")}m` : "Deadline passed"}</strong><p>Sunday, November 8 · 10:00 a.m. ET</p></div>;
}
