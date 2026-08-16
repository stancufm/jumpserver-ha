# jumpserver-ha

Proiect reutilizabil pentru replicarea pull-based a unei perechi de jumpservere
active/standby, pe Debian. Nodul activ este singurul care execută automatizări
operaționale; standby-ul sincronizează pasiv starea partajată și nu pornește
joburi de colectare.

Rolul instalează exportatorul restricționat pe activ, sincronizarea cu timer pe
standby, bannerul de login și runbookul operațional. Poate replica și arhiva Git
GR a configurațiilor. Nu se versionază secrete, chei private, IP-uri sau nume
interne; acestea se furnizează în afara Git.

Unitățile systemd sunt instalate atât la instalare nouă, cât și la upgrade, iar
`daemon-reload` se execută automat. Activarea timerelor operaționale este însă
un pas explicit și se face doar pe activ; un upgrade nu pornește colectări
automat pe un standby sau într-un context nou.

Identitatea hostului, rețeaua, VRRP/keepalived, machine-id și cheile SSH ale
serverului nu se copiază. Ele trebuie să rămână distincte pe fiecare nod.
