import type { Metadata } from "next";
import { SiteHeader } from "@/components/site-header";
import "./globals.css";
import { Analytics } from "@vercel/analytics/next"

const initializeTheme = `(() => {
  try {
    const saved = localStorage.getItem("fmh-theme");
    document.documentElement.dataset.theme = saved === "light" ? "light" : "dark";
  } catch {
    document.documentElement.dataset.theme = "dark";
  }
})();`;

export const metadata: Metadata = {
  title: { default: "F&MHacks 2026", template: "%s | F&MHacks 2026" },
  description:
    "A 24-hour student hackathon at Franklin & Marshall College, November 7–8, 2026.",
  icons: { icon: { url: "/hero-logo-badge.webp", type: "image/webp" } },
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: initializeTheme }} />
      </head>
      <body>
        <SiteHeader />
        {children}
        <footer className="site-footer">
          <div className="shell footer-inner">
            <span>Built by Khongor Ochirkhuu &apos;29</span>
            <span>
              Built for curious people at Franklin & Marshall College.
            </span>
          </div>
        </footer>
      </body>
    </html>
  );
}
