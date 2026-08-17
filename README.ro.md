# jumpserver-ha

Replicare reutilizabilă, pull-based, pentru o pereche de jumpservere Debian
activ/standby.

Standby-ul descarcă exportul cu utilizatorul neprivilegiat dedicat `shadow-ha`.
Un helper root local separat aplică numai arhiva validată. Activul acceptă cheia
standby-ului prin contul restricționat `shadow-export` și o singură comandă
forțată; nu există shell remote general sau regulă sudo largă.

## Starea replicată

Un export reușit conține:

- căile operaționale aprobate explicit;
- metadatele conturilor umane selectate: UID, GID, home, shell și grupuri;
- directoarele home, cu owner numeric, ACL-uri și xattrs păstrate;
- inventarul pachetelor Debian, utilizat numai pentru o propunere pe standby.

Descoperirea automată selectează conturile normale din `/home` cu UID
1000-59999. Conturile de serviciu și cele fără login sunt excluse. Orice conflict
de nume, UID sau GID oprește aplicarea înaintea modificării home-urilor.
Conturile nu sunt șterse automat dacă dispar din inventarul activului.

Cheile private SSH/GPG, fișierele de credențiale API, password-store și
auditurile SSH GR sunt excluse implicit, inclusiv sub o cale partajată aprobată.
Se includ numai prin decizia explicită `--sync-secrets`, după analiza
[modelului de securitate](docs/SECURITY.md).

## Reconcilierea pachetelor

Sincronizarea generează numai o propunere:

```text
sudo shadow-ha-packages plan
```

Nici sincronizarea, timerul, installerul sau rolul Ansible nu instalează automat
pachete. Instalarea pachetelor lipsă necesită o acțiune separată și confirmată:

```text
sudo shadow-ha-packages apply --yes --update
```

Versiunile diferite și pachetele suplimentare rămân numai raportate. Nu se fac
downgrade sau eliminări automate.

## Instalarea unui server nou

Rulat fără `--non-interactive`, `install.sh` solicită rolul, adresa fizică a
activului, portul SSH, VIP-ul, materialul de încredere și opțiunile de
sincronizare. Standby-ul generează propria cheie Ed25519 și afișează cheia
publică ce trebuie autorizată pe activ.

Exemple fără valori interne:

```text
sudo ./install.sh --role standby --active-address ACTIV --vip VIP \
  --active-known-hosts ./active_known_hosts --enable-sync

sudo ./install.sh --role active --vip VIP \
  --standby-public-key ./standby_sync_ed25519.pub
```

`--destdir` este destinat testelor. Instalarea este idempotentă și păstrează
cheia privată existentă. Pachetele Debian lipsă sunt numai raportate dacă nu se
specifică `--install-dependencies`.

## Integrarea GR

Numai activul rulează colectoarele GR. Arhiva `/var/lib/gr/config-archive`,
configurația `/etc/gr` și starea collectorului dedicat pot fi incluse în
allow-list. Standby-ul le primește, dar păstrează timer-ele operaționale oprite
până la promovare. `jumpserver-ha` rămâne singura autoritate de replicare.

MOTD afișează rolul, ultima aplicare și comanda pentru propunerea de pachete.
