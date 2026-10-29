import type { Metadata } from "next";
import Link from "next/link";
import { confirmPasswordReset } from "@/app/actions/auth";

export const metadata: Metadata = { title: "Confirm password reset", robots: { index: false, follow: false }, referrer: "no-referrer" };

export default async function VerifyPasswordReset({ searchParams }: { searchParams: Promise<{ token_hash?: string }> }) {
  const { token_hash: tokenHash } = await searchParams;
  return <main className="auth-page"><div className="shell auth-layout"><div className="auth-side"><p className="section-kicker">ACCOUNT HELP</p><h1>Almost<br/><em>there.</em></h1><p>Continue to choose a new password for your F&MHacks account.</p></div><div className="form-card"><div className="form-heading"><span className="form-step">PASSWORD RESET</span><h2>Confirm reset</h2><p>This step makes sure your reset link is opened by you.</p></div>{tokenHash ? <form action={confirmPasswordReset} className="form-stack"><input type="hidden" name="token_hash" value={tokenHash} /><button type="submit" className="button button-dark full-width">Continue to reset password <span aria-hidden="true">→</span></button></form> : <p className="form-notice error" role="alert">Reset link is invalid. <Link href="/forgot-password">Request another</Link>.</p>}</div></div></main>;
}
