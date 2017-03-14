#!/bin/bash

# Create a log pipe so non root can write to stdout
mkfifo -m 600 /tmp/logpipe
cat <> /tmp/logpipe 1>&2 &
chown -R nginx:nginx /tmp/logpipe

# Add new relic if key is present
if [ ! -z "$NEW_RELIC_LICENSE_KEY" ]; then
    newrelic-install install || exit 1
    nrsysmond-config --set license_key=${NEW_RELIC_LICENSE_KEY} || exit 1
    echo -e "\n[program:nrsysmond]\ncommand=nrsysmond -c /etc/newrelic/nrsysmond.cfg -l /dev/stdout -f\nautostart=true\nautorestart=true\npriority=0\nstdout_events_enabled=true\nstderr_events_enabled=true\nstdout_logfile=/dev/stdout\nstdout_logfile_maxbytes=0\nstderr_logfile=/dev/stderr\nstderr_logfile_maxbytes=0" >> /etc/supervisord.conf
else
    if [ -f /etc/php/7.1/fpm/conf.d/20-newrelic.ini ]; then
        rm -rf /etc/php/7.1/fpm/conf.d/20-newrelic.ini
    fi
    if [ -f /etc/php/7.1/cli/conf.d/20-newrelic.ini ]; then
        rm -rf /etc/php/7.1/cli/conf.d/20-newrelic.ini
    fi
    /etc/init.d/newrelic-daemon stop
fi

# Set custom webroot
if [ ! -z "$WEBROOT" ]; then
    webroot=$WEBROOT
    sed -i "s#root /var/www/html/web;#root ${webroot};#g" /etc/nginx/sites-available/default.conf
else
    webroot=/var/www/html
fi

# Set custom server name
if [ ! -z "$SERVERNAME" ]; then
    sed -i "s#server_name _;#server_name $SERVERNAME;#g" /etc/nginx/sites-available/default.conf
fi

# Composer
if [ -f /var/www/html/composer.json ]; then

cat > /var/www/html/app/config/config_prod.yml <<EOF
imports:
    - { resource: config.yml }
monolog:
    handlers:
        main:
            type: stream
            path:  "/tmp/logpipe"
            level: error
EOF
   
   if [ ! -z "$CONSUL_ENVIRONMENT" ]; then

cat > /var/www/html/app/config/parameters.yml <<EOF
parameters:
    consul_uri: https://$CONSUL_USERNAME:$CONSUL_PASSWORD@$CONSUL_URL
    consul_sections: ['$CONSUL_ENVIRONMENT/common', '$CONSUL_ENVIRONMENT/$CONSUL_APPLICATION']
EOF
    fi

    cd /var/www/html

    mkdir -p /var/www/html/var
    /usr/bin/composer install --no-interaction --no-dev --optimize-autoloader
    php app/console cache:clear --env=prod
    chown -R nginx:nginx /var/www/html/var
fi

# Start supervisord and services
/usr/bin/supervisord -n -c /etc/supervisord.conf
