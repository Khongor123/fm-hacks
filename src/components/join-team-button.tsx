"use client";

import { useFormStatus } from "react-dom";

export function JoinTeamButton() {
  const { pending } = useFormStatus();
  return <button type="submit" className="button button-ghost" disabled={pending}>
    {pending ? "Joining…" : "Join team"} <span aria-hidden="true">→</span>
  </button>;
}
