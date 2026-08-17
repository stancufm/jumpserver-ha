# jumpserver-ha

Replicare reutilizabilă, pull-based, pentru o pereche de jumpservere Debian
activ/standby.

Standby-ul descarcă exportul prin utilizatorul neprivilegiat dedicat
`shadow-ha`. Un helper root local separat aplică numai arhiva validată. Activul
acceptă cheia standby-ului prin contul restricționat `shadow-export` și o
singură comandă forțată; nu oferă shell remote general sau o regulă sudo largă.

## Starea replicată

Un export reușit conține:

- căile operaționale aprobate explicit;
- metadatele conturilor umane selectate: UID, GID, home, shell și grupuri;
- directoarele home, cu owner numeric, ACL-uri și xattrs păstrate;
- inventarul pachetelor Debian, folosit numai pentru o propunere pe standby.

Descoperirea automată selectează conturile normale din `/home` cu UID
1000–59999. Conturile de serviciu și cele fără login rămân în responsabilitatea
pachetelor sau installerelor aplicațiilor. Orice conflict de nume, UID, GID,
home sau shell oprește aplicarea. Conturile nu sunt șterse automat dacă dispar
din inventarul activului.

Modul parțial este implicit și nu copiază hash-uri locale de parolă, chei
private SSH/GPG, credențiale API, password-store sau audituri SSH GR. Opțiunea
explicită `--full-clone`, destinată unei clone precum `shadow-m`/`shadow-s`,
replică pentru conturile umane selectate hash-ul din `/etc/shadow`, starea de
blocare și expirare, plus întregul home. `--sync-secrets` rămâne alias de
compatibilitate. Nu se exportă parole în clar sau fraze GPG.

Arhiva full-clone este sensibilă: este protejată în directoare 0700, cu fișier
0600, și este ștearsă după aplicarea reușită. Un eșec o păstrează pentru
diagnostic/reîncercare. Vezi [modelul de securitate](docs/SECURITY.md).

## Reconcilierea pachetelor

Sincronizarea generează numai o propunere:

```text
sudo shadow-ha-packages plan
```

Nici sincronizarea, timerul, installerul sau rolul Ansible nu instalează
automat pachete. Instalarea celor lipsă necesită o acțiune separată și aprobată:

```text
sudo shadow-ha-packages apply --yes --update
```

Versiunile diferite și pachetele suplimentare rămân numai raportate. Nu se fac
downgrade sau eliminări automate.

## Instalarea unui server nou

Rulat fără `--non-interactive`, `install.sh` solicită rolul, adresa fizică a
activului, portul SSH, VIP-ul, materialul de încredere și politica de clonare.
Standby-ul generează propria cheie Ed25519 și afișează cheia publică ce trebuie
autorizată pe activ.

Exemplu pentru o pereche full-clone, fără valori interne:

```text
sudo ./install.sh --role standby --active-address ACTIV --vip VIP \
  --active-known-hosts ./active_known_hosts --full-clone --enable-sync

sudo ./install.sh --role active --vip VIP \
  --standby-public-key ./standby_sync_ed25519.pub --full-clone
```

`--destdir` este destinat testelor. Instalarea este idempotentă și păstrează
cheia privată existentă. Dependențele Debian lipsă sunt numai raportate dacă nu
se specifică `--install-dependencies`.

## Integrarea GR

Numai activul rulează colectoarele GR. Arhiva `/var/lib/gr/config-archive`,
configurația `/etc/gr` și starea collectorului dedicat pot fi incluse în
allow-list. Standby-ul le primește, dar păstrează timerele operaționale oprite
până la promovare. `jumpserver-ha` rămâne singura autoritate de replicare.

MOTD afișează rolul, politica parțială/full-clone, ultima aplicare și comanda
pentru propunerea de pachete.
