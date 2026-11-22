# AN Ludo — web version

Same game as the iPhone app (web/index.html) plus: Add-to-Home-Screen icon, offline cache, sound even with the silent switch on.
Served from the NAS (folder `ludo-web`, container `an-ludo-web`, port 8860). On each start the container downloads
these files from this repo, so to update: change files here, push, then restart the container.
Uses ../web/three.min.js and ../web/voice-data.js.
