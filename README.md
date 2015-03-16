# blogger-backup
Automatically exported from code.google.com/p/blogger-backup

= Overview

This is a simple project to log into your Blogger (google blogspot) account 
and retrieve all your blogs (text markup and comments, at least - not sure 
about binary blobs and pictures) using the documented Google API. 

It saves the data for each single export as one XML file with a unique name 
(timestamp involved) into a directory you can specify in the config file.
If the previous export had the same content, the freshly retrieved file is
removed to save space. This way you can place the script into your crontab,
and regularly fetch backups from Blogger using new disk space only as long
as you actually post something on your blog.

If you are a prolific writer, then it is of course also possible to set up
tracking of several blogs linked to your Google account ;)

= Rationale/Pre-history

Sometime back in 2011 I was writing a lot of blog text while postprocessing
our very interesting family trip, to save and share our experiences. While
I was editing the posts with some fixes here and there, the Blogger servers
had some hiccup, blogs were frozen for a week and ultimately servers were
rolled back to a days before my wave of editorial fixes. I never got to redo
them again (these are such small perfective things you might never remember
again... and prohibitively time-consuming to re-read everything and reporoduce).
Google never said "sorry" (some of their engineers did, however, while trying
to help and/or not keep users in the dark via the engineering blog), and never
provided the backup snapshots of the blogs, nor good tools to do the backup.

So I had to forge my own tools, and hope to not step into this trap again ;)

= LICENSE

I publish this script under the terms of MIT License.
Copyright (C) 2011-2015 by Jim Klimov

// Hope this helps,
Jim Klimov
