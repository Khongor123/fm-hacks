"use client";
import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { eventPhase, nextBoundaryDelay } from "@/lib/event";

export function EventBoundary({ initialPhase, serverNow }: { initialPhase: ReturnType<typeof eventPhase>; serverNow: number }) {
  const router = useRouter();
  useEffect(() => {
    let active = true;
    const startedAt = performance.now();
    const check = async () => {
      try {
        const response = await fetch("/api/event-time", { cache: "no-store" });
        if (!response.ok) return;
        const { now } = await response.json();
        const expectedNow = serverNow + performance.now() - startedAt;
        if (active && (eventPhase(now) !== initialPhase || Math.abs(now - expectedNow) > 2_000)) router.refresh();
      } catch { /* The next poll retries. */ }
    };
    // Browser timers overflow beyond roughly 24 days. Refresh once at the cap
    // to schedule the remaining time, while polling for clock adjustments.
    const delay = nextBoundaryDelay(serverNow, initialPhase);
    const boundaryTimer = delay !== null ? window.setTimeout(() => router.refresh(), delay) : null;
    const timer = window.setInterval(check, 15_000);
    void check();
    return () => { active = false; window.clearInterval(timer); if (boundaryTimer !== null) window.clearTimeout(boundaryTimer); };
  }, [initialPhase, router, serverNow]);
  return null;
}
