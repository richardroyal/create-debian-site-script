create-debian-site-script
=========================

Bash script capable of creating and configuring a new apache site and database from a git repo, optionally with WordPress.

This script can help you do the following:

* Create a remote or local database
* Clone a git repo for the source files
* Install and configure a new web site
* Download and install a version of WordPress
* Symlink the web root or WP themes folder to the git repo

The following paths will be used as convention:

* Local web root: /var/www
* Local repo root: /opt/deploy
* Origin repo: <insert>