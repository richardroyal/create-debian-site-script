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
# - Origin repo: <insert remote repo url>

CONFPATH="/etc/apache2/sites-available"
WWWPATH="/var/www"
REPOPATH="/opt/deploy"
REPOURL="git.bazooka.se:/opt/git" # insert remote git repo here e.g git.mycompany.com:/opt/git

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

DEPS="curl tar mysql git ssh sed apache2 grep"

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
echo "- Origin repo: <none specified>"
echo

echo "Checking dependencies.."

for DEP in $DEPS; do
	if [ -z "$(which $DEP)" ]; then
		echo "Dependency fail: you need $DEP"
		exit 1
	fi
done

echo "Dependencies OK"
echo

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

read -ep "Configure database? (y/n): "

if [[ $REPLY == [yY] ]]; then
	read -ep "Create a new database or use existing? (y/n): "

	if [[ $REPLY == [yY] ]]; then
		read -ep "Remote database host (use blank for localhost): " REMOTEHOST

		if [ -z "$REMOTEHOST" ] || [ "$REMOTEHOST" == "localhost" ]; then
			REMOTEHOST="127.0.0.1"
		fi

		while [ -z "$REMOTEPWD" ]; do
			read -esp "Database root password: " REMOTEPWD
			echo

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
			read -ep "Remote host, create SSH tunnel? (y/n): "

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
			read -esp "Existing database password: " DBPWD
			echo

			if [ -z "$DBPWD" ]; then
				echo "*** You must enter a database password"
			fi
		done
	fi
fi

if [ -z "$REMOTEHOST" ] || [ "$REMOTEHOST" == '127.0.0.1' ]; then
	REMOTEHOST="localhost"
fi

read -ep "Clone git repo? (y/n): "

if [[ $REPLY == [yY] ]]; then
	while [ -z "$REPO" ]; do
		read -ep "Name of git repo (e.g client/site): " REPO

		if [ -z "$REPO" ]; then
			echo "*** You must enter a git repo name"
		fi
	done

	if [ -d "$REPOPATH/$REPO" ]; then
		echo "*** Repo already exists!"
		exit 1
	fi

	while [ -z "$REPOURL" ]; do
		read -ep "No remote git repo specified in the file - enter remote git repo root url (e.g git.mycompany.com:/opt/git): " REPOURL

		if [ -z "$REPOURL" ]; then
			echo "*** You must enter a git repo url"
		fi
	done

	while [ -z "$REPOUSER" ]; do
		read -ep "Repo user name: " REPOUSER

		if [ -z "$REPOUSER" ]; then
			echo "*** You must enter a git user name"
		fi
	done

	read -ep "Branch to check out (blank for none/master): " -i "develop"

	echo "Cloning repo in $REPOPATH/$REPO..."
	echo
	if [ -z $REPLY ]; then
		git clone $REPOUSER@$REPOURL/$REPO $REPOPATH/$REPO 1> /dev/null
	else
		git clone -b $REPLY $REPOUSER@$REPOURL/$REPO $REPOPATH/$REPO 1> /dev/null
	fi
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

read -ep "Install WordPress? (y/n): "

if [[ $REPLY == [yY] ]]; then
	while [ -z "$WPVERSION" ]; do
		read -ep "Version nr (e.g 3.5.1): " WPVERSION

		if [ -z "$WPVERSION" ]; then
			echo "*** You must enter a version nr"
		fi
	done

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

	echo "Resetting to perms 644..."
	chmod -R 644 $WWWPATH/$DOMAIN
	chmod -R g+X $WWWPATH/$DOMAIN

	echo "Creating empty .htaccess..."
	touch $WWWPATH/$DOMAIN/.htaccess
	chmod g+w $WWWPATH/$DOMAIN/.htaccess

	echo "Setting perms on wp-content..."
	chmod -R g+w $WWWPATH/$DOMAIN/wp-content

	echo "Removing sample plugin..."
	rm $WWWPATH/$DOMAIN/wp-content/plugins/hello.php

	if [ -n "$REPO" ]; then
		if [ -d "$REPOPATH/$REPO/themes" ]; then
			echo "Creating a symlink to $REPOPATH/$REPO/themes..."
			rm -r $WWWPATH/$DOMAIN/wp-content/themes
			ln -s $REPOPATH/$REPO/themes $WWWPATH/$DOMAIN/wp-content/themes
		fi

		if [ -d "$REPOPATH/$REPO/plugins" ]; then
			echo "Creating symlinks to individual plugins in $REPOPATH/$REPO/plugins..."

			for FILE in $REPOPATH/$REPO/plugins/*; do
				echo "Symlink: $FILE"
				ln -s $FILE $WWWPATH/$DOMAIN/wp-content/plugins
			done
		fi
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

	echo "Setting WP_HOME and WP_SITEURL.."
	sed -i "${LINESTART}a define('WP_HOME', 'http://' . \$_SERVER['HTTP_HOST']);" $WWWPATH/$DOMAIN/wp-config.php
	sed -i "${LINESTART}a define('WP_SITEURL', 'http://' . \$_SERVER['HTTP_HOST']);" $WWWPATH/$DOMAIN/wp-config.php
else
	if [ -n "$REPO" ]; then
		echo "Symlinking $WWWPATH/$DOMAIN to $REPOPATH/$REPO..."
		ln -s $REPOPATH/$REPO $WWWPATH/$DOMAIN
	else
		echo "Creating index.html in $WWWPATH/$DOMAIN..."
		mkdir $WWWPATH/$DOMAIN

		echo "<!doctype html>
			<html>
				<head>
					<meta charset=\"utf-8\">
					<title>$DOMAIN</title>
				</head>

				<body>
					<p>Index of $DOMAIN</p>
				</body>
			</html>" >> $WWWPATH/$DOMAIN/index.html
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
