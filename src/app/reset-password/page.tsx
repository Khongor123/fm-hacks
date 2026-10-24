import type { Metadata } from "next";
import Link from "next/link";
import { updatePassword } from "@/app/actions/auth";
import { FormNotice } from "@/components/form-notice";

export const metadata: Metadata = { title: "Choose a new password" };

export default async function ResetPassword({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const params = await searchParams;
  return <main className="auth-page"><div className="shell auth-layout"><div className="auth-side"><p className="section-kicker">ACCOUNT HELP</p><h1>A fresh<br/><em>start.</em></h1><p>Choose a new password to get back into your F&MHacks account.</p></div><div className="form-card"><div className="form-heading"><span className="form-step">PASSWORD RESET</span><h2>New password</h2><p>Reset link expired? <Link href="/forgot-password">Request another</Link></p></div><FormNotice error={params.error} /><form action={updatePassword} className="form-stack"><div className="field"><label htmlFor="password">New password</label><input id="password" name="password" type="password" autoComplete="new-password" minLength={8} placeholder="At least 8 characters" required /></div><button type="submit" className="button button-dark full-width">Save password <span aria-hidden="true">→</span></button></form></div></div></main>;
}
