"use client";

import { useState } from "react";

export function CopyTeamCode({ code }: { code: string }) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(code);
      setCopied(true);
    } catch {
      setCopied(false);
    }
  }

  return <button type="button" className="text-link" onClick={copy} aria-label="Copy team code">
    {copied ? "Copied" : "Copy code"}
  </button>;
}
