#!/bin/bash

docker-compose exec php-fpm php artisan view:clear
docker-compose exec php-fpm php artisan route:clear
docker-compose exec php-fpm php artisan config:clear
docker-compose exec php-fpm php artisan view:cache
docker-compose exec php-fpm php artisan route:cache
docker-compose exec php-fpm php artisan config:cache
docker-compose exec php-fpm php artisan queue:restart
