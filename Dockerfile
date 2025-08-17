# --- Composer stage (nur wenn composer.json existiert) ---
FROM composer:2 AS composer_build
WORKDIR /app
COPY . .
RUN if [ -f composer.json ]; then \
      composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader --no-scripts || true; \
    else \
      echo "No composer.json found, skipping composer install"; \
    fi

# --- Node assets (nur wenn package.json existiert) ---
FROM node:20-alpine AS node_build
WORKDIR /app
COPY . .
RUN if [ -f package.json ]; then \
      (npm ci || npm i) && (npm run build || true); \
    else \
      echo "No package.json found, skipping Node build"; \
    fi

# --- Runtime (php-fpm + nginx) ---
FROM php:8.2-fpm-alpine
WORKDIR /var/www/html
RUN apk add --no-cache nginx bash git curl libpng libjpeg-turbo freetype libzip \
    && docker-php-ext-install pdo pdo_mysql bcmath opcache

# App-Dateien & gebaute Assets
COPY --from=composer_build /app /var/www/html
COPY --from=node_build /app/public /var/www/html/public || true

# Permissions (Laravel/ähnlich)
RUN mkdir -p /var/www/html/storage /var/www/html/bootstrap/cache \
 && chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache

# Nginx config
COPY nginx.conf /etc/nginx/nginx.conf

# Start: nur die Befehle ausführen, die vorhanden sind
CMD bash -lc '\
  if [ -f .env.example ] && [ ! -f .env ]; then cp .env.example .env; fi; \
  if [ -f artisan ]; then php artisan key:generate || true; fi; \
  if [ -f artisan ]; then php artisan migrate --force || true; fi; \
  if [ -f artisan ]; then php artisan storage:link || true; fi; \
  php-fpm -D && nginx -g "daemon off;" \
'