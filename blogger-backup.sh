#!/bin/bash

### Backs up a list of Blogspot sites where you have admin access.
### NOTE: Does not compress exported files, because this makes diffing
### vs. last exported piece more simple, and I have a compressed ZFS,
### so I can afford to care a bit less about space implications :-)
### Can authenticate with OAuth 2.0 (you must pre-set it up according to
### the docs), or GoogleLogin (deprecated) or API Keys (limited usability)
###   https://github.com/jimklimov/blogger-backup
### (C) Nov 2011, Jan 2014, Jun-Aug 2015 by Jim Klimov (License: MIT)
### with help from sites for older ClientLogin version:
###   http://code.google.com/apis/gdata/articles/using_cURL.html
###   http://code.google.com/apis/gdata/faq.html#clientlogin
### ...and numerous resources, blogs and comments on newer OAuth2.0 scripting:
###   https://developers.google.com/identity/protocols/OAuth2InstalledApp
###   https://developers.google.com/blogger/docs/3.0/using
###   https://developers.google.com/blogger/docs/2.0/json/using?hl=en
###   https://code.google.com/apis/console/?pli=1
###   https://developers.google.com/drive/about-auth
###   http://www.jbmurphy.com/2013/01/11/2237/
###   http://www.visualab.org/index.php/using-google-rest-api-for-analytics
###   http://jacobsalmela.com/oauth-2-0-google-analytics-desktop-using-geektool-bash-curl/
###   http://stackoverflow.com/questions/18244110/use-bash-curl-with-oauth-to-return-google-apps-user-account-date
#
### I created an "API Project" in Google API interface and enabled the
### Blogger API 3.0 there (NOTE: might not even be needed, considering use of
### Blogger Feeds directly). Actual credentials following the routine below
### were created in that project. Paraphrasing some comments from
### http://codeseekah.com/2013/12/21/headless-google-drive-uploads/ :
# I managed to create the API key using your script
# https://github.com/soulseekah/bash-utils/blob/master/google-oauth2/google-oauth2.sh
# with the CLIENT_ID and CLIENT_SECRET generated from a "Native application".
# To get those, I went to https://console.developers.google.com/
# I chose "OAuth" > "Create new client ID", "Installed application", then "Other".
# If you're not getting the URL to go to with the code you need to enter,
# then your ID and SECRET are incorrect. ID and SECRET are not your Google
# login and password, but actual API keys that you get through your
# development dashboard. 
###
### Also I've tried to use a "Server" "API Key" but only could export the
### public blog entries as a result of search query, and that requires a
### sophisticated protocol to track all posts and comments...
### Better than nothing if all else fails, so some foundation is here ;)
#
### Suitable for crontab usage like this:
###   0 * * * * [ -x /home/USERNAME/blogger-backup.sh ] && /home/USERNAME/blogger-backup.sh >/dev/null
### Don't forget to use config files, see the attached sample file.
### TODO: Use return/exit codes in a less haphazard manner, so they have
### a better diagnostic meaning than just "something non-zero" :)

### PATHs to extra programs like gdate, gdiff and curl
PATH="/bin:/usr/local/bin:/opt/COSac/bin:/usr/sfw/bin:$PATH"
export PATH
LD_LIBRARY_PATH="/lib:/usr/lib:/usr/local/lib:/usr/sfw/lib:$LD_LIBRARY_PATH"
export LD_LIBRARY_PATH

### cURL flag for HTTP Proxy usage
### Unset this var e.g. to a space to not use a proxy
[ x"$PROXYFLAG" = x ] && PROXYFLAG="-x http.proxy.com:3128"

### Where should we save the backups?
[ x"$DATADIR" = x ] && DATADIR="~/blogger-backup"

### Which login methods do we want to use for backing up?
[ x"$AUTH_METHODS" ] && \
    AUTH_METHODS="auth_ClientLogin auth_OAuth20"

### ClientLogin info for user who is a Blogspot author
[ x"$AUTH_EMAIL" = x ] && AUTH_EMAIL='username@gmail.com'
[ x"$AUTH_PASS" = x ] && AUTH_PASS='gmailPassw0rd'

### OAuthLogin info for user who is a Blogspot author
### Credentials can be set up for oneself via Google API console,
### create a project for "installed application" and a ClientID
### for each instance of the script. Also a $CONFIG_FILE_OAUTH20
### config file will be maintained to store volatile tokens.
### It is more complicated to set up, but you don't store plaintext
### login and passwords like for the simple ClientLogin - it's good :)
### In short: generate these two values in Google API web-interface
[ x"$AUTH_CLIENTID" = x ] && \
    AUTH_CLIENTID='123456-abcdef.apps.googleusercontent.com'
[ x"$AUTH_CLIENTSECRET" = x ] && \
    AUTH_CLIENTSECRET='1a2b3c--F6D5E4'
### Leave this OAuth scope at default value, should suffice for backups
### For Blogger ATOM XMLs we need the feeds; API we don't want yet :)
[ x"$AUTH_SCOPE" = x ] && \
    AUTH_SCOPE='https://www.blogger.com/feeds/'
    #AUTH_SCOPE='https://www.googleapis.com/auth/blogger.readonly'
    #AUTH_SCOPE='https://www.googleapis.com/auth/blogger'

### Alternately, a Server API Key can be used (from the same Google console)
[ x"$AUTH_SERVERAPIKEY" = x ] && \
    AUTH_SERVERAPIKEY='AbC-123'

### A copy of my fork of JSON.sh project is provided with this script:
[ x"$JSON_SH" = x ] && \
    JSON_SH="`dirname "$0"`/JSON.sh"

### A space-separated list of blogs in the form of "BLOG_ID:HUMAN_NAME [*]"
### The Blogger ID can be found in the Web-GUI as ?blogID=XXX& part of Mgmt URL
### (or as part of the Button URL in the Settings/Basic/Export screen)
### The "HUMAN_NAME" is used to tag backup files, and so should have no spaces
[ x"$BLOGGER_LIST" = x ] && BLOGGER_LIST="12345678901234567:myblogname"

### Filename part for the backup file...
TIMESTAMP="`TZ=UTC gdate '+%Y%m%dT%H%M%SZ'`" || TIMESTAMP="last-$$"

### Default config-file names, first name that exists - wins
### Protect the file with "chmod 600", it has passwords!
for C in \
    "$CONFIG_FILE" \
    "$HOME/.blogger-backup.conf" \
    "~/.blogger-backup.conf" \
    "`dirname $0`/.blogger-backup.conf" \
; do
    [ x"$CONFIG_FILE" = x -a -s "$C" -a -r "$C" ] && \
        CONFIG_FILE="$C" && break
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
        *) echo "Unknown param: '$1'" 2>&1; exit 1;;
    esac
    shift
done

if [ x"$CONFIG_FILE" != x -a -s "$CONFIG_FILE" -a -r "$CONFIG_FILE" ]; then
    echo "INFO: Using config-file: $CONFIG_FILE"
    . "$CONFIG_FILE"
fi
[ -n "$CONFIG_FILE" ] && \
    CONFIG_FILE_OAUTH20="$CONFIG_FILE.oauth-tokens" || \
    CONFIG_FILE_OAUTH20="$HOME/.blogger-backup.conf.oauth-tokens"
    # This is likely to fail in OAuth login if there is no config file with
    # saved ClientID and ClientSecret - but we leave this for the later test

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

CURL() {
    curl -k $PROXYFLAG --silent "$@"
}

### A dictionary value used in Google headers
AUTH_TYPE=""
### File extension - .xml for Blogger Atom, .json for JSON
BLOG_EXT=""
auth_ClientLogin() {
    ### Try to get a Google AUTH token for Blogspot
    ### with simple ClientLogin (obsolete in May 2015)
    [ -z "${AUTH_EMAIL}" -o -z "${AUTH_PASS}" ] && \
        echo "SKIP: auth_ClientLogin(): email or password not provided" >&2 && \
        return 1

    AUTH_TOKEN="`CURL https://www.google.com/accounts/ClientLogin --data-urlencode Email=${AUTH_EMAIL} --data-urlencode Passwd=${AUTH_PASS} -d accountType=GOOGLE -d source=Google-cURL-Example -d service=blogger | egrep -i '^auth=' | head -1`" || AUTH_TOKEN=""
    if [ x"$AUTH_TOKEN" = x ]; then
        #### Retry once for hiccups
        AUTH_TOKEN="`CURL https://www.google.com/accounts/ClientLogin --data-urlencode Email=${AUTH_EMAIL} --data-urlencode Passwd=${AUTH_PASS} -d accountType=GOOGLE -d source=Google-cURL-Example -d service=blogger | egrep -i '^auth=' | head -1`" || AUTH_TOKEN=""
        if [ x"$AUTH_TOKEN" = x ]; then
            echo "FATAL: Can't auth to google via ClientLogin">&2
            return 1
        fi
    fi

    BLOG_EXT=.xml
    AUTH_TYPE="GoogleLogin"
    return 0
}

auth_OAuth20() {
    ### Try to get a Google AUTH token for Blogspot with OAuth 2.0;
    [ -z "${AUTH_CLIENTID}" -o -z "${AUTH_CLIENTSECRET}" ] && \
        echo "SKIP: auth_OAuth20(): ClientId or ClientSecret not provided" >&2 && \
        return 1

    if [ x"$CONFIG_FILE_OAUTH20" != x -a -s "$CONFIG_FILE_OAUTH20" -a -r "$CONFIG_FILE_OAUTH20" ] && \
       [ "`egrep '^(AUTH_CODE|AUTH_TOKEN|REFR_TOKEN)=' "$CONFIG_FILE_OAUTH20" | wc -l`" -eq 3 ] \
    ; then
        echo "INFO: Using config-file with cached OAuth tokens: $CONFIG_FILE_OAUTH20"
        . "$CONFIG_FILE_OAUTH20"
    else
        echo "INFO: A config-file with cached OAuth tokens is not (yet) available: $CONFIG_FILE_OAUTH20"
        echo "Phase 1: initial request to allow application access to your Google Account"
        echo "(interactive work will be needed in a browser) using 'Other' API token type."
        RESPONSE="`CURL -v "https://accounts.google.com/o/oauth2/auth" --data "client_id=$AUTH_CLIENTID&scope=$AUTH_SCOPE&response_type=code&redirect_uri=urn:ietf:wg:oauth:2.0:oob" 2>&1`"
        if [ $? != 0 -o -z "$RESPONSE" ]; then
            echo "FATAL: Can't auth to google via OAuth2.0 initial request">&2
            echo "$RESPONSE" >&2
            return 1
        fi
        [ -s "$JSON_SH" ] && [ -x "$JSON_SH" ] || { echo "FATAL: JSON.sh is required!"; exit 127; }

        AUTH_URL="`echo "$RESPONSE" | egrep '^\< Location: ' | sed 's,^< Location: ,,'`"
        if [ $? != 0 -o -z "$AUTH_URL" ]; then
            echo "FATAL: Can't auth to google via OAuth2.0 initial request: did not retrieve the Auth URL">&2
            echo "$RESPONSE" >&2
            return 1
        fi

        echo "In the browser go to this URL:"; echo "  $AUTH_URL"
        echo "There log into your Google account with administrative access to blogs,"
        echo "and press OK to grant access to this application (blogger-backup script)."
        echo "Copy the resulting authorization code into this shell. Hit enter when done..."
        echo "NOTE: The resulting code can only be 'redeemed' into ultimate tokens once."
        read AUTH_CODE

        RESPONSE="`CURL "https://accounts.google.com/o/oauth2/token" --data "client_id=$AUTH_CLIENTID&client_secret=$AUTH_CLIENTSECRET&code=$AUTH_CODE&grant_type=authorization_code&redirect_uri=urn:ietf:wg:oauth:2.0:oob&scope="`"
        if [ $? != 0 -o -z "$RESPONSE" ] || echo "$RESPONSE" | grep -i "error" ; then
            echo "FATAL: Can't auth to google via OAuth2.0 autorization code:">&2
            echo "$RESPONSE" >&2
            return 1
        fi

        echo "$RESPONSE"
        AUTH_TOKEN="`echo "$RESPONSE" | $JSON_SH -b -x 'access_token' | awk '{print $2}' | sed 's,^"\(.*\)"$,\1,'`" && \
        REFR_TOKEN="`echo "$RESPONSE" | $JSON_SH -b -x 'refresh_token' | awk '{print $2}' | sed 's,^"\(.*\)"$,\1,'`" && \
        [ -n "$AUTH_TOKEN" -a -n "$REFR_TOKEN" -a -n "$AUTH_CODE" ] && \
        { ( echo "# Last regenerated : `date`"
            echo "AUTH_CODE='$AUTH_CODE'"
            echo "REFR_TOKEN='$REFR_TOKEN'"
            echo "AUTH_TOKEN='$AUTH_TOKEN'"
          ) > "$CONFIG_FILE_OAUTH20" && chmod 600 "$CONFIG_FILE_OAUTH20"; }
    fi

    # Check the AUTH_TOKEN for expiration (defaults to 3600 sec)
    RESPONSE="`CURL "https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=${AUTH_TOKEN}"`"
    if [ $? != 0 -o -z "$RESPONSE" ] ; then
        echo "FATAL: Can't auth to google via OAuth2.0: failed to verify known AUTH_TOKEN">&2
        echo "$RESPONSE" >&2
        return 1
    fi

    if echo "$RESPONSE" | egrep -i 'error|invalid_token' >/dev/null ; then
        echo "INFO: AUTH_TOKEN for google OAuth2.0 has expired, refreshing..."

        RESPONSE="`CURL -d "client_secret=$AUTH_CLIENTSECRET&grant_type=refresh_token&refresh_token=$REFR_TOKEN&client_id=$AUTH_CLIENTID" https://accounts.google.com/o/oauth2/token`" && \
        AUTH_TOKEN="`echo "$RESPONSE" | $JSON_SH -b -x 'access_token' | awk '{print $2}' | sed 's,^"\(.*\)"$,\1,'`" && \
        [ -n "$AUTH_TOKEN" -a -n "$REFR_TOKEN" -a -n "$AUTH_CODE" ] && \
        { ( echo "# Last regenerated : `date`"
            echo "AUTH_CODE='$AUTH_CODE'"
            echo "REFR_TOKEN='$REFR_TOKEN'"
            echo "AUTH_TOKEN='$AUTH_TOKEN'"
          ) > "$CONFIG_FILE_OAUTH20" && chmod 600 "$CONFIG_FILE_OAUTH20"; }
        if [ $? != 0 -o ! -n "$AUTH_TOKEN" ] ; then
            echo "FATAL: Can't auth to google via OAuth2.0: failed to refresh AUTH_TOKEN">&2
            echo "$RESPONSE" >&2
        fi
    fi

#    echo "FATAL: Can't auth to google via OAuth 2.0 (not implemented yet)" >&2
#    AUTH_TYPE="X-GoogleOAuth"
#    return 1

    BLOG_EXT=.xml
    AUTH_TYPE="OAuth"
#    AUTH_TYPE="Bearer"
    return 0
}

auth_APIKey() {
    [ -z "$AUTH_SERVERAPIKEY" -o x"$AUTH_SERVERAPIKEY" = x'AbC-123' ] && \
        echo "SKIP: auth_APIKey(): API Key not provided" >&2 && \
        return 1

    BLOG_EXT=.json
    AUTH_TYPE="X-GoogleAPIkey"
    return 0
}

requestBlog() {
    # Auth-dependent ways of requesting the blog, CURL to stdout

    case "$AUTH_TYPE" in
        GoogleLogin|OAuth|Bearer)
            # Add a trailing newline to make diff happy
            CURL --location \
                --header "Authorization: ${AUTH_TYPE} ${AUTH_TOKEN}" \
                --header "GData-Version: 2" \
                "http://www.blogger.com/feeds/${BLOG_ID}/archive" && \
            echo ""
            return $?
            ;;
        X-GoogleOAuth)
            # Authorization: Bearer oauth2-token
            echo "ERROR: AUTH_TYPE='$AUTH_TYPE' not implemented (yet)"; return 1;;
        X-GoogleAPIkey) # JSON list of public blog entries, and it is 
                        # paginated (default 10, maxResults=20) so we'd
                        # better iterate this; comments are linked to...
            echo "WARNING: Requesting Blogger API v3, following the pagination is not implemented (yet)" \
                 "- so only fetched the newest 10 entries" >&2
            CURL --location \
                "https://www.googleapis.com/blogger/v3/blogs/${BLOG_ID}/posts?&key=${AUTH_SERVERAPIKEY}"
            return $?
            ;;
    esac

    echo "ERROR: Unknown AUTH_TYPE='$AUTH_TYPE'" >&2
    return 2
}

blogExport() {
    BLOG_ID="`echo "$1" | ( IFS=: read _B _H; echo "$_B")`"
    HUMAN_NAME="`echo "$1" | ( IFS=: read _B _H; echo "$_H")`"
    [ -z "$TRY_COUNT" ] && TRY_COUNT=1

    ### Most recent of previous backups; if there were no changes,
    ### then we don't want to keep an identical newer backup file.
    LASTFILE="`ls -1dtr ${DATADIR}/backup-blogger-${HUMAN_NAME}.*${BLOG_EXT} | tail -1`"
    NEWFILE="$DATADIR/backup-blogger-${HUMAN_NAME}.$TIMESTAMP${BLOG_EXT}"

    requestBlog > "$NEWFILE" && [ -s "$NEWFILE" ] || \
        { echo "=== ${HUMAN_NAME}: Error exporting the blog, removing new copy" >&2
          rm -f "$NEWFILE"; return 1; }
    # At this point we had no CURL errors and got a nonempty file

    # TODO: Parsing "ls" might be faster though maybe less portable
    # Anyhow, file data is cached at this moment so should not be dead-slow
    if [ `wc -c < "$NEWFILE"` -lt 500 ] 2>/dev/null && \
       grep 'Not Found' < "$NEWFILE" | grep 'Error 404' \
    ; then
        echo "=== ${HUMAN_NAME}: Got an HTTP-404 (Not found) error when exporting the blog"
        if [ "$TRY_COUNT" -lt 2 ]; then
            ### We have a suggested hourly schedule.
            ### And OAuth token lifetime is 3600s.
            ### These may interact somehow funny ;)
            echo "INFO: Will try to re-authenticate (maybe token expired?) and re-export, attempt $TRY_COUNT..."
            $GOOD_AUTH_METHOD && \
            TRY_COUNT=$(($TRY_COUNT+1)) blogExport "$@"
            return $?
        else
            echo "=== ${HUMAN_NAME}: Got an HTTP-404 (Not found) error when exporting the blog and could not fix it" >&2
            rm -f "$NEWFILE"
            return 1
        fi
    fi

    [ x"$LASTFILE" != x -a x"$TIMESTAMP" != xlast ] && \
    diff "$LASTFILE" "$NEWFILE" >/dev/null && \
    echo "=== ${HUMAN_NAME}: Matches last available backup, removing new copy" && \
    rm -f "$NEWFILE"

    ls -1d "$DATADIR/backup-blogger-${HUMAN_NAME}."*${BLOG_EXT} | tail -3
}

###########################################################################
### The logic skeleton: try to log into google, try to export data, done

GOOD_AUTH_METHOD=""
for A in $AUTH_METHODS; do
    case "$A" in
        auth_ClientLogin|auth_OAuth20|auth_APIKey)
            "$A" && GOOD_AUTH_METHOD="$A" && break ;;
        *) echo "FATAL: Unknown auth method requested (see script for supported AUTH_METHODS): '$A'" >&2
            exit 3
            ;;
    esac
done

if [ x"$AUTH_TYPE" = x ] || [ x"$GOOD_AUTH_METHOD" = x ]; then
    echo "FATAL: Not logged into Google services! Quitting..." >&2
    exit 1
fi

echo "INFO: Logged in to Google/Blogspot with ${GOOD_AUTH_METHOD}, got token: ${AUTH_TOKEN} (type ${AUTH_TYPE})"

if [ x"$BLOGGER_LIST" = x ]; then
    echo "FATAL: No BLOGGER_LIST is configured, thus nothing to do! Quitting..." >&2
    exit 2
fi

_RESULT=0
for BLOG in $BLOGGER_LIST; do
    blogExport "$BLOG" || _RESULT=$?
done

### To unwind a huge single-line XML (e.g. for diff'ing) you may want this:
### tidy -xml -utf8 -indent -quiet < backup-blogger-myblogname.20111123T234153Z.xml > b

exit $_RESULT
