"use client";

import { motion } from "motion/react";
import { channelReleaseNotesIndexPath, type ReleaseChannel } from "../lib/channels";

type BottomNavProps = {
  channel: ReleaseChannel;
};

export default function BottomNav({ channel }: BottomNavProps) {
  const navItems = [
    { href: "/", label: "STABLE" },
    { href: "/beta", label: "BETA" },
    { href: channelReleaseNotesIndexPath(channel), label: "RELEASE NOTES" },
  ];

  return (
    <div className="bottom-nav-anchor">
      <motion.nav
        className="bottom-nav"
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.8, delay: 0.4 }}
        >
          <ul>
            {navItems.map((item, index) => (
              <li key={item.href}>
              <a href={item.href}>
                <span className="smallcaps">{item.label}</span>
              </a>
              {index < navItems.length - 1 ? (
                <span className="bottom-nav-divider" aria-hidden="true">
                  •
                </span>
              ) : null}
            </li>
            ))}
          </ul>
      </motion.nav>
      <motion.a
        className="bottom-nav-support"
        href="mailto:support@example.invalid"
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.8, delay: 0.5 }}
      >
        <span className="smallcaps">support@example.invalid</span>
      </motion.a>
    </div>
  );
}
