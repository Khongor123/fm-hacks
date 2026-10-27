"use client";

import { useId, useState } from "react";
import Link from "next/link";
import { ThemeToggle } from "@/components/theme-toggle";

export function HeaderNavigation({ signedIn }: { signedIn: boolean }) {
  const [menuOpen, setMenuOpen] = useState(false);
  const menuId = useId();

  return (
    <div className="shell nav-inner">
      <button
        type="button"
        className="menu-toggle"
        aria-label={menuOpen ? "Close menu" : "Open menu"}
        aria-controls={menuId}
        aria-expanded={menuOpen}
        onClick={() => setMenuOpen((open) => !open)}
      >
        <span className="menu-toggle-lines" aria-hidden="true"><span /><span /><span /></span>
      </button>
      <nav id={menuId} className={menuOpen ? "nav-links is-open" : "nav-links"} aria-label="Main navigation">
        <Link href="/#about" onClick={() => setMenuOpen(false)}>About</Link>
        <Link href="/#schedule" onClick={() => setMenuOpen(false)}>Schedule</Link>
        <Link href="/#rules" onClick={() => setMenuOpen(false)}>Rules</Link>
        {signedIn
          ? <Link href="/#dashboard" className="nav-button" onClick={() => setMenuOpen(false)}>Dashboard</Link>
          : <Link href="/register" className="nav-button" onClick={() => setMenuOpen(false)}>Register <span aria-hidden="true">↗</span></Link>}
      </nav>
      <ThemeToggle />
    </div>
  );
}
