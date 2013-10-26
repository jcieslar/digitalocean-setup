#!/bin/bash
# to run this type ./setup_do.sh
# http://linuxconfig.org/bash-scripting-tutorial

username=user_app_name
appname=your_app_name
domain=jcieslar.pl
ruby_v=2.0.0

# creat user
# echo -e "Hi, please type the username: \c "
# read username
adduser $username

# install rvm
su $username  << EOF
  whoami
  cd
  \curl -L https://get.rvm.io | bash -s stable --ruby
  source ~/.rvm/scripts/rvm
  type rvm | head -n 1
EOF
echo -n '[[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm" # Load RVM into a shell session *as a function*' >> /home/$username/.bashrc

# echo -e "Type Ruby version (e.g: 1.9.3): \c "
# read ruby_v
# setup default ruby version
su $username << EOF
  cd
  source ~/.rvm/scripts/rvm
  type rvm | head -n 1
  rvm use $ruby_v --default
  ruby -v
EOF

# echo -e "Your app name: \c "
# read appname
# echo -e "Your app domain \c "
# read domain

# configure unicorn for new app
echo "
upstream unicorn-$appname {
  server unix:/tmp/unicorn.$appname.sock;
}

server {
  listen 80;
  server_name $domain www.$domain;
  root /home/$username/$appname/current/public;

  location / {
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Real-IP  \$remote_addr;
    proxy_set_header Host \$http_host;
    proxy_redirect off;

    if (!-f \$request_filename) {
      proxy_pass http://unicorn-$appname;
      break;
    }
  }
}

" > /etc/nginx/sites-available/$domain

ln -s /etc/nginx/sites-available/$domain /etc/nginx/sites-enabled/$domain

# optional
# echo "/etc/init.d/nginx restart"

# unicorn start/stop configuration
echo "
#!/bin/sh
set -e

# Feel free to change any of the following variables for your app:
TIMEOUT=\${TIMEOUT-60}
APP_ROOT=/home/$username/$appname/current
APP_USER=$username
PID=\$APP_ROOT/tmp/pids/unicorn.pid
ENV=production
CMD=\"bundle exec unicorn_rails -E \$ENV -D -c \$APP_ROOT/config/unicorn.rb\"
action=\"\$1\"
set -u

old_pid=\"\$PID.oldbin\"

cd \$APP_ROOT || exit 1

sig () {
        test -s \"\$PID\" && kill -\$1 \`cat \$PID\`
}

oldsig () {
        test -s \$old_pid && kill -\$1 \`cat \$old_pid\`
}

case \$action in
start)
        sig 0 && echo >&2 \"Already running\" && exit 0
        su --login \$APP_USER -c \"\$CMD\"
        ;;
stop)
        sig QUIT && exit 0
        echo >&2 \"Not running\"
        ;;
force-stop)
        sig TERM && exit 0

        echo >&2 \"Not running\"
        ;;
restart|reload)
        sig HUP && echo reloaded OK && exit 0
        echo >&2 \"Couldn't reload, starting '\$CMD' instead\"
        su --login \$APP_USER -c \"\$CMD\"
        ;;
upgrade)
        if sig USR2 && sleep 2 && sig 0 && oldsig QUIT
        then
                n=\$TIMEOUT
                while test -s \$old_pid && test \$n -ge 0
                do
                        printf '.' && sleep 1 && n=\$(( \$n - 1 ))
                done
                echo

                if test \$n -lt 0 && test -s \$old_pid
                then
                        echo >&2 \"\$old_pid still exists after \$TIMEOUT seconds\"
                        exit 1
                fi
                exit 0
        fi
        echo >&2 \"Couldn't upgrade, starting '\$CMD' instead\"
        su --login \$APP_USER -c \"\$CMD\"
        ;;
reopen-logs)
        sig USR1
        ;;
*)
        echo >&2 \"Usage: \$0 \"
        exit 1
        ;;
esac
" > /etc/init.d/unicorn.$appname

chmod +x /etc/init.d/unicorn.$appname

# add ability to connect via ssh
mkdir /home/$username/.ssh/
cp .ssh/authorized_keys /home/$username/.ssh/authorized_keys
chown $username:$username /home/$username/.ssh/

# gnerating ssh key for new user
su $username << EOF
  cd
  ssh-keygen -t rsa
EOF

# create postgres user
#su -c "createuser $appname --superuser" -- postgres

exit
