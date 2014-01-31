#!/bin/bash

### Backs up a list of Blogspot sites where you have admin access.
### (C) Nov 2011, Jan 2014 by Jim Klimov with help from sites:
###   http://code.google.com/apis/gdata/articles/using_cURL.html
###   http://code.google.com/apis/gdata/faq.html#clientlogin
### Suitable for crontab usage like this:
###   0 * * * * [ -x /home/USERNAME/blogger-backup.sh ] && /home/USERNAME/blogger-backup.sh >/dev/null
### Don't forget to use config files, see the attached sample file.

### PATHs to extra programs like gdate, gdiff and curl
PATH=/bin:/usr/local/bin:/opt/COSac/bin:/usr/sfw/bin:$PATH
export PATH
LD_LIBRARY_PATH=/lib:/usr/lib:/usr/local/lib:/usr/sfw/lib:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH

### cURL flag for HTTP Proxy usage
### Unset this var to not use a proxy
[ x"$PROXYFLAG" = x ] && PROXYFLAG="-x http.proxy.com:3128"

### Where should we save the backups?
[ x"$DATADIR" = x ] && DATADIR="~/blogger-backup"

### Login info for user who is a Blogspot author
[ x"$AUTH_EMAIL" = x ] && AUTH_EMAIL='username@gmail.com'
[ x"$AUTH_PASS" = x ] && AUTH_PASS='gmailPassw0rd'

### A list of blogs in the form of "BLOG_ID:HUMAN_NAME [*]"
### The Blogger ID can be found in the Web-GUI as ?blogID=XXX& part of Mgmt URL
### (or as part of the Button URL in the Settings/Basic/Export screen)
[ x"$BLOGGER_LIST" = x ] && BLOGGER_LIST="12345678901234567:myblogname"

### Filename part for the backup file...
TIMESTAMP="`TZ=UTC gdate '+%Y%m%dT%H%M%SZ'`" || TIMESTAMP="last-$$"

### Default config-file names
### Protect the file with "chmod 600", it has passwords!
for C in $CONFIG_FILE $HOME/.blogger-backup.conf ~/.blogger-backup.conf \
    "`dirname $0`/.blogger-backup.conf"; do
	[ x"$CONFIG_FILE" = x -a -s "$C" -a -r "$C" ] && CONFIG_FILE="$C"
done

while [ $# -gt 0 ]; do
    case "$1" in
	-h) echo "$0: downloads a Google blogspot blog for local backup"
	    echo "  -c	Config-file with settings (password, blogid, etc.)"
	    echo "  blogid:humanname	alternate entries for your blog list"
	    exit 0
	    ;;
	-c) if [ x"$2" != x ]; then
		if [ -s "$2" -a -r "$2" ]; then
		    CONFIG_FILE="$2"
		else
		    echo "FATAL: CONFIG_FILE='$2' is not accessible" >&2
		    exit 1
		fi
	    else
		echo "FATAL: Param required for -c" >&2
		exit 1
	    fi
	    shift
	    ;;
	*:*) BLOGGER_LIST_ALT="$BLOGGER_LIST_ALT $1" ;;
	*) echo "Unknown param: '$1'" 2>&1;;
    esac
    shift
done

if [ x"$CONFIG_FILE" != x -a -s "$CONFIG_FILE" -a -r "$CONFIG_FILE" ]; then
    echo "INFO: Using config-file: $CONFIG_FILE"
    . "$CONFIG_FILE"
fi

if [ ! -d "$DATADIR" -o ! -w "$DATADIR" ]; then
    echo "FATAL: DATADIR '$DATADIR' not accessible! Did you create it?" >&2
    exit 1
else
    echo "INFO: Using DATADIR '$DATADIR'"
fi

if [ x"$BLOGGER_LIST_ALT" != x ]; then
    echo "INFO: Overriding BLOGGER_LIST with '$BLOGGER_LIST_ALT'"
    BLOGGER_LIST="$BLOGGER_LIST_ALT"
fi

### Try to get a Google AUTH token for Blogspot
AUTH="`curl -k $PROXYFLAG --silent https://www.google.com/accounts/ClientLogin --data-urlencode Email=${AUTH_EMAIL} --data-urlencode Passwd=${AUTH_PASS} -d accountType=GOOGLE -d source=Google-cURL-Example -d service=blogger | egrep -i '^auth=' | head -1`" || AUTH=""
if [ x"$AUTH" = x ]; then
	AUTH="`curl -k $PROXYFLAG --silent https://www.google.com/accounts/ClientLogin --data-urlencode Email=${AUTH_EMAIL} --data-urlencode Passwd=${AUTH_PASS} -d accountType=GOOGLE -d source=Google-cURL-Example -d service=blogger | egrep -i '^auth=' | head -1`" || AUTH=""
	if [ x"$AUTH" = x ]; then
		echo "FATAL: Can't auth to google">&2
		exit 1
	fi
fi

if [ x"$BLOGGER_LIST" = x ]; then
	echo "Logged in to Google/Blogspot, got token: $AUTH" >&2
	echo "FATAL: No BLOGGER_LIST is configured, thus nothing to do! Quitting..." >&2
	exit 2
fi

blogExport() {
	BLOG_ID="`echo $1 | ( IFS=: read _B _H; echo "$_B")`"
	HUMAN_NAME="`echo $1 | ( IFS=: read _B _H; echo "$_H")`"

	### Most recent of previous backups; if there were no changes,
	### then we don't want to keep an identical newer backup file.
	LASTFILE="`ls -1tr ${DATADIR}/backup-blogger-${HUMAN_NAME}.*.xml | tail -1`"

	curl -k $PROXYFLAG --silent --location \
	  --header "Authorization: GoogleLogin $AUTH" \
          "http://www.blogger.com/feeds/${BLOG_ID}/archive" \
	> "$DATADIR/backup-blogger-${HUMAN_NAME}.$TIMESTAMP.xml" && \
        [ x"$LASTFILE" != x -a x"$TIMESTAMP" != xlast ] && \
        gdiff -q "$LASTFILE" "$DATADIR/backup-blogger-${HUMAN_NAME}.$TIMESTAMP.xml" && \
        echo "=== ${HUMAN_NAME}: Matches last available backup, removing new copy" && \
        rm -f "$DATADIR/backup-blogger-${HUMAN_NAME}.$TIMESTAMP.xml"

	ls -1 "$DATADIR/backup-blogger-${HUMAN_NAME}."*.xml | tail -3
}

for BLOG in $BLOGGER_LIST; do
	blogExport $BLOG
done

### tidy -xml -utf8 -indent -quiet < backup-blogger-k3njim.20111123T234153Z.xml > b

