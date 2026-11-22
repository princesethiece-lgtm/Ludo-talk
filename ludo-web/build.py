# Makes ludo-web/index.html from web/index.html (same game + Add-to-Home-Screen / offline / silent-switch extras).
# Run after every change to web/index.html:  python3 ludo-web/build.py
import os
root=os.path.dirname(os.path.abspath(__file__))
s=open(os.path.join(root,'..','web','index.html')).read()
s=s.replace('<title>AN Ludo</title>','''<meta name="apple-mobile-web-app-title" content="AN Ludo">
<meta name="theme-color" content="#08122A">
<link rel="manifest" href="manifest.webmanifest">
<link rel="apple-touch-icon" href="icon-180.png">
<title>AN Ludo</title>''',1)
s=s.replace('<script src="three.min.js"></script>','''<script>
/* Web version: play sound even when the iPhone silent switch is on (Safari 16.4+), and keep working offline */
try{if(navigator.audioSession)navigator.audioSession.type="playback";}catch(e){}
if("serviceWorker" in navigator&&location.protocol!=="file:"){addEventListener("load",function(){navigator.serviceWorker.register("sw.js").catch(function(){});});}
</script>
<script src="three.min.js"></script>''',1)
open(os.path.join(root,'index.html'),'w').write(s)
sw=os.path.join(root,'sw.js');t=open(sw).read()
import re
t=re.sub(r"an-ludo-v(\d+)",lambda m:"an-ludo-v%d"%(int(m.group(1))+1),t,1);open(sw,'w').write(t)
