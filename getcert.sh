#!/bin/sh
# 
# getcert.sh
# Version 1.1
#
# Wichtige Hinweise: Dieses Script muss im Home-Verzeichnis in einem eigenen
# Ordner liegen, beispielsweise unter ~/getcert/getcert.sh
# Erstellen Sie darin selbst keine weiteren Ordner.
# Sonst funktioniert die automatische Erkennung des Ablaufdatums wahrscheinlich nicht.
# 
# Wenn die Zeile "Make sure your web server displays the following content at"
# erscheint, pausiert das Script.
# Erstellen Sie dann auf Ihrem Webserver die geforderte Datei mit dem 
# darunter geforderten Inhalt, beispielsweise im Ordner
#
# /var/www/html/.well-known/acme-challenge
#
# Drücken Sie erst dann die Enter-Taste, um fortzufahren
#
# Der LetsEncrypt-Client muss mit
# git clone https://github.com/letsencrypt/letsencrypt
# im Home-Verzeichnis installiert sein.
#
# Andernfalls geben Sie in der nächsten Zeile
# ein anderes Verzeichnis an.
LEBIN=~/letsencrypt/letsencrypt-auto

set -e

#########################
# passen Sie die folgenden Parameter an
country=DE            # Ihr Land, beispielsweise DE
state="Germany"       # Ihr Staat, beispielsweise Germany
town="Munic"          # Ihre Stadt beispielsweise Berlin
email=ich@irdendwo.de # Ihre E-Mail-Adresse
DAYS_REMAINING=30     # Verbleibende Tage bis zur Erneuerung
#########################

if [ ! -e ${LEBIN} ]; then
echo "$0: Fehler: Installieren Sie zuerst letsencrypt."
exit 1
fi

if [ $# -lt 1 ]; then
    echo "$0: Fehler: Ein Domain-Name ist erforderlich."
    exit 1
fi
domain=$1

outdir="certs/$domain"
key="$outdir/privkey1.pem"
csr="$outdir/signreq.der"

check_cert() {
# letzten Sicherungsordner ermitteln
LASTFOLDER=`find . -mindepth 1 -maxdepth 1 -type d  -exec stat -c "%Y %n" {} \;  |sort -n -r |head -1 |awk '{print $2}'`
echo "Prüfe Zertifikate aus: ${LASTFOLDER}"

if [ -e ${LASTFOLDER}/0000_cert.pem ]; then
get_days_exp ${LASTFOLDER}/0000_cert.pem
echo -n "INFO: Zertifikat für ${FOR_DOMAIN} läuft in ${DAYS_EXP} Tagen ab. "
echo ""

 if [ "$DAYS_EXP" -gt "$DAYS_REMAINING" ]; then
   echo "Erneuerung nicht nötig." 
   exit 0 
 else
  echo "Das Zertifikat läuft bald ab! Versuche es zu erneuern..."
  echo ""

 fi
fi
}

move_files() {
# PEM-Dateien in eigene Ordner verschieben
DATE=`date +"%Y-%m-%d-%H-%M-%S"`
mkdir ${DATE}
mv 0000_cert.pem ${DATE}
mv 0000_chain.pem ${DATE}
mv 0001_chain.pem ${DATE}
}

get_days_exp() {
# Ablaufdatum ermitteln
  local dname=$(openssl x509 -in $1 -text -noout|grep "Subject:"|cut -c 21-)  
  local d1=$(date -d "`openssl x509 -in $1 -text -noout|grep "Not After"|cut -c 25-`" +%s)
  local d2=$(date -d "now" +%s)
  # Return result in global variable
  DAYS_EXP=$(echo \( $d1 - $d2 \) / 86400 |bc)
  FOR_DOMAIN=$dname
}

get_cert() {
#
# Verwenden Sie den zusätzlichen Parammeter --test-cert,
# um das Script auszuprobieren.
# Damit erzeugen Sie ein Test-Zertifikat, das aber vom Browser
# wie ein selbst-signiertes Zertifikat behandelt wird.
# Entfernen Sie das Kommentarzeich vor der nächsten Zeile.
 TEST_PARAM=--test-cert
#
${LEBIN} certonly \
    ${TEST_PARAM} \
    --agree-tos \
    --authenticator manual \
    --rsa-key-size 4096 \
    --text \
    --config-dir letsencrypt/etc --logs-dir letsencrypt/log \
    --work-dir letsencrypt/lib --email "$email" \
    --csr "$csr" 
}

# neues Zertifikat erstellen
create_cert () {
tmpdir=
cleanup() {
    if [ -n "$tmpdir" -a -d "$tmpdir" ]; then
        rm -rf "$tmpdir"
    fi
}

trap cleanup INT QUIT TERM EXIT
tmpdir=`mktemp -d -t mkcert-XXXXXXX`

sslcnf="$tmpdir/openssl.cnf"
cat /etc/ssl/openssl.cnf > "$sslcnf"
echo "[SAN]" >> "$sslcnf"
echo "subjectAltName=DNS:$domain" >> "$sslcnf"

mkdir -p "$outdir"
echo "Neues Zertifikat erstellen"
# Eigene SSH-Schlüssel für die Zertifikatanforderung erzeugen
openssl req \
    -new -newkey rsa:4096 -sha256 -nodes \
    -keyout "$key" -out "$csr" -outform der \
    -subj "/C=$country/ST=$state/L=$town/O=$domain/emailAddress=$email/CN=$domain" \
    -reqexts SAN \
    -config "$sslcnf"

get_cert # Zertifikat anfordern
 }

# Zertifikat erneuern/neu anfordern
renew_cert () {
echo "Zertifikat neu anfordern"
get_cert ## Zertifikat anfordern
}

if [ -d "$outdir" ]; then
    echo "Ausgabe-Verzeichnis $outdir ist vorhanden."
    # das Script wurde bereits einmal ausgeführt
    check_cert # prüfe Ablaufdatum, bei langer Gültigkeit Script-Ende
    renew_cert # Zertifikat erneuern
    move_files # PEM-Dateien verschieben
else
    create_cert # neues Zertifikat erzeugen
    move_files # PEM-Dateien verschieben
fi
echo "Fertig."

exit 0

