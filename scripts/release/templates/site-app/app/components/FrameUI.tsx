"use client";

import { motion } from "motion/react";
import { channelReleaseNotesIndexPath, type ReleaseChannel } from "../lib/channels";

type FrameUIProps = {
  channel: ReleaseChannel;
};

export default function FrameUI({ channel }: FrameUIProps) {
  const navItems = [
    { href: "/", label: "STABLE" },
    { href: "/beta", label: "BETA" },
    { href: channelReleaseNotesIndexPath(channel), label: "RELEASE NOTES" },
  ];

  return (
    <>
      <FrameCorners />

      <div className="frame-nav-anchor">
        <motion.nav
          className="frame-nav"
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
                  <span className="frame-divider" aria-hidden="true">
                    •
                  </span>
                ) : null}
              </li>
            ))}
          </ul>
        </motion.nav>
      </div>
    </>
  );
}

function FrameCorners() {
  return (
    <>
      <motion.div
        className="frame-corner frame-corner-top-left"
        initial={{ opacity: 0, x: -20, y: -20 }}
        animate={{ opacity: 1, x: 0, y: 0 }}
        transition={{ duration: 1, ease: "easeOut" }}
      />
      <motion.div
        className="frame-corner frame-corner-top-right"
        initial={{ opacity: 0, x: 20, y: -20 }}
        animate={{ opacity: 1, x: 0, y: 0 }}
        transition={{ duration: 1, ease: "easeOut" }}
      />
      <motion.div
        className="frame-corner frame-corner-bottom-left"
        initial={{ opacity: 0, x: -20, y: 20 }}
        animate={{ opacity: 1, x: 0, y: 0 }}
        transition={{ duration: 1, ease: "easeOut" }}
      />
      <motion.div
        className="frame-corner frame-corner-bottom-right"
        initial={{ opacity: 0, x: 20, y: 20 }}
        animate={{ opacity: 1, x: 0, y: 0 }}
        transition={{ duration: 1, ease: "easeOut" }}
      />
    </>
  );
}
