"use client";

import { useState } from "react";
import { SidebarNav } from "./sidebar-nav";

/** Phone and tablet menu. Closes itself when a link is chosen. */
export function MobileNav() {
  const [open, setOpen] = useState(false);

  return (
    <div className="md:hidden">
      <button
        type="button"
        aria-expanded={open}
        aria-controls="mobile-nav-panel"
        onClick={() => setOpen((v) => !v)}
        className="flex min-h-11 items-center gap-2 rounded-lg border border-line bg-panel px-3 text-sm font-medium text-ink"
      >
        <span aria-hidden="true" className="text-base leading-none">
          {open ? "✕" : "☰"}
        </span>
        Menu
      </button>

      {open ? (
        <div
          id="mobile-nav-panel"
          className="absolute inset-x-0 top-full z-30 border-b border-line bg-ink px-4 py-4 shadow-lg"
        >
          <SidebarNav onNavigate={() => setOpen(false)} />
        </div>
      ) : null}
    </div>
  );
}
