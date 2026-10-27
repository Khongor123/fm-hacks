"use client";

import { useActionState, useState } from "react";
import { createInvitation } from "@/app/actions/invitations";
import { FormNotice } from "@/components/form-notice";

export function InvitationForm() {
  const [state, action, pending] = useActionState(createInvitation, { error: null, link: null });
  const [copied, setCopied] = useState(false);
  return <div className="dashboard-card"><h2>Invite an organizer</h2><p>The link works once, expires in seven days, and is tied to one F&M email. Verify the person before sharing it.</p>
    <form action={action} className="form-stack"><FormNotice error={state.error || undefined} /><div className="field"><label htmlFor="invite-email">F&M email</label><input id="invite-email" name="email" type="email" placeholder="organizer@fandm.edu" required /></div><button className="button button-dark" disabled={pending}>{pending ? "Creating…" : "Create invitation"}</button></form>
    {state.link && <div className="field"><label htmlFor="invite-link">Private invitation link</label><input id="invite-link" readOnly value={state.link} onFocus={event => event.currentTarget.select()} /><button className="text-link" type="button" onClick={async () => { await navigator.clipboard.writeText(state.link!); setCopied(true); }}>{copied ? "Copied ✓" : "Copy link"}</button><small>Copy this link now. For security, it cannot be viewed again.</small></div>}
  </div>;
}
