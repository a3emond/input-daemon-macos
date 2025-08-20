Launchctl Cheatsheet – InputDaemon

This document summarizes the key launchctl commands for working with the
pro.aedev.input-daemon LaunchAgent.

⸻

Plist Location

For per-user agents:

~/Library/LaunchAgents/pro.aedev.input-daemon.plist

For system-wide daemons:

/Library/LaunchDaemons/pro.aedev.input-daemon.plist


⸻

Lifecycle Commands

1. Bootstrap (load)

Register the job with launchd from its plist:

launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/pro.aedev.input-daemon.plist

    •    Reads the plist into launchd’s database.
    •    Must be done at least once after creating or changing the plist.
    •    Equivalent of “install this service”.

⸻

2. Enable

Allow the service to start automatically:

launchctl enable gui/$(id -u)/pro.aedev.input-daemon

    •    Ensures the job can run at login/boot.
    •    Combined with RunAtLoad and/or KeepAlive in the plist, this makes it persistent.

⸻

3. Kickstart (start now)

Start or restart the service immediately:

launchctl kickstart -k gui/$(id -u)/pro.aedev.input-daemon

    •    Good for testing new builds without rebooting.
    •    The -k flag forces restart if already running.

⸻

4. Bootout (unload/remove)

Unload the job completely:

launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/pro.aedev.input-daemon.plist

    •    Removes the service from launchd’s database.
    •    Use this before re-bootstrapping after changing the plist.
