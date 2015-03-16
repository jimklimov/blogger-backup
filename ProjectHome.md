I was looking for a way to back up my Blogger.com/Blogspot.com blogs from UNIX (Linux, Solaris) using command-line and crontabs.

First I looked for ways to use wget to back up the blog, but found some cURL examples on code.google.com and extended them instead.

Now I have (and publish) a simple script which can use a config-file with your gmail address and password, path for backups, optional HTTP Proxy info, and a list of "blogid:humanname" tokens. This allows to "export" a number of blogs where you have editorial access in a manner equivalent to Settings/Basic/Export Web-GUI action (into a large XML file).

The script also compares the newly-fetched blog backup to the last one you've had, and if there are no differences - deletes the new file. This saves space, so you can run this script frequently :)

//Jim Klimov