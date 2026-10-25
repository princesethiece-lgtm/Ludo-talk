# AN Lead Finder (iPhone app)

Audio Nation ki lead app — Punjab ke posh areas mein nayi ban rahi / nayi bani kothiyan, architects, builders aur
forum (HiFiVision, AVS Forum) par home theater / automation poochne wale log. Leads aapke Synology NAS ka
**Lead Finder scanner** (`lead-finder` folder, port 8857) dhundhta hai; ye app unhe iPhone par dikhati hai.

## App mein kya hai
- Har lead par score (0–100), city, locality, stage (Planning / Under construction / Finishing / Ready), size (gaj), BHK
- Number mila ho to **📞 number seedha button par — ek tap = call**, aur upar likha: **Owner / Architect / Contractor-Builder / Dealer** + naam
- WhatsApp button (Audio Nation ka message pehle se bhara), Share lead (staff ko bhejne ke liye), Copy number, Google Maps
- Tabs: Leads · 🔥 Hot · ⏰ Follow-up · Settings; city aur stage chips, Filter (contact type, status, source, min score)
- Follow-up date (+1 din / +3 din / +1 hafta), status (new → contacted → interested → quoted → won/lost), notes
- **Nayi hot lead par iPhone notification** (app band ho tab bhi iPhone khud kuch der mein check karta hai) + app icon par red badge
- Excel download (iPhone share sheet se WhatsApp / Mail / Files mein bhejiye)
- Neeche kheenchkar refresh; NAS na mile to setup screen jahan address badal sakte hain

## .ipa kahan milegi
Har push par GitHub khud banata hai: **Releases → AN Lead Finder build N → `AN-LeadFinder.ipa`**.
Haath se: **Actions → Build AN Lead Finder (.ipa) → Run workflow**.

## iPhone par install (Windows laptop se, iLoader)
Ludo jaisa hi: iLoader kholiye → `AN-LeadFinder.ipa` → apna Apple ID → Install. iPhone par
Settings → General → VPN & Device Management → Trust. Free Apple ID par 7 din chalti hai, phir wahi .ipa dobara install.
Aapka data NAS par rehta hai, isliye re-install par kuch nahi mitta.

## Zaroori (ek baar)
NAS par `lead-finder` project Container Manager mein chalu ho, aur reverse proxy
`lead-finder.audionation.synology.me` → `localhost:8857` bana ho (NAS ke `lead-finder/README.md` mein steps).
Office Wi-Fi par `http://NAS-IP:8857` bhi chalega — app ke setup screen mein daal sakte hain.
