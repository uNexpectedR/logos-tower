import type { Metadata } from "next";
import { Figtree, Syne } from "next/font/google";
import { Nav } from "@/components/Nav";
import "./globals.css";

const syne = Syne({
  subsets: ["latin"],
  variable: "--font-syne",
  weight: ["600", "700", "800"],
});

const figtree = Figtree({
  subsets: ["latin"],
  variable: "--font-figtree",
  weight: ["400", "500", "600"],
});

export const metadata: Metadata = {
  title: "Logos Tower",
  description: "Vertical jumper with the Logos lambda — persona login, public board on logos.dev.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${syne.variable} ${figtree.variable}`}>
      <body
        style={
          {
            ["--font-display" as string]: "var(--font-syne), Syne, sans-serif",
            ["--font-body" as string]: "var(--font-figtree), Figtree, sans-serif",
          } as React.CSSProperties
        }
      >
        <div className="shell">
          <Nav />
          <main className="main">{children}</main>
        </div>
      </body>
    </html>
  );
}
