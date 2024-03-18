(job '(next-minute (range 0 59 5))
     "/bin/bash /var/www/html/docker-scripts/update-app.sh >> /home/encryption/log/referral-factory/update.log 2>&1")
