import Link from "next/link";
import Image from "next/image";
import { createClient } from "@/lib/supabase/server";

export async function SiteHeader() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  return (
    <header className="site-header">
      <div className="shell nav-inner">
        <Link href="/" className="brand" aria-label="F&MHacks home"><span className="brand-logo"><Image src="/logo.png" alt="" width={54} height={72} priority /></span><span>F&amp;MHACKS<span className="brand-year"> / 26</span></span></Link>
        <nav aria-label="Main navigation">
          <Link href="/#about">About</Link>
          <Link href="/#schedule">Schedule</Link>
          <Link href="/#rules">Rules</Link>
          {user ? <Link href="/#dashboard" className="nav-button">Dashboard</Link> : <Link href="/register" className="nav-button">Register <span aria-hidden="true">↗</span></Link>}
        </nav>
      </div>
    </header>
  );
}
