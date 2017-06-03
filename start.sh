#!/bin/bash

if [ ! -d /var/lib/cloudstack/management/.ssh ]; then
	mknod /dev/loop6 -m0660 b 7 6
fi

chown cloud:cloud /var/lib/cloudstack/management/.ssh/*

until nc -z mysql 3306; do
    echo "waiting for mysql-server..."
    sleep 1
done

mysql -u "$mysql_user" -p"$mysql_root_password" -h mysql \
   -e "show databases;"|grep -q cloud

case $? in
  1)
	echo "deploying new cloud databases"
	INITIATED=false
	cloudstack-setup-databases cloud:${mysql_password}@mysql \
	--deploy-as=root:${mysql_root_password} -m ${mgmt_server_key} \
	-k ${database_secretkey} -i ${mgmt_server_ip}
    ;;
  0)
	echo "using existing databases"
	INITIATED=true
	cloudstack-setup-databases cloud:${mysql_password}@mysql -k ${database_secretkey} -m ${mgmt_server_key} -i ${mgmt_server_ip}
    ;;
  *)
	echo "cannot access database"
	exit 12
    ;;
esac

PATH=/bin:/usr/bin:/sbin:/usr/sbin
NAME=cloudstack-management
DESC="CloudStack-specific Tomcat servlet engine"
DAEMON=/usr/bin/jsvc
CATALINA_HOME=/usr/share/cloudstack-management
DEFAULT=/etc/cloudstack/management/tomcat6.conf
JVM_TMP=/tmp/$NAME-temp

# We have to explicitly set the HOME variable to the homedir from the user "cloud"
# This is because various scripts run by the management server read the HOME variable
# and fail when this init script is run manually.
HOME=$(echo ~cloud)

if [ `id -u` -ne 0 ]; then
	echo "You need root privileges to run this script"
	exit 1
fi
 
# Make sure tomcat is started with system locale
if [ -r /etc/default/locale ]; then
	. /etc/default/locale
	export LANG
fi

. /lib/lsb/init-functions
. /etc/default/rcS


# The following variables can be overwritten in $DEFAULT

# Run Tomcat 6 as this user ID
TOMCAT6_USER=tomcat6

# The first existing directory is used for JAVA_HOME (if JAVA_HOME is not
# defined in $DEFAULT)
JDK_DIRS="/usr/lib/jvm/java-7-openjdk-amd64 /usr/lib/jvm/java-7-openjdk-i386 /usr/lib/jvm/java-7-oracle /usr/lib/jvm/java-7-openjdk /usr/lib/jvm/java-7-sun"

# Look for the right JVM to use
for jdir in $JDK_DIRS; do
    if [ -r "$jdir/bin/java" -a -z "${JAVA_HOME}" ]; then
	JAVA_HOME="$jdir"
    fi
done
export JAVA_HOME

# Directory for per-instance configuration files and webapps
CATALINA_BASE=/usr/share/cloudstack-management

# Use the Java security manager? (yes/no)
TOMCAT6_SECURITY=no

# Default Java options
# Set java.awt.headless=true if JAVA_OPTS is not set so the
# Xalan XSL transformer can work without X11 display on JDK 1.4+
# It also looks like the default heap size of 64M is not enough for most cases
# so the maximum heap size is set to 128M
if [ -z "$JAVA_OPTS" ]; then
	JAVA_OPTS="-Djava.awt.headless=true -Xmx128M"
fi

# End of variables that can be overwritten in $DEFAULT

# overwrite settings from default file
if [ -f "$DEFAULT" ]; then
	. "$DEFAULT"
fi

if [ ! -f "$CATALINA_HOME/bin/bootstrap.jar" ]; then
	log_failure_msg "$NAME is not installed"
	exit 1
fi

[ -f "$DAEMON" ] || exit 0

POLICY_CACHE="$CATALINA_BASE/work/catalina.policy"

JAVA_OPTS="$JAVA_OPTS -Djava.endorsed.dirs=$CATALINA_HOME/endorsed -Dcatalina.base=$CATALINA_BASE -Dcatalina.home=$CATALINA_HOME -Djava.io.tmpdir=$JVM_TMP"

# Set the JSP compiler if set in the tomcat6.default file
if [ -n "$JSP_COMPILER" ]; then
	JAVA_OPTS="$JAVA_OPTS -Dbuild.compiler=$JSP_COMPILER"
fi

if [ "$TOMCAT6_SECURITY" = "yes" ]; then
	JAVA_OPTS="$JAVA_OPTS -Djava.security.manager -Djava.security.policy=$POLICY_CACHE"
fi

# Set juli LogManager if logging.properties is provided
if [ -r "$CATALINA_BASE"/conf/logging.properties ]; then
  JAVA_OPTS="$JAVA_OPTS "-Djava.util.logging.manager=org.apache.juli.ClassLoaderLogManager" "-Djava.util.logging.config.file="$CATALINA_BASE/conf/logging.properties"
fi

# Define other required variables
CATALINA_PID="/var/run/$NAME.pid"
BOOTSTRAP_CLASS=org.apache.catalina.startup.Bootstrap
JSVC_CLASSPATH="/usr/share/java/commons-daemon.jar:$CATALINA_HOME/bin/bootstrap.jar:/etc/cloudstack/management:/usr/share/cloudstack-management/setup"

# Look for Java Secure Sockets Extension (JSSE) JARs
if [ -z "${JSSE_HOME}" -a -r "${JAVA_HOME}/jre/lib/jsse.jar" ]; then
    JSSE_HOME="${JAVA_HOME}/jre/"
fi
export JSSE_HOME

if [ -z "$JAVA_HOME" ]; then
	log_failure_msg "no JDK found - please set JAVA_HOME"
	exit 1
fi

if [ ! -d "$CATALINA_BASE/conf" ]; then
	log_failure_msg "invalid CATALINA_BASE: $CATALINA_BASE"
	exit 1
fi

log_daemon_msg "Starting $DESC" "$NAME"

# Regenerate POLICY_CACHE file
umask 022
echo "// AUTO-GENERATED FILE from /etc/tomcat6/policy.d/" \
	> "$POLICY_CACHE"
echo ""  >> "$POLICY_CACHE"
if ls $CATALINA_BASE/conf/policy.d/*.policy > /dev/null 2>&1 ; then
	cat $CATALINA_BASE/conf/policy.d/*.policy \
	>> "$POLICY_CACHE"
fi

# Remove / recreate JVM_TMP directory
rm -rf "$JVM_TMP"
mkdir "$JVM_TMP" || {
	log_failure_msg "could not create JVM temporary directory"
	exit 1
}
chown $TOMCAT6_USER "$JVM_TMP"
cd "$JVM_TMP"


# fix storage issues on nfs mounts
umask 000
$DAEMON -nodetach -user "$TOMCAT6_USER" -cp "$JSVC_CLASSPATH" \
    -outfile SYSLOG -errfile SYSLOG \
    -pidfile "$CATALINA_PID" $JAVA_OPTS "$BOOTSTRAP_CLASS"
