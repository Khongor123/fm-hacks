import type { Metadata } from "next";
import Link from "next/link";
import { requestPasswordReset } from "@/app/actions/auth";
import { FormNotice } from "@/components/form-notice";

export const metadata: Metadata = { title: "Reset password" };

export default async function ForgotPassword({ searchParams }: { searchParams: Promise<{ error?: string; sent?: string }> }) {
  const params = await searchParams;
  return <main className="auth-page"><div className="shell auth-layout"><div className="auth-side"><p className="section-kicker">ACCOUNT HELP</p><h1>Back in<br/><em>a moment.</em></h1><p>We’ll send a password reset link to your F&M email address.</p></div><div className="form-card"><div className="form-heading"><span className="form-step">PASSWORD RESET</span><h2>Reset your password</h2><p>Remember it? <Link href="/login">Log in</Link></p></div><FormNotice error={params.error} success={params.sent ? "If this email has an account, a reset link is on its way." : undefined} /><form action={requestPasswordReset} className="form-stack"><div className="field"><label htmlFor="email">F&M email</label><input id="email" name="email" type="email" autoComplete="email" placeholder="you@fandm.edu" required /></div><button type="submit" className="button button-dark full-width">Send reset link <span aria-hidden="true">→</span></button></form></div></div></main>;
}
