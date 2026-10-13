"use client";

import { useEffect, useState } from "react";
import { EVENT_START } from "@/lib/config";

function remaining(now: number) {
  const total = Math.max(0, new Date(EVENT_START).getTime() - now);
  return {
    days: Math.floor(total / 86_400_000),
    hours: Math.floor((total / 3_600_000) % 24),
    minutes: Math.floor((total / 60_000) % 60),
    seconds: Math.floor((total / 1_000) % 60),
    finished: total === 0,
  };
}

export function Countdown({ serverNow }: { serverNow?: number }) {
  const [time, setTime] = useState<ReturnType<typeof remaining> | null>(null);
  useEffect(() => {
    const start = performance.now();
    const tick = () => setTime(remaining(serverNow === undefined ? Date.now() : serverNow + performance.now() - start));
    tick();
    const timer = window.setInterval(tick, 1000);
    return () => window.clearInterval(timer);
  }, [serverNow]);

  return (
    <div className="countdown" aria-live="off">
      <div className="countdown-label">{time?.finished ? "The hackathon has begun" : "Countdown to kickoff"}</div>
      <div className="countdown-units" aria-label={time ? `${time.days} days, ${time.hours} hours, ${time.minutes} minutes, ${time.seconds} seconds until kickoff` : "Loading countdown"}>
        {(["days", "hours", "minutes", "seconds"] as const).map((unit) => (
          <div className="countdown-unit" key={unit}>
            <strong>{String(time?.[unit] ?? 0).padStart(2, "0")}</strong>
            <span>{unit}</span>
          </div>
        ))}
      </div>
      <p>Saturday, November 7 · 9:00 a.m. ET</p>
    </div>
  );
}