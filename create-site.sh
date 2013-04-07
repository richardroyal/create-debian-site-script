#!/bin/bash

# This script can help you do the following:
# - Create a remote or local database
# - Clone a git repo for the source files
# - Install and configure a new web site
# - Download and install a version of WordPress
# - Symlink the web root or WP themes folder to the git repo
# The following paths will be used as convention:
# - Local web root: /var/www
# - Local repo root: /opt/deploy
# - Origin repo: <insert>

CONFPATH="/etc/apache2/sites-available"
WWWPATH="/var/www"
REPOPATH="/opt/deploy"
REPOURL="<insert>"

REPO=""
DOMAIN=""
REPOUSER=""
WPVERSION=""
WPLANG=""
WPLANGSUB=""

REMOTEHOST=""
REMOTEPWD=""
DBNAME=""
DBUSER=""
DBPWD=""
DBPORT=3306
SSHTUNNEL=false
SSHPID=0

function revert {
	echo "Reverting..."

	echo "Disabling site..."
	a2dissite $DOMAIN > /dev/null 2>&1

	if [ -n "$DOMAIN" ]; then
		echo "Removing $CONFPATH/$DOMAIN..."
		rm $CONFPATH/$DOMAIN > /dev/null 2>&1

		echo "Removing $WWWPATH/$DOMAIN..."
		rm -r $WWWPATH/$DOMAIN > /dev/null 2>&1
	fi

	if [ -n "$REPO" ]; then
		echo "Removing $REPOPATH/$REPO..."
		rm -r $REPOPATH/$REPO > /dev/null 2>&1
	fi

	echo "Reloading apache..."
	service apache2 reload > /dev/null 2>&1

	echo "Revert OK"
}

echo
echo "=========================================="
echo "This script can help you do the following:"
echo
echo "- Create a remote or local database"
echo "- Clone a git repo for the source files"
echo "- Install and configure a new web site"
echo "- Download and install a version of WordPress"
echo "- Symlink the web root to the git repo"
echo
echo "The following paths will be used as convention:"
echo
echo "- Local web root: $WWWPATH"
echo "- Local repo root: $REPOPATH"
echo "- Origin repo: $REPOURL"
echo

read -ep "Continue (y/n): "

if [[ "$REPLY" != [yY] ]]; then
	exit 0
fi

while [ -z "$DOMAIN" ]; do
	read -ep "Site name (e.g company.dev): " DOMAIN

	if [ -z "$DOMAIN" ]; then
		echo "*** You must enter a site name"
	fi
done

if [ -e "$CONFPATH/$DOMAIN" ] || [ -d "$WWWPATH/$DOMAIN" ]; then
	echo "*** Site already exists!"
	exit 1
fi

CONF="<VirtualHost *:80>
	ServerName $DOMAIN
	DocumentRoot $WWWPATH/$DOMAIN

	<Directory $WWWPATH/$DOMAIN>
		Options FollowSymLinks
		AllowOverride All
		Order allow,deny
		allow from all
	</Directory>

	ErrorLog \${APACHE_LOG_DIR}/$DOMAIN-error.log
</VirtualHost>"

read -ep "Create a new database or use existing (y/n): "

if [[ $REPLY == [yY] ]]; then
	read -ep "Remote database host (use blank for localhost): " REMOTEHOST

	if [ -z "$REMOTEHOST" ] || [ "$REMOTEHOST" == "localhost" ]; then
		REMOTEHOST="127.0.0.1"
	fi

	while [ -z "$REMOTEPWD" ]; do
		read -eps "Database root password: " REMOTEPWD

		if [ -z "$REMOTEPWD" ]; then
			echo "*** You must enter the database root password"
		fi
	done

	while [ -z "$DBNAME" ]; do
		read -ep "New database name: " DBNAME

		if [ -z "$DBNAME" ]; then
			echo "*** You must enter a database name"
		fi
	done

	while [ -z "$DBUSER" ]; do
		read -ep "New database user: " DBUSER

		if [ -z "$DBUSER" ]; then
			echo "*** You must enter a database user"
		fi
	done

	while [ -z "$DBPWD" ]; do
		RNDPWD=$(date +%s | sha256sum | base64 | head -c 12)
		read -ep "New database password: " -i "$RNDPWD" DBPWD

		if [ -z "$DBPWD" ]; then
			echo "*** You must enter a database password"
		fi
	done

	if [ $REMOTEHOST != "127.0.0.1" ]; then
		read -ep "Remote host, create SSH tunnel (y/n): "

		if [[ "$REPLY" == [yY] ]]; then
			SSHTUNNEL=true

			while [ -z "$SSHUSER" ]; do
				read -ep "Remote host SSH username: " SSHUSER

				if [ -z "$SSHUSER" ]; then
					echo "*** You must enter an SSH username"
				fi
			done

			echo "Creating SSH tunnel to $REMOTEHOST..."

			ssh -fN -L 3307:127.0.0.1:3306 $UNAME@$REMOTEHOST

			if [ $? != 0 ]; then
				echo "*** FAILED"
				exit 1
			fi

			SSHPID=$(ps aux | grep "[s]sh -fN -L 3307:127.0.0.1:3306 $UNAME@$REMOTEHOST" | awk '{ print $2 }')
		fi
	fi

	echo "Creating database $DBNAME..."

	DBHOST=$REMOTEHOST

	if $SSHTUNNEL; then
		DBPORT=3307
		DBHOST="127.0.0.1"
	fi

	mysql -h $DBHOST -P $DBPORT -u root -p$REMOTEPWD -e "CREATE DATABASE $DBNAME; GRANT ALL ON $DBNAME.* TO '$DBUSER'@'localhost' IDENTIFIED BY '$DBPWD';"

	if [ $? != 0 ]; then
		echo "*** FAILED"
	else
		echo "Created database $DBNAME@$REMOTEHOST using login $DBUSER/$DBPWD"
	fi

	if $SSHTUNNEL; then
		echo "Killing SSH tunnel..."
		kill $SSHPID
	fi
else
	read -ep "Existing database host (use blank for localhost): " REMOTEHOST

	while [ -z "$DBNAME" ]; do
		read -ep "Existing database name: " DBNAME

		if [ -z "$DBNAME" ]; then
			echo "*** You must enter a database name"
		fi
	done

	while [ -z "$DBUSER" ]; do
		read -ep "Existing database user: " DBUSER

		if [ -z "$DBUSER" ]; then
			echo "*** You must enter a database user"
		fi
	done

	while [ -z "$DBPWD" ]; do
		read -eps "Existing database password: " DBPWD

		if [ -z "$DBPWD" ]; then
			echo "*** You must enter a database password"
		fi
	done
fi

if [ -z "$REMOTEHOST" ] || [ "$REMOTEHOST" == '127.0.0.1' ]; then
	REMOTEHOST="localhost"
fi

read -ep "Name of git repo (e.g client/site, or blank for none): " REPO

if [ -n "$REPO" ]; then
	if [ -d "$REPOPATH/$REPO" ]; then
		echo "*** Repo already exists!"
		exit 1
	fi

	while [ -z "$REPOUSER" ]; do
		read -ep "Repo user name: " REPOUSER

		if [ -z "$REPOUSER" ]; then
			echo "*** You must enter a git user name"
		fi
	done

	echo "Cloning repo in $REPOPATH/$REPO..."
	echo
	git clone $REPOUSER@$REPOURL/$REPO $REPOPATH/$REPO 1> /dev/null
	echo

	if [ $? != 0 ]; then
		echo "*** FAILED"
		revert
		exit 1
	fi

	echo "Setting git filemode to false..."
	cd $REPOPATH/$REPO
	git config core.filemode false
	cd - > /dev/null 2>&1
fi

read -ep "Install WordPress? Enter version nr (e.g 3.5.1 or blank for no): " WPVERSION

if [ -n "$WPVERSION" ]; then
	read -ep "WordPress language (e.g sv_SE or blank for default): " WPLANG

	if [ -n "$WPLANG" ]; then
		WPLANGSUB="$(echo $WPLANG | cut -c1-2)."
		WPVERSION="$WPVERSION-$WPLANG"
	fi
fi

echo "Creating new site..."

if [ -n "$WPVERSION" ]; then
	WPURL="http://${WPLANGSUB}wordpress.org/wordpress-$WPVERSION.tar.gz"

	echo "Downloading WordPress $WPVERSION from $WPURL..."
	echo
	mkdir $WWWPATH/$DOMAIN
	curl "$WPURL" | tar -xz -C $WWWPATH/$DOMAIN --strip 1
	echo

	if [ $? != 0 ]; then
		echo "*** FAILED"
		revert
		exit 1
	fi

	echo "Resetting to basic perms..."
	chmod -R 644 $WWWPATH/$DOMAIN

	echo "Creating empty .htaccess..."
	touch $WWWPATH/$DOMAIN/.htaccess
	chmod g+w $WWWPATH/$DOMAIN/.htaccess

	echo "Setting perms on wp-content..."
	chmod -R g+w $WWWPATH/$DOMAIN/wp-content

	echo "Removing sample plugin..."
	rm $WWWPATH/$DOMAIN/wp-content/plugins/hello.php

	if [ -n "$REPO" ] && [ -d "$REPOPATH/$REPO/themes" ]; then
		echo "Creating a symlink to $REPOPATH/$REPO/themes..."
		rm -r $WWWPATH/$DOMAIN/wp-content/themes
		ln -s $REPOPATH/$REPO/themes $WWWPATH/$DOMAIN/wp-content/themes
		echo "Remember to symlink individual plugins manually!"
	fi

	echo "Setting up wp-config.php..."
	mv $WWWPATH/$DOMAIN/wp-config-sample.php $WWWPATH/$DOMAIN/wp-config.php

	LINESTART=$(grep -n "define('DB_NAME'" $WWWPATH/$DOMAIN/wp-config.php | cut -d: -f1)
	sed -i "${LINESTART}d" $WWWPATH/$DOMAIN/wp-config.php
	sed -i "${LINESTART}i define('DB_NAME', '$DBNAME');" $WWWPATH/$DOMAIN/wp-config.php

	LINESTART=$(grep -n "define('DB_USER'" $WWWPATH/$DOMAIN/wp-config.php | cut -d: -f1)
	sed -i "${LINESTART}d" $WWWPATH/$DOMAIN/wp-config.php
	sed -i "${LINESTART}i define('DB_USER', '$DBUSER');" $WWWPATH/$DOMAIN/wp-config.php

	LINESTART=$(grep -n "define('DB_PASSWORD'" $WWWPATH/$DOMAIN/wp-config.php | cut -d: -f1)
	sed -i "${LINESTART}d" $WWWPATH/$DOMAIN/wp-config.php
	sed -i "${LINESTART}i define('DB_PASSWORD', '$DBPWD');" $WWWPATH/$DOMAIN/wp-config.php

	LINESTART=$(grep -n "define('DB_HOST'" $WWWPATH/$DOMAIN/wp-config.php | cut -d: -f1)
	sed -i "${LINESTART}d" $WWWPATH/$DOMAIN/wp-config.php
	sed -i "${LINESTART}i define('DB_HOST', '$REMOTEHOST');" $WWWPATH/$DOMAIN/wp-config.php

	read -ep "Table prefix (including underscore, blank for default): " -i "wp_" WPPREFIX

	if [ -n "$WPPREFIX" ]; then
		sed -i "s/'wp_'/'$WPPREFIX'/" $WWWPATH/$DOMAIN/wp-config.php
	fi

	echo "Getting auth salt values..."
	echo
	SALT=$(curl https://api.wordpress.org/secret-key/1.1/salt/)
	echo

	LINESTART=$(grep -n "define('AUTH_KEY'" $WWWPATH/$DOMAIN/wp-config.php | cut -d: -f1)
	LINEEND=$(echo "$SALT" | wc -l)
	LINEEND=$(($LINESTART + $LINEEND - 1))

	sed -i "${LINESTART},${LINEEND}d" $WWWPATH/$DOMAIN/wp-config.php

	while read -r LINE; do
		sed -i "${LINESTART}i $LINE" $WWWPATH/$DOMAIN/wp-config.php
		LINESTART=$(($LINESTART + 1))
	done <<< "$SALT"

	echo "Setting FS_METHOD to direct..."
	LINESTART=$(grep -n "define('WP_DEBUG'" $WWWPATH/$DOMAIN/wp-config.php | cut -d: -f1)
	sed -i "${LINESTART}a define('FS_METHOD', 'direct');" $WWWPATH/$DOMAIN/wp-config.php
else
	if [ -n "$REPO" ]; then
		echo "Symlinking $WWWPATH/$DOMAIN to $REPOPATH/$REPO..."
		ln -s $REPOPATH/$REPO $WWWPATH/$DOMAIN
	else
		echo "Creating empty folder in $WWWPATH/$DOMAIN..."
		mkdir $WWWPATH/$DOMAIN
	fi
fi

echo "Setting owner of $WWWPATH/$DOMAIN to $USER:www-data..."
chown -R $USER:www-data $WWWPATH/$DOMAIN

echo "Creating and enabling site configuration file at $CONFPATH/$DOMAIN..."
echo "$CONF" > $CONFPATH/$DOMAIN
a2ensite $DOMAIN 1> /dev/null

if [ $? != 0 ]; then
	echo "*** FAILED"
	revert
	exit 1
fi

echo "Reloading apache..."
service apache2 reload 1> /dev/null

if [ $? != 0 ]; then
	echo "*** FAILED"
	revert
	exit 1
fi

echo "Done! Remember to add $DOMAIN to your local hosts file."
exit 0