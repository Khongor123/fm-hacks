"use client";

import { useActionState, useState } from "react";
import { register } from "@/app/actions/auth";
import { FormNotice } from "@/components/form-notice";

export function RegistrationForm() {
  const [state, action, pending] = useActionState(register, { error: null });
  const [email, setEmail] = useState("");
  const [repeatEmail, setRepeatEmail] = useState("");
  const [clientError, setClientError] = useState("");
  const emailsDiffer = repeatEmail.length > 0 && email.trim().toLowerCase() !== repeatEmail.trim().toLowerCase();

  return <form action={action} className="form-stack" onInvalidCapture={() => setClientError("Complete every required field, including a password of at least 12 characters.")} onSubmit={event => {
    if (emailsDiffer) { event.preventDefault(); setClientError("The email addresses do not match."); }
    else setClientError("");
  }}>
    <FormNotice error={clientError || state.error || undefined} />
    <div className="field"><label htmlFor="full_name">Full name</label><input id="full_name" name="full_name" autoComplete="name" maxLength={120} placeholder="Your first and last name" required /></div>
    <div className="field-grid"><div className="field"><label htmlFor="grade">Class year</label><select id="grade" name="grade" defaultValue="" required><option value="" disabled>Select year</option><option value="first-year">First-year</option><option value="sophomore">Sophomore</option><option value="junior">Junior</option><option value="senior">Senior</option></select></div><div className="field"><label htmlFor="tshirt_size">T-shirt size</label><select id="tshirt_size" name="tshirt_size" defaultValue="" required><option value="" disabled>Select size</option>{["S", "M", "L", "XL"].map(size => <option key={size} value={size}>{size}</option>)}</select></div></div>
    <div className="field"><label htmlFor="email">F&M email</label><input id="email" name="email" type="email" autoComplete="email" placeholder="you@fandm.edu" value={email} onChange={event => setEmail(event.target.value)} required /></div>
    <div className="field"><label htmlFor="repeat_email">Repeat your email</label><input id="repeat_email" name="repeat_email" type="email" autoComplete="off" placeholder="you@fandm.edu" value={repeatEmail} onChange={event => setRepeatEmail(event.target.value)} aria-invalid={emailsDiffer} aria-describedby={emailsDiffer ? "email-mismatch" : undefined} required />{emailsDiffer && <small id="email-mismatch" role="alert">The email addresses do not match.</small>}</div>
    <div className="field"><label htmlFor="password">Password</label><input id="password" name="password" type="password" autoComplete="new-password" minLength={12} placeholder="At least 12 characters" required /><small>Use a unique password with at least 12 characters.</small></div>
    <label className="checkbox-line"><input type="checkbox" name="attendance_commitment" required /><span>I expect to attend F&MHacks in person on November 7–8. I understand I may be waitlisted if all 75 places are filled.</span></label>
    <button type="submit" className="button button-dark full-width" disabled={pending}>{pending ? "Creating account…" : "Create account"} <span aria-hidden="true">→</span></button>
    <p className="form-footnote">Registration closes Nov 3 at 11:59 p.m. ET. We’ll never display your personal information publicly.</p>
  </form>;
}
