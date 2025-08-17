# --- Composer stage ---
FROM composer:2 AS composer_build
WORKDIR /app
# Kopiere den gesamten Code, damit composer alles findet – ohne composer.lock zu erzwingen
COPY . .
# Installiere Abhängigkeiten (ohne Dev), falls kein lock vorhanden ist klappt das trotzdem
RUN composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader || true
RUN composer dump-autoload --optimize

# --- Node assets (optional, falls vorhanden) ---
FROM node:20-alpine AS node_build
WORKDIR /app
COPY . .
RUN [ -f package.json ] && (npm ci || npm i) || true
RUN [ -f package.json ] && (npm run build || true)

# --- Runtime (php-fpm) ---
FROM php:8.2-fpm-alpine
WORKDIR /var/www/html
RUN apk add --no-cache nginx supervisor bash git curl libpng libjpeg-turbo freetype libzip \
    && docker-php-ext-install pdo pdo_mysql bcmath opcache

# App-Dateien & gebaute Assets
COPY --from=composer_build /app /var/www/html
COPY --from=node_build /app/public /var/www/html/public
RUN chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache

# Nginx
COPY nginx.conf /etc/nginx/nginx.conf

# Start & App-Init
CMD bash -lc '\
  cp -n .env.example .env || true && \
  php artisan key:generate || true && \
  php artisan migrate --force || true && \
  php artisan storage:link || true && \
  php-fpm -D && \
  nginx -g "daemon off;" \
'