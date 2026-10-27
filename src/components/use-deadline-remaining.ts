"use client";

import { useEffect, useState } from "react";
import { SUBMISSIONS_CLOSE } from "@/lib/event";

const deadline = Date.parse(SUBMISSIONS_CLOSE);

export function useDeadlineRemaining(serverNow: number): number {
  const [remaining, setRemaining] = useState(() => Math.max(0, deadline - serverNow));

  useEffect(() => {
    const startedAt = performance.now();
    const update = () => setRemaining(Math.max(0, deadline - serverNow - (performance.now() - startedAt)));
    update();
    const interval = window.setInterval(update, 1000);
    const cutoff = window.setTimeout(update, Math.max(0, deadline - serverNow));
    return () => {
      window.clearInterval(interval);
      window.clearTimeout(cutoff);
    };
  }, [serverNow]);

  return remaining;
}
